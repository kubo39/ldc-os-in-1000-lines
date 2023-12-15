extern (C):

import ldc.attributes;
import ldc.llvmasm;

import common;

extern __gshared char* __stack_top;

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

int getchar()
{
    return syscall(SYS_GETCHAR, 0, 0, 0);
}

noreturn exit()
{
    syscall(SYS_EXIT, 0, 0, 0);
    for (;;) {} // 念のため
}

int readfile(const char* filename, char* buf, int len)
{
    return syscall(SYS_READFILE, cast(int) filename, cast(int) buf, len);
}

int writefile(const char* filename, const char* buf, int len)
{
    return syscall(SYS_WRITEFILE, cast(int) filename, cast(int) buf, len);
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
