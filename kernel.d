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
    const(char)* s = "\n\nHello World!\n";
    for (int i = 0; s[i] != '\0'; i++) {
        putchar(s[i]);
    }
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
