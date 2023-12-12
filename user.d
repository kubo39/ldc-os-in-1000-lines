extern (C):

import ldc.attributes;
import ldc.llvmasm;

import common;

extern __gshared char* __stack_top;

noreturn exit()
{
    for (;;) {}
}

int syscall(int sysno, int arg0, int arg1, int arg2)
{
    return __asm!int(
        "ecall",
        "={a0},{a0},{a1},{a2},{a3},~{memory}",
        arg0, arg1, arg2, sysno
    );
}

void putchar(char ch)
{
    syscall(SYS_PUTCHAR, ch, 0, 0);
}

@section(".text.start")
@naked void start()
{
    __asm(`
        mv sp, $0
        call main
        call exit
    `, "r", &__stack_top);
}
