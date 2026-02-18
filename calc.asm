; calc.asm - simple integer kalkulator (Windows x64, NASM)
; - REPL petlja: radi dok ne upišeš q/quit/exit
; - Podržava infix:  12 + 5
; - Podržava prefix: pow 2 10
; - Podržava "ans" kao operand (zadnji rezultat)
; - Operacije:
;   Binarne: + - * / % & | ^ << >> shl shr pow gcd lcm
;   Unarne:  abs neg not
;
; Build (MSYS2 UCRT64):
;   nasm -f win64 calc.asm -o calc.obj
;   gcc  calc.obj -o calc.exe

default rel

extern printf
extern scanf
extern sscanf
extern strcmp
extern strtoll
extern fflush

%macro VCALL 1
    ; Spremi register argumente u home slotove (Windows x64 varargs)
    mov [rsp+0x00], rcx
    mov [rsp+0x08], rdx
    mov [rsp+0x10], r8
    mov [rsp+0x18], r9
    xor eax, eax            ; AL=0 (nema XMM argumenata)
    call %1
%endmacro

section .data
    banner      db "ByteCore ASM Kalkulator (int64) - upisi 'help' za upute.", 13, 10, 0
    fmt_prompt  db "[ans=%lld] > ", 0
    fmt_line    db " %255[^", 13, 10, "]", 0
    fmt_tok     db "%31s %31s %31s", 0

    fmt_res     db "Rezultat: %lld", 13, 10, 0
    fmt_errsyn  db "Greska: sintaksa. Primjeri: 12 + 5  |  pow 2 10  |  abs -5", 13, 10, 0
    fmt_errop   db "Greska: nepodrzan operator.", 13, 10, 0
    fmt_errnum  db "Greska: neispravan broj: '%s'", 13, 10, 0
    fmt_div0    db "Greska: dijeljenje s nulom.", 13, 10, 0
    fmt_powneg  db "Greska: exponent za pow mora biti >= 0.", 13, 10, 0

    helptext    db  "Upute:",13,10
                db  "  - Infix:   a op b      (npr: 12 + 5)",13,10
                db  "  - Prefix:  op a b      (npr: pow 2 10, gcd 24 18, shl 1 5)",13,10
                db  "  - Unarno:  op a        (abs, neg, not)  (npr: abs -5)",13,10
                db  "  - ans:     koristi zadnji rezultat (npr: ans * 3)",13,10
                db  "Operacije:",13,10
                db  "  +  -  *  /  %",13,10
                db  "  &  |  ^",13,10
                db  "  <<  >>   (ili: shl / shr)",13,10
                db  "  pow  gcd  lcm",13,10
                db  "Komande: help, q, quit, exit",13,10,0

   
    s_help  db "help",0
    s_q     db "q",0
    s_quit  db "quit",0
    s_exit  db "exit",0
    s_ans   db "ans",0

section .bss
    line    resb 256
    t1      resb 32
    t2      resb 32
    t3      resb 32

    ans     resq 1
    endptr  resq 1 

section .text
global main

; ------------------------------------------------------------
; parse_operand(token_ptr) -> RAX=value, EDX=success(1/0)
; RCX = pokazivac na token (npr "123" ili "ans")
; ------------------------------------------------------------
parse_operand:
    sub rsp, 0x28                 ; shadow space + poravnanje

    ; Spremi originalni pointer na token na stack (jer C pozivi mogu pregaziti registre)
    mov [rsp+0x20], rcx           ; koristimo zadnjih 8 bajtova (iza shadow prostora)

    ; strcmp(token, "ans")
    mov rcx, [rsp+0x20]
    mov rdx, s_ans
    call strcmp
    test eax, eax
    jne .not_ans

    mov rax, [ans]
    mov edx, 1
    add rsp, 0x28
    ret

.not_ans:
    ; strtoll(token, &endptr, 10)
    mov rcx, [rsp+0x20]
    lea rdx, [endptr]
    mov r8d, 10
    call strtoll

    ; Validacija:
    ; - mora potrositi barem 1 znak (endptr != token)
    ; - i mora zavrsiti na '\0'
    mov r9, [endptr]
    cmp r9, [rsp+0x20]
    je .bad
    cmp byte [r9], 0
    jne .bad

    mov edx, 1
    add rsp, 0x28
    ret

.bad:
    xor eax, eax
    xor edx, edx
    add rsp, 0x28
    ret

