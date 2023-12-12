module common;

extern (C):

alias va_list = imported!"core.stdc.stdarg".va_list;
alias va_start = imported!"core.stdc.stdarg".va_start;
alias va_end = imported!"core.stdc.stdarg".va_end;
alias va_arg = imported!"core.stdc.stdarg".va_arg;

void putchar(char);

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
    ubyte* p = cast(ubyte*) buf;
    while (n--)
    {
        *p++ = c;
    }
    return buf;
}

void* memcpy(void* dst, const(void)* src, size_t n)
{
    ubyte* d = cast(ubyte*) dst;
    const(ubyte)* s = cast(const(ubyte)*) src;
    while (n--)
    {
        *d++ = *s++;
    }
    return dst;
}

char* strcpy(char* dst, const(char)* src)
{
    char* d = dst;
    while (*src)
    {
        *d++ = *src++;
    }
    *d = '\0';
    return dst;
}

int strcmp(const(char)* s1, const(char)* s2)
{
    while (*s1 && *s2)
    {
        if (*s1 != *s2)
        {
            break;
        }
        s1++;
        s2++;
    }

    return *(cast(char*)s1) - *(cast(char*)s2);
}
