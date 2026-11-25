extern (C):

import ldc.attributes;
import ldc.llvmasm;

import common;

int syscall(int sysno, int arg0, int arg1, int arg2)
{
    // LLVMはmemory clobberを単に無視し、またLDCは常にインラインアセンブラで
    // ReadWriteMemoryな関数属性が付与され、これはmemory clobberが付与される
    // のと同じ効果があるため `~{memory}` は不要だが、わかりやすさのために
    // 残しておく。
    return __asm!int(
        "ecall",
        "={a0},{a0},{a1},{a2},{a3},~{memory}",
        arg0, arg1, arg2, sysno
    );
}

void putchar(char ch)
{
    syscall(SysNo.putchar, ch, 0, 0);
}

int getchar()
{
    return syscall(SysNo.getchar, 0, 0, 0);
}

noreturn exit()
{
    syscall(SysNo.exit, 0, 0, 0);
    for (;;) {}
}

noreturn __assert(const(char)* msg, const(char)* file, int line)
{
    printf!"assertion failed: %s:%d: %s\n"(file, line, msg);
    backtrace();
    exit();
}

pragma(inline, false)
void backtrace()
{
    import ldc.intrinsics;
    auto fp = cast(uint) llvm_frameaddress(0);
    int depth = 0;
    while (fp != 0 && (fp & 3) == 0 && depth < 16)
    {
        uint ra = *cast(uint*) (fp - 4);
        if (ra == 0)
            break;
        printf!"  #%d:%x\n"(depth, ra - 2);
        fp = *cast(uint*) (fp - 8);
        depth++;
    }
}

int readfile(const char* filename, char* buf, int len)
{
    return syscall(SysNo.readFile, cast(int) filename, cast(int) buf, len);
}

int writefile(const char* filename, const char* buf, int len)
{
    return syscall(SysNo.writeFile, cast(int) filename, cast(int) buf, len);
}

@section(".text.start")
@naked void start()
{
    __asm(`
        la sp, __stack_top
        li fp, 0
        li ra, 0
        call main
        call exit
    `, "");
}