; ------------------------------------------------------------
; is_binop(ptr) -> AL=1 ako je binarni operator, inace AL=0
; RCX = ptr na string
; (bez pozivanja C funkcija: brze + nema stack komplikacija)
; ------------------------------------------------------------
is_binop:
    ; Jednoznakovni operatori
    mov al, [rcx]
    mov dl, [rcx+1]
    cmp dl, 0
    jne .check_twochar

    cmp al, '+'
    je .yes
    cmp al, '-'
    je .yes
    cmp al, '*'
    je .yes
    cmp al, '/'
    je .yes
    cmp al, '%'
    je .yes
    cmp al, '&'
    je .yes
    cmp al, '|'
    je .yes
    cmp al, '^'
    je .yes
    jmp .no

.check_twochar:
    ; "<<"
    cmp al, '<'
    jne .chk_gt
    cmp byte [rcx+1], '<'
    jne .chk_words
    cmp byte [rcx+2], 0
    je .yes
    jmp .no

.chk_gt:
    ; ">>"
    cmp al, '>'
    jne .chk_words
    cmp byte [rcx+1], '>'
    jne .chk_words
    cmp byte [rcx+2], 0
    je .yes
    jmp .no

.chk_words:
    ; "shl" / "shr" / "pow" / "gcd" / "lcm"
    mov al, [rcx]
    cmp al, 's'
    jne .chk_pow
    cmp byte [rcx+1], 'h'
    jne .no
    cmp byte [rcx+2], 'l'
    je .shl_ok
    cmp byte [rcx+2], 'r'
    je .shr_ok
    jmp .no
.shl_ok:
    cmp byte [rcx+3], 0
    je .yes
    jmp .no
.shr_ok:
    cmp byte [rcx+3], 0
    je .yes
    jmp .no

.chk_pow:
    cmp al, 'p'
    jne .chk_gcd
    cmp byte [rcx+1], 'o'
    jne .no
    cmp byte [rcx+2], 'w'
    jne .no
    cmp byte [rcx+3], 0
    je .yes
    jmp .no

.chk_gcd:
    cmp al, 'g'
    jne .chk_lcm
    cmp byte [rcx+1], 'c'
    jne .no
    cmp byte [rcx+2], 'd'
    jne .no
    cmp byte [rcx+3], 0
    je .yes
    jmp .no

.chk_lcm:
    cmp al, 'l'
    jne .no
    cmp byte [rcx+1], 'c'
    jne .no
    cmp byte [rcx+2], 'm'
    jne .no
    cmp byte [rcx+3], 0
    je .yes
    jmp .no

.yes:
    mov al, 1
    ret
.no:
    xor eax, eax
    ret


; main

main:
   
    push rbx
    sub rsp, 0x30

    mov qword [ans], 0

    
    lea rcx, [banner]
    VCALL printf

.repl:
    
    lea rcx, [fmt_prompt]
    mov rdx, [ans]
    VCALL printf

    
    xor ecx, ecx 
    call fflush

    
    mov byte [t1], 0
    mov byte [t2], 0
    mov byte [t3], 0

    
    lea rcx, [fmt_line]
    lea rdx, [line]
    xor eax, eax
    VCALL scanf
    cmp eax, 1
    jne .done

    
    lea rcx, [line]
    lea rdx, [fmt_tok]
    lea r8,  [t1]
    lea r9,  [t2]
    lea rax, [t3]
    mov [rsp+0x20], rax 
    xor eax, eax
    VCALL sscanf 

    test eax, eax
    jle .repl

    
    cmp eax, 1
    jne .not_one

    ; help?
    lea rcx, [t1]
    lea rdx, [s_help]
    call strcmp
    test eax, eax
    jne .chk_quit1
    lea rcx, [helptext]
    VCALL printf
    jmp .repl

.chk_quit1:
    lea rcx, [t1]
    lea rdx, [s_q]
    call strcmp
    test eax, eax
    je .done

    lea rcx, [t1]
    lea rdx, [s_quit]
    call strcmp
    test eax, eax
    je .done

    lea rcx, [t1]
    lea rdx, [s_exit]
    call strcmp
    test eax, eax
    je .done

    
    lea rcx, [fmt_errsyn]
    VCALL printf
    jmp .repl

.not_one:
    
    cmp eax, 2
    jne .three_or_more

   
    lea rcx, [t2]
    call parse_operand
    test edx, edx
    jne .unary_ok

    
    lea rcx, [fmt_errnum]
    lea rdx, [t2]
    VCALL printf
    jmp .repl

