/*
 * vm.S - stage 2: RC4 + a small bytecode VM.
 *
 * check2() sits behind the same switch-recovery trick as check1(): an affected
 * Hex-Rays shows only "int check2(const char *input) { return 0; }" while the
 * CPU always runs case 0, which does three things:
 *
 *   1. rebuilds the RC4 key on the stack  ("Kam30SA", stored ^ 0x77 so that
 *      `strings` shows nothing),
 *   2. RC4-decrypts a 32-byte blob from .rodata; the plaintext is flag2,
 *   3. runs a bytecode program on a tiny VM that compares the user's input
 *      against that plaintext and accumulates the differences.
 *
 * The VM has 8 one-byte registers and fixed 4-byte instructions:
 *
 *   [ op | a | b | c ]
 *
 *   0x11 IMM  ra, b        regs[a] = b
 *   0x22 LDI  ra, rb       regs[a] = input[regs[b]]
 *   0x33 LDE  ra, rb       regs[a] = expected[regs[b]]
 *   0x44 XOR  ra, rb       regs[a] ^= regs[b]
 *   0x55 OR   ra, rb       regs[a] |= regs[b]
 *   0x66 INC  ra           regs[a]++
 *   0x77 JB   ra, b, c     if regs[a] < b: pc = c
 *   0x88 RET  ra           return regs[a]
 *
 * The program it runs:
 *
 *   00  IMM r0, 0              ; i   = 0
 *   01  IMM r1, 0              ; acc = 0
 *   02  LDI r2, r0             ; a = input[i]
 *   03  LDE r3, r0             ; b = expected[i]
 *   04  XOR r2, r3             ; a ^= b
 *   05  OR  r1, r2             ; acc |= a
 *   06  INC r0                 ; i++
 *   07  JB  r0, 32, 02         ; while (i < 32)
 *   08  LDI r2, r0             ; input[32] must be the NUL terminator
 *   09  OR  r1, r2
 *   10  RET r1                 ; 0 == accepted
 */

    .intel_syntax noprefix

    .section .rodata
    .align 4
.Ltable:
    .long   .Lcase_real - .Ltable      /* case 0: what actually runs        */
    .long   .Lcase_stub - .Ltable      /* case 1: what the decompiler shows */

    .align 8
.Lflag2_ct:                            /* RC4("Kam30SA", flag2), 32 bytes */
    .byte   0xd6,0x4e,0x88,0x6e,0xe5,0xe9,0xac,0x45,0x41
    .byte   0xa7,0x8e,0xde,0x25,0x19,0x98,0xcc,0x73,0xcb
    .byte   0x64,0xba,0x45,0x83,0xcc,0x44,0xc6,0x14,0x44
    .byte   0x39,0xae,0xda,0x02,0xa7
.Lrc4_key:                             /* "Kam30SA" ^ 0x77 */
    .byte   0x3c,0x16,0x1a,0x44,0x47,0x24,0x36
    .align 4
.Lvm_prog:
    .byte   0x11,0x00,0x00,0x00        /* IMM r0, 0      */
    .byte   0x11,0x01,0x00,0x00        /* IMM r1, 0      */
    .byte   0x22,0x02,0x00,0x00        /* LDI r2, r0     */
    .byte   0x33,0x03,0x00,0x00        /* LDE r3, r0     */
    .byte   0x44,0x02,0x03,0x00        /* XOR r2, r3     */
    .byte   0x55,0x01,0x02,0x00        /* OR  r1, r2     */
    .byte   0x66,0x00,0x00,0x00        /* INC r0         */
    .byte   0x77,0x00,0x20,0x02        /* JB  r0, 32, 02 */
    .byte   0x22,0x02,0x00,0x00        /* LDI r2, r0     */
    .byte   0x55,0x01,0x02,0x00        /* OR  r1, r2     */
    .byte   0x88,0x01,0x00,0x00        /* RET r1         */

    .equ    S_BOX,    0                /* stack layout inside check2 */
    .equ    EXPECTED, 256
    .equ    RC4_KEY,  288
    .equ    VM_REGS,  296
    .equ    FRAME,    336

    .equ    KEY_LEN,  7
    .equ    FLAG2_LEN,32

    .text
    .globl  check2
    .type   check2, @function
check2:                                /* rdi = input, returns 0 on success */
    endbr64
    push    rbx
    sub     rsp, FRAME
    mov     rbx, rdi

    mov     rax, rsp
    shr     rax, 63
    lea     r10, [rip + .Ltable]
    movsxd  r11, dword ptr [r10 + rax*4]
    mov     eax, 1
    add     r11, r10
    jmp     r11

/* ---- case 0: everything below is invisible to an affected decompiler ---- */
.Lcase_real:

/* ---- rebuild the RC4 key: key[i] = table[i] ^ 0x77 ---- */
    lea     rsi, [rip + .Lrc4_key]
    xor     ecx, ecx
1:  movzx   eax, byte ptr [rsi + rcx]
    xor     eax, 0x77
    mov     byte ptr [rsp + rcx + RC4_KEY], al
    inc     rcx
    cmp     rcx, KEY_LEN
    jb      1b

