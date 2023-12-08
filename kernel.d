import ldc.attributes;
import ldc.llvmasm;

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

void* memset(void* buf, char c, size_t n)
{
    char* p = cast(char*) buf;
    while (n--)
    {
        *p++ = c;
    }
    return buf;
}

void kernel_main()
{
    memset(__bss, 0, cast(size_t) __bss_end - cast(size_t) __bss);
    printf("\n\nHello, World!\n");
    printf("1 + 2 = %d, %x\n", 1 + 2, 0x1234abcd);
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