.unary_ok:
    
    mov r10, rax 

   
    cmp byte [t1], 'a'
    jne .un_neg
    cmp byte [t1+1], 'b'
    jne .un_bad
    cmp byte [t1+2], 's'
    jne .un_bad
    cmp byte [t1+3], 0
    jne .un_bad

    ; abs(a)
    mov rax, r10
    test rax, rax
    jns .un_store
    neg rax
    jmp .un_store

.un_neg:
    ; neg
    cmp byte [t1], 'n'
    jne .un_not
    cmp byte [t1+1], 'e'
    jne .un_bad
    cmp byte [t1+2], 'g'
    jne .un_bad
    cmp byte [t1+3], 0
    jne .un_bad

    mov rax, r10
    neg rax
    jmp .un_store

.un_not:
    ; not
    cmp byte [t1], 'n'
    jne .un_bad
    cmp byte [t1+1], 'o'
    jne .un_bad
    cmp byte [t1+2], 't'
    jne .un_bad
    cmp byte [t1+3], 0
    jne .un_bad

    mov rax, r10
    not rax
    jmp .un_store

.un_bad:
    lea rcx, [fmt_errop]
    VCALL printf
    jmp .repl

.un_store:
    mov [ans], rax
    lea rcx, [fmt_res]
    mov rdx, [ans]
    VCALL printf
    jmp .repl

.three_or_more:
    
    lea rcx, [t1]
    call is_binop
    test al, al
    jne .prefix

   
    lea rcx, [t2]
    call is_binop
    test al, al
    jne .infix

    
    lea rcx, [fmt_errsyn]
    VCALL printf
    jmp .repl

.prefix:
   
    lea rcx, [t2]
    call parse_operand
    test edx, edx
    jne .p_a_ok
    lea rcx, [fmt_errnum]
    lea rdx, [t2]
    VCALL printf
    jmp .repl
.p_a_ok:
    mov r10, rax

    lea rcx, [t3]
    call parse_operand
    test edx, edx
    jne .p_b_ok
    lea rcx, [fmt_errnum]
    lea rdx, [t3]
    VCALL printf
    jmp .repl
.p_b_ok:
    mov r11, rax 

    lea r8, [t1]
    jmp .do_bin

.infix:
    
    lea rcx, [t1]
    call parse_operand
    test edx, edx
    jne .i_a_ok
    lea rcx, [fmt_errnum]
    lea rdx, [t1]
    VCALL printf
    jmp .repl
.i_a_ok:
    mov r10, rax

    lea rcx, [t3]
    call parse_operand
    test edx, edx
    jne .i_b_ok
    lea rcx, [fmt_errnum]
    lea rdx, [t3]
    VCALL printf
    jmp .repl
.i_b_ok:
    mov r11, rax 

    lea r8, [t2] 

.do_bin:

    mov al, [r8]
    cmp byte [r8+1], 0
    jne .bin_two_or_word

    cmp al, '+'
    je .op_add
    cmp al, '-'
    je .op_sub
    cmp al, '*'
    je .op_mul
    cmp al, '/'
    je .op_div
    cmp al, '%'
    je .op_mod
    cmp al, '&'
    je .op_and
    cmp al, '|'
    je .op_or
    cmp al, '^'
    je .op_xor
    jmp .op_bad

.bin_two_or_word:
    ; "<<"
    cmp byte [r8], '<'
    jne .chk_shift_r
    cmp byte [r8+1], '<'
    jne .chk_shift_r
    cmp byte [r8+2], 0
    je .op_shl
.chk_shift_r:
    ; ">>"
    cmp byte [r8], '>'
    jne .chk_words2
    cmp byte [r8+1], '>'
    jne .chk_words2
    cmp byte [r8+2], 0
    je .op_shr

.chk_words2:
    cmp byte [r8], 's'
    jne .chk_pow2
    cmp byte [r8+1], 'h'
    jne .op_bad
    cmp byte [r8+2], 'l'
    je .w_shl
    cmp byte [r8+2], 'r'
    je .w_shr
    jmp .op_bad
.w_shl:
    cmp byte [r8+3], 0
    je .op_shl
    jmp .op_bad
.w_shr:
    cmp byte [r8+3], 0
    je .op_shr
    jmp .op_bad