/* ---- RC4 key-scheduling: S[i] = i ---- */
    xor     ecx, ecx
2:  mov     byte ptr [rsp + rcx + S_BOX], cl
    inc     ecx
    cmp     ecx, 256
    jb      2b

/* ---- RC4 KSA: j = (j + S[i] + key[i % 7]) & 0xff, swap ---- */
    xor     ecx, ecx                   /* i */
    xor     edx, edx                   /* j */
    xor     r9d, r9d                   /* i mod 7 */
3:  movzx   eax, byte ptr [rsp + rcx + S_BOX]
    add     edx, eax
    movzx   r8d, byte ptr [rsp + r9 + RC4_KEY]
    add     edx, r8d
    and     edx, 0xff
    movzx   r10d, byte ptr [rsp + rdx + S_BOX]
    mov     byte ptr [rsp + rcx + S_BOX], r10b
    mov     byte ptr [rsp + rdx + S_BOX], al
    inc     r9d
    cmp     r9d, KEY_LEN
    jb      4f
    xor     r9d, r9d
4:  inc     ecx
    cmp     ecx, 256
    jb      3b

/* ---- RC4 PRGA: decrypt the blob into the expected buffer ---- */
    lea     rsi, [rip + .Lflag2_ct]
    xor     ecx, ecx                   /* i */
    xor     edx, edx                   /* j */
    xor     r9d, r9d                   /* output index */
5:  inc     ecx
    and     ecx, 0xff
    movzx   eax, byte ptr [rsp + rcx + S_BOX]
    add     edx, eax
    and     edx, 0xff
    movzx   r10d, byte ptr [rsp + rdx + S_BOX]
    mov     byte ptr [rsp + rcx + S_BOX], r10b
    mov     byte ptr [rsp + rdx + S_BOX], al
    add     eax, r10d
    and     eax, 0xff
    movzx   r11d, byte ptr [rsp + rax + S_BOX]
    movzx   r8d, byte ptr [rsi + r9]
    xor     r8d, r11d
    mov     byte ptr [rsp + r9 + EXPECTED], r8b
    inc     r9d
    cmp     r9d, FLAG2_LEN
    jb      5b

/* ---- run the bytecode ---- */
    mov     qword ptr [rsp + VM_REGS], 0
    lea     r8, [rip + .Lvm_prog]
    xor     r9d, r9d                   /* pc, in instructions */

.Lvm_next:
    lea     r10, [r8 + r9*4]
    movzx   eax, byte ptr [r10]        /* op */
    movzx   ecx, byte ptr [r10 + 1]    /* a  */
    movzx   edx, byte ptr [r10 + 2]    /* b  */
    movzx   r11d, byte ptr [r10 + 3]   /* c  */
    inc     r9d

    cmp     eax, 0x11
    je      .Lop_imm
    cmp     eax, 0x22
    je      .Lop_ldi
    cmp     eax, 0x33
    je      .Lop_lde
    cmp     eax, 0x44
    je      .Lop_xor
    cmp     eax, 0x55
    je      .Lop_or
    cmp     eax, 0x66
    je      .Lop_inc
    cmp     eax, 0x77
    je      .Lop_jb
    cmp     eax, 0x88
    je      .Lop_ret
    jmp     .Lreject                   /* bad opcode */

.Lop_imm:
    mov     byte ptr [rsp + rcx + VM_REGS], dl
    jmp     .Lvm_next
.Lop_ldi:
    movzx   eax, byte ptr [rsp + rdx + VM_REGS]
    movzx   eax, byte ptr [rbx + rax]
    mov     byte ptr [rsp + rcx + VM_REGS], al
    jmp     .Lvm_next
.Lop_lde:
    movzx   eax, byte ptr [rsp + rdx + VM_REGS]
    movzx   eax, byte ptr [rsp + rax + EXPECTED]
    mov     byte ptr [rsp + rcx + VM_REGS], al
    jmp     .Lvm_next
.Lop_xor:
    movzx   eax, byte ptr [rsp + rdx + VM_REGS]
    xor     byte ptr [rsp + rcx + VM_REGS], al
    jmp     .Lvm_next
.Lop_or:
    movzx   eax, byte ptr [rsp + rdx + VM_REGS]
    or      byte ptr [rsp + rcx + VM_REGS], al
    jmp     .Lvm_next
.Lop_inc:
    inc     byte ptr [rsp + rcx + VM_REGS]
    jmp     .Lvm_next
.Lop_jb:
    movzx   eax, byte ptr [rsp + rcx + VM_REGS]
    cmp     eax, edx
    jae     .Lvm_next
    mov     r9d, r11d
    jmp     .Lvm_next
.Lop_ret:
    movzx   eax, byte ptr [rsp + rcx + VM_REGS]
    test    eax, eax
    jz      .Laccept
.Lreject:
    mov     eax, 1
    jmp     .Lout
.Laccept:
    xor     eax, eax
    jmp     .Lout

/* ---- case 1: the only thing the pseudocode shows ---- */
.Lcase_stub:
    xor     eax, eax
.Lout:
    add     rsp, FRAME
    pop     rbx
    ret
    .size   check2, .-check2

    .section .note.GNU-stack,"",@progbits
