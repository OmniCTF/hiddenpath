/*
 * say.S - the two verdicts, behind the same switch-recovery trick.
 *
 * "Nice" and "Get good" are kept XOR-ed with a rolling key (0x5A + i) and
 * decrypted onto the stack right before puts(), so `strings` gives nothing.
 * The decryption itself sits in case 0 of the dispatcher, so an affected
 * Hex-Rays shows only:
 *
 *   void say(int failed) { ; }
 */

    .intel_syntax noprefix

    .section .rodata
    .align 4
.Ltable:
    .long   .Lcase_real - .Ltable      /* case 0: what actually runs        */
    .long   .Lcase_stub - .Ltable      /* case 1: what the decompiler shows */

.Lmsg_ok:                              /* "Nice"     ^ (0x5A + i) */
    .byte   0x14,0x32,0x3f,0x38
.Lmsg_bad:                             /* "Get good" ^ (0x5A + i) */
    .byte   0x1d,0x3e,0x28,0x7d,0x39,0x30,0x0f,0x05

    .equ    MSG_KEY,     0x5a
    .equ    MSG_OK_LEN,  4
    .equ    MSG_BAD_LEN, 8

    .text
    .globl  say
    .type   say, @function
say:                                   /* edi = 0 -> "Nice", else "Get good" */
    endbr64
    sub     rsp, 24

    mov     rax, rsp
    shr     rax, 63
    lea     r10, [rip + .Ltable]
    movsxd  r11, dword ptr [r10 + rax*4]
    mov     eax, 1
    add     r11, r10
    jmp     r11

/* ---- case 0: the real code ---- */
.Lcase_real:
    test    edi, edi
    jne     .Lbad
    lea     rsi, [rip + .Lmsg_ok]
    mov     r9d, MSG_OK_LEN
    jmp     .Lgo
.Lbad:
    lea     rsi, [rip + .Lmsg_bad]
    mov     r9d, MSG_BAD_LEN
.Lgo:
    xor     ecx, ecx
    mov     r8d, MSG_KEY
1:  movzx   eax, byte ptr [rsi + rcx]
    xor     eax, r8d                   /* msg[i] ^ (0x5A + i) */
    mov     byte ptr [rsp + rcx], al
    inc     r8d
    inc     rcx
    cmp     rcx, r9
    jb      1b
    mov     byte ptr [rsp + rcx], 0
    mov     rdi, rsp
    call    puts@PLT
    jmp     .Ldone

/* ---- case 1: the only thing the pseudocode shows ---- */
.Lcase_stub:
    xor     eax, eax
.Ldone:
    add     rsp, 24
    ret
    .size   say, .-say

    .section .note.GNU-stack,"",@progbits
