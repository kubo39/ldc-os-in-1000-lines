import ldc.attributes;
import ldc.llvmasm;

import common;

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

void panic(string fmt)()
{
    printf("PANIC: %s:%d: " ~ fmt ~ "\n", __FILE__.ptr, __LINE__);
    for (;;) {}
}

align(1) struct trap_frame
{
align(1):
    uint ra;
    uint gp;
    uint tp;
    uint t0;
    uint t1;
    uint t2;
    uint t3;
    uint t4;
    uint t5;
    uint t6;
    uint a0;
    uint a1;
    uint a2;
    uint a3;
    uint a4;
    uint a5;
    uint a6;
    uint a7;
    uint s0;
    uint s1;
    uint s2;
    uint s3;
    uint s4;
    uint s5;
    uint s6;
    uint s7;
    uint s8;
    uint s9;
    uint s10;
    uint s11;
    uint sp;
}

T READ_CSR(string reg, T)()
{
    return __asm!T("csrr $0, " ~ reg, "=r");
}

void WRITE_CSR(string reg)(void* value)
{
    __asm("csrw " ~ reg ~ ", $0", "r", value);
}

enum SCAUSE_ECALL = 8;

void handle_trap(trap_frame* f)
{
    uint scause = READ_CSR!("scause", uint)();
    uint stval = READ_CSR!("stval", uint)();
    uint user_pc = READ_CSR!("sepc", uint)();

    if (scause == SCAUSE_ECALL)
    {
        handle_syscall(f);
        user_pc += 4;
    }
    else
    {
        printf("scause: %x\n", scause);
        printf("stval: %x\n", stval);
        printf("user_pc: %x\n", user_pc);

        panic!("unexpected trap");
    }

    WRITE_CSR!("sepc")(cast(void*)user_pc);
}

void handle_syscall(trap_frame* f)
{
    switch (f.a3)
    {
    case SYS_PUTCHAR:
        putchar(cast(char) f.a0);
        break;
    default:
        panic!("unexpected syscall");
    }
}

align(4) @naked void kernel_entry()
{
    __asm(`
        # 実行中プロセスのカーネルスタックをsscratchから取り出す
        # tmp = sp; sp = sscratch; sscratch = tmp;
        csrrw sp, sscratch, sp

        addi sp, sp, -4 * 31
        sw ra,  4 * 0(sp)
        sw gp,  4 * 1(sp)
        sw tp,  4 * 2(sp)
        sw t0,  4 * 3(sp)
        sw t1,  4 * 4(sp)
        sw t2,  4 * 5(sp)
        sw t3,  4 * 6(sp)
        sw t4,  4 * 7(sp)
        sw t5,  4 * 8(sp)
        sw t6,  4 * 9(sp)
        sw a0,  4 * 10(sp)
        sw a1,  4 * 11(sp)
        sw a2,  4 * 12(sp)
        sw a3,  4 * 13(sp)
        sw a4,  4 * 14(sp)
        sw a5,  4 * 15(sp)
        sw a6,  4 * 16(sp)
        sw a7,  4 * 17(sp)
        sw s0,  4 * 18(sp)
        sw s1,  4 * 19(sp)
        sw s2,  4 * 20(sp)
        sw s3,  4 * 21(sp)
        sw s4,  4 * 22(sp)
        sw s5,  4 * 23(sp)
        sw s6,  4 * 24(sp)
        sw s7,  4 * 25(sp)
        sw s8,  4 * 26(sp)
        sw s9,  4 * 27(sp)
        sw s10, 4 * 28(sp)
        sw s11, 4 * 29(sp)

        # 例外発生時のspを取り出して保存
        csrr a0, sscratch
        sw a0, 4 * 30(sp)

        # カーネルスタックを設定し直す
        addi a0, sp, 4 * 31
        csrw sscratch, a0

        mv a0, sp
        call handle_trap

        lw ra,  4 * 0(sp)
        lw gp,  4 * 1(sp)
        lw tp,  4 * 2(sp)
        lw t0,  4 * 3(sp)
        lw t1,  4 * 4(sp)
        lw t2,  4 * 5(sp)
        lw t3,  4 * 6(sp)
        lw t4,  4 * 7(sp)
        lw t5,  4 * 8(sp)
        lw t6,  4 * 9(sp)
        lw a0,  4 * 10(sp)
        lw a1,  4 * 11(sp)
        lw a2,  4 * 12(sp)
        lw a3,  4 * 13(sp)
        lw a4,  4 * 14(sp)
        lw a5,  4 * 15(sp)
        lw a6,  4 * 16(sp)
        lw a7,  4 * 17(sp)
        lw s0,  4 * 18(sp)
        lw s1,  4 * 19(sp)
        lw s2,  4 * 20(sp)
        lw s3,  4 * 21(sp)
        lw s4,  4 * 22(sp)
        lw s5,  4 * 23(sp)
        lw s6,  4 * 24(sp)
        lw s7,  4 * 25(sp)
        lw s8,  4 * 26(sp)
        lw s9,  4 * 27(sp)
        lw s10, 4 * 28(sp)
        lw s11, 4 * 29(sp)
        lw sp,  4 * 30(sp)
        sret
    `, "");
}

