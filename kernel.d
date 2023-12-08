import ldc.attributes;
import ldc.llvmasm;

extern (C):

extern __gshared char* __bss;
extern __gshared char* __bss_end;
extern __gshared char* __stack_top;

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
    for (;;) {}
}

@section(".text.boot")
@naked void boot()
{
    __asm(`
        mv sp, $0
        j kernel_main
    `, "r", &__stack_top);
}
