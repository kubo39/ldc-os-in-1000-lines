import ldc.attributes;
import ldc.llvmasm;

extern (C):

extern __gshared char* __stack_top;

noreturn exit()
{
    for (;;) {}
}

void putchar(char c) {}

@section(".text.start")
@naked void start()
{
    __asm(`
        mv sp, $0
        call main
        call exit
    `, "r", &__stack_top);
}