extern __gshared char* __free_ram;
extern __gshared char* __free_ram_end;

alias paddr_t = uint;
alias vaddr_t = uint;

enum uint PAGE_SIZE = 4096;

__gshared paddr_t next_paddr = 0;

paddr_t alloc_pages(uint n)
{
    if (next_paddr == 0)
    {
        next_paddr = cast(paddr_t) &__free_ram;
    }
    paddr_t paddr = next_paddr;
    next_paddr += n * PAGE_SIZE;

    if (next_paddr > cast(paddr_t) &__free_ram_end)
    {
        panic!("Out of memory");
    }

    memset(cast(void*) paddr, 0, n * PAGE_SIZE);
    return paddr;
}

enum PROC_MAX = 8;   // 最大プロセス数
enum PROC_UNUSED = 0;   // 未使用のプロセス管理構造体
enum PROC_RUNNABLE = 1;   // 実行可能なプロセス

struct process
{
    int pid;
    int state;
    vaddr_t sp; // コンテキストスイッチ時のスタックポインタ
    uint* page_table;
    ubyte[8192] stack; // カーネルスタック
}

__gshared process[PROC_MAX] procs;

@naked void switch_context(uint* prev_sp, uint* next_sp)
{
    pragma(inline, false);
    __asm(`
        addi sp, sp, -13 * 4
        sw ra,  0  * 4(sp)
        sw s0,  1  * 4(sp)
        sw s1,  2  * 4(sp)
        sw s2,  3  * 4(sp)
        sw s3,  4  * 4(sp)
        sw s4,  5  * 4(sp)
        sw s5,  6  * 4(sp)
        sw s6,  7  * 4(sp)
        sw s7,  8  * 4(sp)
        sw s8,  9  * 4(sp)
        sw s9,  10 * 4(sp)
        sw s10, 11 * 4(sp)
        sw s11, 12 * 4(sp)
        sw sp, (a0)
        lw sp, (a1)
        lw ra,  0  * 4(sp)
        lw s0,  1  * 4(sp)
        lw s1,  2  * 4(sp)
        lw s2,  3  * 4(sp)
        lw s3,  4  * 4(sp)
        lw s4,  5  * 4(sp)
        lw s5,  6  * 4(sp)
        lw s6,  7  * 4(sp)
        lw s7,  8  * 4(sp)
        lw s8,  9  * 4(sp)
        lw s9,  10 * 4(sp)
        lw s10, 11 * 4(sp)
        lw s11, 12 * 4(sp)
        addi sp, sp, 13 * 4
        ret
    `, "");
}

extern __gshared char* __kernel_base;

process* create_process(const void* image, size_t image_size)
{
    process* proc = null;
    int i;
    for (i = 0; i < PROC_MAX; i++)
    {
        if (procs[i].state == PROC_UNUSED)
        {
            proc = &procs[i];
            break;
        }
    }

    if (!proc)
    {
        panic!("No free process slots");
    }

    // switch_context() で復帰できるように、
    // スタックに呼び出し先保存レジスタを積む
    uint* sp = cast(uint*) &(proc.stack[proc.stack.sizeof - 1]);
    *--sp = 0;     // s11
    *--sp = 0;     // s10
    *--sp = 0;     // s9
    *--sp = 0;     // s8
    *--sp = 0;     // s7
    *--sp = 0;     // s6
    *--sp = 0;     // s5
    *--sp = 0;     // s4
    *--sp = 0;     // s3
    *--sp = 0;     // s2
    *--sp = 0;     // s1
    *--sp = 0;     // s0
    *--sp = cast(uint) &user_entry;    // ra

    uint* page_table = cast(uint*) alloc_pages(1);

    // カーネルのページをマッピングする
    for (paddr_t paddr = cast(paddr_t) &__kernel_base;
         paddr < cast(paddr_t) &__free_ram_end; paddr += PAGE_SIZE)
    {
        map_page(page_table, paddr, paddr, PAGE_R | PAGE_W | PAGE_X);
    }

    // ユーザーのページをマッピングする
    for (uint off; off < image_size; off += PAGE_SIZE)
    {
        paddr_t page = alloc_pages(1);
        memcpy(cast(void*) page, image + off, PAGE_SIZE);
        map_page(page_table, USER_BASE + off, page,
                 PAGE_U | PAGE_R | PAGE_W | PAGE_X);
    }

    // 各フィールドを初期化
    proc.pid = i + 1;
    proc.state = PROC_RUNNABLE;
    proc.sp = cast(uint) sp;
    proc.page_table = page_table;
    return proc;
}

