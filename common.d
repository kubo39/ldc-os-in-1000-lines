module common;

extern (C):

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
