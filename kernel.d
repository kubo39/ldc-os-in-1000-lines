import ldc.attributes;
import ldc.llvmasm;

import common;

extern (C):

extern __gshared char* __bss;
extern __gshared char* __bss_end;
extern __gshared char* __stack_top;

struct sbiret
{
    long error;
    long value;
}

sbiret sbi_call(long arg0, long arg1, long arg2, long arg3, long arg4,
                long arg5, long fid, long eid)
{
    return __asm!sbiret(
        "ecall",
        "={a0},={a1},{a0},{a1},{a2},{a3},{a4},{a5},{a6},{a7},~{memory}",
        arg0, arg1, arg2, arg3, arg4, arg5, fid, eid
    );
}

void putchar(char ch)
{
    sbi_call(ch, 0, 0, 0, 0, 0, 0, 1 /* Console Putchar */);
}

alias va_list = imported!"core.stdc.stdarg".va_list;
alias va_start = imported!"core.stdc.stdarg".va_start;
alias va_end = imported!"core.stdc.stdarg".va_end;
alias va_arg = imported!"core.stdc.stdarg".va_arg;

void printf(const(char)* fmt, ...)
{
    va_list vargs;
    va_start(vargs, fmt);

    while (*fmt)
    {
        if (*fmt == '%')
        {
            fmt++;
            switch (*fmt)
            {
            case '\0':
                putchar('%');
                goto end;
            case '%':
                putchar('%');
                break;
            case 's':
            {
                const(char)* s = va_arg!(const(char)*)(vargs);
                while (*s)
                {
                    putchar(*s);
                    s++;
                }
                break;
            }
            case 'd':
            {
                int value = va_arg!int(vargs);
                if (value < 0)
                {
                    putchar('-');
                    value = -value;
                }

                int divisor = 1;
                while (value / divisor > 9)
                {
                    divisor *= 10;
                }

                while (divisor > 0)
                {
                    putchar('0' + value / divisor);
                    value %= divisor;
                    divisor /= 10;
                }

                break;
            }
            case 'x':
            {
                int value = va_arg!int(vargs);
                for (int i = 7; i >= 0; i--)
                {
                    int nibble = (value >> (i * 4)) & 0xf;
                    putchar("0123456789abcdef"[nibble]);
                }
                break;
            }
            default:
                break;
            }
        }
        else
        {
            putchar(*fmt);
        }

        fmt++;
    }

end:
    va_end(vargs);
}

void panic(string fmt)()
{
    printf("PANIC: %s:%d: " ~ fmt ~ "\n", __FILE__.ptr, __LINE__);
    for (;;) {}
}

align(1) struct trap_frame
{
align(1):
    uint ra;
    uint gp;
    uint tp;
    uint t0;
    uint t1;
    uint t2;
    uint t3;
    uint t4;
    uint t5;
    uint t6;
    uint a0;
    uint a1;
    uint a2;
    uint a3;
    uint a4;
    uint a5;
    uint a6;
    uint a7;
    uint s0;
    uint s1;
    uint s2;
    uint s3;
    uint s4;
    uint s5;
    uint s6;
    uint s7;
    uint s8;
    uint s9;
    uint s10;
    uint s11;
    uint sp;
}

T READ_CSR(string reg, T)()
{
    return __asm!T("csrr $0, " ~ reg, "=r");
}

void WRITE_CSR(string reg)(void* value)
{
    __asm("csrw " ~ reg ~ ", $0", "r", value);
}

void handle_trap(trap_frame* f)
{
    uint scause = READ_CSR!("scause", uint)();
    uint stval = READ_CSR!("stval", uint)();
    uint user_pc = READ_CSR!("sepc", uint)();

    printf("scause: %x\n", scause);
    printf("stval: %x\n", stval);
    printf("user_pc: %x\n", user_pc);

    panic!("unexpected trap");
}

align(4) @naked void kernel_entry()
{
    __asm(`
        csrw sscratch, sp
        addi sp, sp, -4 * 31
        sw ra,  4 * 0(sp)
        sw gp,  4 * 1(sp)
        sw tp,  4 * 2(sp)
        sw t0,  4 * 3(sp)
        sw t1,  4 * 4(sp)
        sw t2,  4 * 5(sp)
        sw t3,  4 * 6(sp)
        sw t4,  4 * 7(sp)
        sw t5,  4 * 8(sp)
        sw t6,  4 * 9(sp)
        sw a0,  4 * 10(sp)
        sw a1,  4 * 11(sp)
        sw a2,  4 * 12(sp)
        sw a3,  4 * 13(sp)
        sw a4,  4 * 14(sp)
        sw a5,  4 * 15(sp)
        sw a6,  4 * 16(sp)
        sw a7,  4 * 17(sp)
        sw s0,  4 * 18(sp)
        sw s1,  4 * 19(sp)
        sw s2,  4 * 20(sp)
        sw s3,  4 * 21(sp)
        sw s4,  4 * 22(sp)
        sw s5,  4 * 23(sp)
        sw s6,  4 * 24(sp)
        sw s7,  4 * 25(sp)
        sw s8,  4 * 26(sp)
        sw s9,  4 * 27(sp)
        sw s10, 4 * 28(sp)
        sw s11, 4 * 29(sp)

        csrr a0, sscratch
        sw a0, 4 * 30(sp)

        mv a0, sp
        call handle_trap

        lw ra,  4 * 0(sp)
        lw gp,  4 * 1(sp)
        lw tp,  4 * 2(sp)
        lw t0,  4 * 3(sp)
        lw t1,  4 * 4(sp)
        lw t2,  4 * 5(sp)
        lw t3,  4 * 6(sp)
        lw t4,  4 * 7(sp)
        lw t5,  4 * 8(sp)
        lw t6,  4 * 9(sp)
        lw a0,  4 * 10(sp)
        lw a1,  4 * 11(sp)
        lw a2,  4 * 12(sp)
        lw a3,  4 * 13(sp)
        lw a4,  4 * 14(sp)
        lw a5,  4 * 15(sp)
        lw a6,  4 * 16(sp)
        lw a7,  4 * 17(sp)
        lw s0,  4 * 18(sp)
        lw s1,  4 * 19(sp)
        lw s2,  4 * 20(sp)
        lw s3,  4 * 21(sp)
        lw s4,  4 * 22(sp)
        lw s5,  4 * 23(sp)
        lw s6,  4 * 24(sp)
        lw s7,  4 * 25(sp)
        lw s8,  4 * 26(sp)
        lw s9,  4 * 27(sp)
        lw s10, 4 * 28(sp)
        lw s11, 4 * 29(sp)
        lw sp,  4 * 30(sp)
        sret
    `, "");
}

void kernel_main()
{
    memset(__bss, 0, cast(size_t) &__bss_end - cast(size_t) &__bss);
    printf("\n\nHello, World!\n");
    printf("1 + 2 = %d, %x\n", 1 + 2, 0x1234abcd);

    WRITE_CSR!"stvec"(&kernel_entry);
    __asm("unimp", "");

    panic!("booted!");
    printf("unreachable here!\n");

    for (;;)
    {
        __asm("wfi", "");
    }
}

@section(".text.boot")
@naked void boot()
{
    __asm(`
        mv sp, $0
        j kernel_main
    `, "r", &__stack_top);
}