__gshared process* proc_a;
__gshared process* proc_b;

void proc_a_entry()
{
    printf("starting process A\n");
    while (true)
    {
        putchar('A');
        yield();

        foreach (i; 0 .. 30000000)
        {
            __asm("nop", "");
        }
    }
}

void proc_b_entry()
{
    printf("starting process B\n");
    while (true)
    {
        putchar('B');
        yield();

        foreach (i; 0 .. 30000000)
        {
            __asm("nop", "");
        }
    }
}

__gshared process* current_proc; // 現在実行中のプロセス
__gshared process *idle_proc;    // アイドルプロセス

void yield()
{
    // 実行可能なプロセスを探す
    process* next = idle_proc;
    foreach (i; 0 .. PROC_MAX)
    {
        process* proc = &procs[(current_proc.pid + i) % PROC_MAX];
        if (proc.state == PROC_RUNNABLE && proc.pid > 0)
        {
            next = proc;
            break;
        }
    }

    // 現在実行中のプロセス以外に、実行可能なプロセスがない。
    // 戻って処理を続行する
    if (next == current_proc)
        return;

    // コンテキストスイッチ
    process* prev = current_proc;
    current_proc = next;

    __asm(`
            sfence.vma
            csrw satp, $0
            sfence.vma
            csrw sscratch, $1
        `,
        "r,r",
        (SATP_SV32 | (cast(uint) next.page_table / PAGE_SIZE)),
        &next.stack[next.stack.sizeof-1]
    );

    switch_context(&prev.sp, &next.sp);
}

enum uint SATP_SV32 = 1 << 31;
enum uint PAGE_V = 1 << 0;   // 有効化ビット
enum uint PAGE_R = 1 << 1;   // 読み込み可能
enum uint PAGE_W = 1 << 2;   // 書き込み可能
enum uint PAGE_X = 1 << 3;   // 実行可能
enum uint PAGE_U = 1 << 4;   // ユーザーモードでアクセス可能

void map_page(uint* table1, uint vaddr, paddr_t paddr, uint flags)
{
    if ((vaddr & (PAGE_SIZE - 1)) != 0)
    {
        panic!("unaligned vaddr");
    }

    if ((paddr & (PAGE_SIZE - 1)) != 0)
    {
        panic!("unaligned paddr");
    }

    uint vpn1 = (vaddr >> 22) & 0x3ff;
    if ((table1[vpn1] & PAGE_V) == 0)
    {
        // 2段目のページテーブルが存在しないので作成する
        uint pt_paddr = alloc_pages(1);
        table1[vpn1] = ((pt_paddr / PAGE_SIZE) << 10) | PAGE_V;
    }

    // 2段目のページテーブルにエントリを追加する
    uint vpn0 = (vaddr >> 12) & 0x3ff;
    uint* table0 = cast(uint*) ((table1[vpn1] >> 10) * PAGE_SIZE);
    table0[vpn0] = ((paddr / PAGE_SIZE) << 10) | flags | PAGE_V;
}

enum USER_BASE = 0x1000000;

extern __gshared char* _binary_shell_bin_start;
extern __gshared char* _binary_shell_bin_size;

enum SSTATUS_SPIE = 1 << 5;

@naked void user_entry()
{
    __asm(`
        csrw sepc, $0
        csrw sstatus, $1
        sret
    `, "r,r", USER_BASE, SSTATUS_SPIE);
}

void kernel_main()
{
    memset(&__bss, 0, &__bss_end - &__bss);
    printf("\n\nHello, World!\n");
    printf("1 + 2 = %d, %x\n", 1 + 2, 0x1234abcd);

    WRITE_CSR!"stvec"(&kernel_entry);

    idle_proc = create_process(null, 0);
    idle_proc.pid = -1;
    current_proc = idle_proc;

    create_process(&_binary_shell_bin_start, cast(size_t) &_binary_shell_bin_size);

    yield();
    panic!("switched to idle process\n");

    paddr_t paddr0 = alloc_pages(2);
    paddr_t paddr1 = alloc_pages(1);
    printf("alloc_pages test: paddr0=%x\n", paddr0);
    printf("alloc_pages test: paddr1=%x\n", paddr1);

    panic!("booted!");
    printf("unreachable here!\n");

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
