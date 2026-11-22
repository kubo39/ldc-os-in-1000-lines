module common;

import ldc.llvmasm;

extern (C):

enum SysNo : uint
{
    putchar = 1,
    getchar,
    exit,
    readFile,
    writeFile,
}

void putchar(char);
int getchar();
noreturn exit();
int readfile(const char*, char*, int);
int writefile(const char*, const char*, int);

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

int strcmp(const char* s1, const char* s2)
{
    char* p1 = cast(char*) s1;
    char* p2 = cast(char*) s2;
    while (*p1 && *p2)
    {
        if (*p1 != *p2)
        {
            break;
        }
        p1++;
        p2++;
    }

    return *p1 - *p2;
}

extern (D):

template toDecString(size_t n)
{
    static if (n < 10)
        enum toDecString = "0123456789"[n .. n + 1];
    else
        enum toDecString = toDecString!(n / 10) ~ toDecString!(n % 10);
}

void putStr(const(char)[] s)
{
    foreach (char c; s)
        putchar(c);
}

void putCStr(const(char)* s)
{
    while (*s)
        putchar(*s++);
}

void putDec(int value)
{
    uint magnitude = value;
    if (value < 0)
    {
        putchar('-');
        magnitude = -magnitude;
    }
    putDec(magnitude);
}

void putDec(uint magnitude)
{
    uint divisor = 1;
    while (magnitude / divisor > 9)
        divisor *= 10;

    while (divisor > 0)
    {
        putchar(cast(char)('0' + magnitude / divisor));
        magnitude %= divisor;
        divisor /= 10;
    }
}

void putHex(uint value)
{
    foreach_reverse (i; 0 .. 8)
    {
        uint nibble = (value >> (i * 4)) & 0xf;
        putchar("0123456789abcdef"[nibble]);
    }
}

void printf(string fmt, Args...)(Args args)
{
    enum segs = parseFormat!fmt();
    static assert(countArgs(segs) == Args.length,
        "printf: argument count does not match format: \"" ~ fmt ~ "\"");

    static foreach (seg; segs)
    {
        static if (seg.kind == Seg.Kind.literal)
            putStr(seg.lit);
        else
            putArg!(seg.kind, fmt)(args[seg.arg]);
    }
}

private:

struct Seg
{
    enum Kind : char
    {
        literal = 'L',
        dec = 'd',
        hex = 'x',
        str = 's',
    }

    Kind kind;
    string lit;
    size_t arg;
}

void putArg(Seg.Kind kind, string fmt, T)(T value)
{
    static if (kind == Seg.Kind.dec)
    {
        static assert(isInt32!T, "printf: %d expects an integer of 32 bits or less (got "
            ~ T.stringof ~ "): \"" ~ fmt ~ "\"");
        static if (__traits(isUnsigned, T))
            putDec(cast(uint) value);
        else
            putDec(cast(int) value);
    }
    else static if (kind == Seg.Kind.hex)
    {
        static assert(isInt32!T, "printf: %x expects an integer of 32 bits or less (got "
            ~ T.stringof ~ "): \"" ~ fmt ~ "\"");
        putHex(cast(uint) value);
    }
    else static if (kind == Seg.Kind.str)
    {
        static assert(is(T : const(char)[]) || is(T : const(char)*),
            "printf: %s expects a string, const(char)[] or const(char)* (got "
            ~ T.stringof ~ "): \"" ~ fmt ~ "\"");
        static if (is(T : const(char)[]))
            putStr(value);
        else
            putCStr(value);
    }
}

enum isInt32(T) = is(immutable T == immutable byte) || is(immutable T == immutable ubyte)
    || is(immutable T == immutable short) || is(immutable T == immutable ushort)
    || is(immutable T == immutable int) || is(immutable T == immutable uint);


size_t countSegs()(string fmt)
{
    size_t n = 0;
    size_t i = 0;
    while (i < fmt.length)
    {
        if (fmt[i] == '%')
        {
            i += 2;
        }
        else
        {
            while (i < fmt.length && fmt[i] != '%')
                i++;
        }
        n++;
    }
    return n;
}

Seg[countSegs(fmt)] parseFormat(string fmt)()
{
    Seg[countSegs(fmt)] segs;
    size_t n = 0;
    size_t arg = 0;
    size_t i = 0;
    while (i < fmt.length)
    {
        if (fmt[i] == '%')
        {
            if (i + 1 >= fmt.length)
                assert(false, "printf: format ends with '%': \"" ~ fmt ~ "\"");
            switch (fmt[i + 1])
            {
            case '%':
                segs[n] = Seg(Seg.Kind.literal, "%");
                break;
            case 'd':
                segs[n] = Seg(Seg.Kind.dec, null, arg++);
                break;
            case 'x':
                segs[n] = Seg(Seg.Kind.hex, null, arg++);
                break;
            case 's':
                segs[n] = Seg(Seg.Kind.str, null, arg++);
                break;
            default:
                assert(false, "printf: unsupported format specifier %" ~ fmt[i + 1 .. i + 2]
                    ~ ": \"" ~ fmt ~ "\"");
            }
            i += 2;
        }
        else
        {
            const start = i;
            while (i < fmt.length && fmt[i] != '%')
                i++;
            segs[n] = Seg(Seg.Kind.literal, fmt[start .. i]);
        }
        n++;
    }
    return segs;
}

size_t countArgs(size_t N)(const Seg[N] segs)
{
    size_t n = 0;
    foreach (seg; segs)
    {
        if (seg.kind != Seg.Kind.literal)
            n++;
    }
    return n;
}
