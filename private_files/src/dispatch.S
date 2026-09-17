/*
 * dispatch.S - stage 1: the whole flag1 check lives inside a switch case that
 * affected Hex-Rays versions delete.
 *
 * Technique:
 *   https://github.com/lityrgia/anti_decompil_poc
 *   https://community.hex-rays.com/t/wrong-switch-decompilation/610
 *
 *   mov    rax, rsp
 *   shr    rax, 63          ; always 0 in user mode -> case 0 runs
 *   lea    r10, [rip+table]
 *   movsxd r11, [r10+rax*4] ; offset already latched into R11
 *   mov    eax, 1           ; <-- index register clobbered AFTER the load
 *   add    r11, r10
 *   jmp    r11
 *
 * The CPU jumps to case 0. Hex-Rays (< 9.5) takes the clobbered EAX as the
 * switch input, concludes the index is constant 1, drops case 0 as unreachable
 * and decompiles only the return stub of case 1:
 *
 *   int check1(const char *input) { return 0; }
 *
 * Which reads as "flag1 always accepted". Nothing below - the rolling-key XOR
 * comparison and its table - ever shows up in the pseudocode.
 *
 * The input IS flag1: enc[i] == flag1[i] ^ (0x30 + i).
 */

    .intel_syntax noprefix

    .section .rodata
    .align 4
.Ltable:
    .long   .Lcase_real - .Ltable      /* case 0: what actually runs        */
    .long   .Lcase_stub - .Ltable      /* case 1: what the decompiler shows */

    .align 8
.Lflag1_enc:                           /* flag1[i] ^ (0x30 + i), + terminator */
    .byte   0x7f,0x7c,0x7c,0x7a,0x77,0x61,0x70,0x4c,0x4b
    .byte   0x4e,0x0b,0x4f,0x5f,0x55,0x61,0x5c,0x74,0x32
    .byte   0x71,0x1c,0x2c,0x74,0x22,0x23,0x7b,0x27,0x15
    .byte   0x2d,0x3e,0x7d,0x23,0x10,0x61,0x35,0x66,0x2e
    .byte   0x54

    .equ    FLAG1_LEN, 36
    .equ    FLAG1_KEY, 0x30

    .text
    .globl  check1
    .type   check1, @function
check1:
    endbr64
    push    rbx
    mov     rbx, rdi                   /* rbx = user input */

    mov     rax, rsp
    shr     rax, 63
    lea     r10, [rip + .Ltable]
    movsxd  r11, dword ptr [r10 + rax*4]
    mov     eax, 1
    add     r11, r10
    jmp     r11

/* ---- case 0: the real check, invisible to an affected decompiler ---- */
.Lcase_real:
    lea     rsi, [rip + .Lflag1_enc]
    xor     ecx, ecx
    mov     r8d, FLAG1_KEY             /* rolling key, one step per char */
1:  movzx   edx, byte ptr [rbx + rcx]
    xor     edx, r8d                   /* input[i] ^ (0x30 + i) */
    movzx   eax, byte ptr [rsi + rcx]
    cmp     dl, al
    jne     .Lfail
    inc     r8d
    inc     rcx
    cmp     rcx, FLAG1_LEN + 1         /* the +1 forces the NUL terminator */
    jb      1b

    xor     eax, eax                   /* 0 = accepted */
    jmp     .Ldone
.Lfail:
    mov     eax, 1                     /* 1 = rejected */
    jmp     .Ldone

/* ---- case 1: the only thing the pseudocode shows ---- */
.Lcase_stub:
    xor     eax, eax
.Ldone:
    pop     rbx
    ret
    .size   check1, .-check1

    .section .note.GNU-stack,"",@progbits