.chk_pow2:
    cmp byte [r8], 'p'
    jne .chk_gcd2
    cmp byte [r8+1], 'o'
    jne .op_bad
    cmp byte [r8+2], 'w'
    jne .op_bad
    cmp byte [r8+3], 0
    je .op_pow
    jmp .op_bad

.chk_gcd2:
    cmp byte [r8], 'g'
    jne .chk_lcm2
    cmp byte [r8+1], 'c'
    jne .op_bad
    cmp byte [r8+2], 'd'
    jne .op_bad
    cmp byte [r8+3], 0
    je .op_gcd
    jmp .op_bad

.chk_lcm2:
    cmp byte [r8], 'l'
    jne .op_bad
    cmp byte [r8+1], 'c'
    jne .op_bad
    cmp byte [r8+2], 'm'
    jne .op_bad
    cmp byte [r8+3], 0
    je .op_lcm
    jmp .op_bad

.op_add:
    mov rax, r10
    add rax, r11
    jmp .store_print
.op_sub:
    mov rax, r10
    sub rax, r11
    jmp .store_print
.op_mul:
    mov rax, r10
    imul rax, r11
    jmp .store_print

.op_div:
    test r11, r11
    jz .err_div0
    mov rax, r10
    cqo
    idiv r11 
    jmp .store_print

.op_mod:
    test r11, r11
    jz .err_div0
    mov rax, r10
    cqo
    idiv r11
    mov rax, rdx  
    jmp .store_print

.op_and:
    mov rax, r10
    and rax, r11
    jmp .store_print
.op_or:
    mov rax, r10
    or  rax, r11
    jmp .store_print
.op_xor:
    mov rax, r10
    xor rax, r11
    jmp .store_print

.op_shl:
    
    mov rax, r10
    mov rcx, r11
    and ecx, 63
    shl rax, cl
    jmp .store_print

.op_shr:
    ; aritmeticki desni shift za signed int64
    mov rax, r10
    mov rcx, r11
    and ecx, 63
    sar rax, cl
    jmp .store_print

.op_pow:
   
    test r11, r11
    js .err_powneg

    mov rax, 1 
    mov r9,  r10 
    mov rdx, r11

.pow_loop:
    test rdx, rdx
    jz .store_print
    test rdx, 1
    jz .pow_skip_mul
    imul rax, r9
.pow_skip_mul:
    imul r9, r9
    shr rdx, 1
    jmp .pow_loop

.op_gcd:
   
    mov rax, r10
    mov rbx, r11
   
    test rax, rax
    jns .gcd_absb
    neg rax
.gcd_absb:
    test rbx, rbx
    jns .gcd_loop
    neg rbx

.gcd_loop:
    test rbx, rbx
    jz .gcd_done
    cqo
    idiv rbx
    mov rax, rbx
    mov rbx, rdx
    jmp .gcd_loop

.gcd_done:
   
    jmp .store_print

.op_lcm:
    
    test r10, r10
    jz .lcm_zero
    test r11, r11
    jz .lcm_zero

    
    mov rax, r10
    mov rbx, r11

    test rax, rax
    jns .lcm_absb
    neg rax
.lcm_absb:
    test rbx, rbx
    jns .lcm_gcd_loop
    neg rbx

.lcm_gcd_loop:
    test rbx, rbx
    jz .lcm_gcd_done
    cqo
    idiv rbx
    mov rax, rbx
    mov rbx, rdx
    jmp .lcm_gcd_loop

.lcm_gcd_done:
    mov r9, rax 

   
    mov rax, r10
    test rax, rax
    jns .lcm_abs_a_ok
    neg rax
.lcm_abs_a_ok:
    mov rdx, r11
    test rdx, rdx
    jns .lcm_abs_b_ok
    neg rdx
.lcm_abs_b_ok:

    
    cqo
    idiv r9 
    imul rax, rdx
    jmp .store_print

.lcm_zero:
    xor eax, eax
    jmp .store_print

.op_bad:
    lea rcx, [fmt_errop]
    VCALL printf
    jmp .repl

.err_div0:
    lea rcx, [fmt_div0]
    VCALL printf
    jmp .repl

.err_powneg:
    lea rcx, [fmt_powneg]
    VCALL printf
    jmp .repl

.store_print:
    mov [ans], rax
    lea rcx, [fmt_res]
    mov rdx, [ans]
    VCALL printf
    jmp .repl

.done:
    add rsp, 0x30
    pop rbx
    xor eax, eax
    ret
