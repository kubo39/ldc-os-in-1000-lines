extern (C):

import core.volatile;

import ldc.attributes;
import ldc.intrinsics;
import ldc.llvmasm;

import common;

alias alignUp = imported!"core.stdc.stdarg".alignUp;

extern __gshared ubyte __bss;
extern __gshared ubyte __bss_end;
extern __gshared ubyte __stack_top;

struct sbiret
{
    int error;
    int value;
}

sbiret sbi_call(int arg0, int arg1, int arg2, int arg3, int arg4,
                int arg5, int fid, int eid)
{
    // LLVMはmemory clobberを単に無視し、またLDCは常にインラインアセンブラで
    // ReadWriteMemoryな関数属性が付与され、これはmemory clobberが付与される
    // のと同じ効果があるため `~{memory}` は不要だが、わかりやすさのために
    // 残しておく。
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

int getchar()
{
    pragma(inline, false);
    sbiret ret = sbi_call(0, 0, 0, 0, 0, 0, 0, 2);
    return ret.error;
}

void panic(string fmt)()
{
    printf("PANIC: %s:%d: " ~ fmt ~ "\n", __FILE__.ptr, __LINE__);
    for (;;) {}
}

file* fs_lookup(const char* filename)
{
    for (int i = 0; i < FILES_MAX; i++)
    {
        file* file = &files[i];
        if (!strcmp(file.name.ptr, filename))
        {
            return file;
        }
    }

    return null;
}

struct trap_frame
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
    case SYS_GETCHAR:
        while (true)
        {
            int ch = getchar();
            if (ch >= 0)
            {
                f.a0 = cast(uint) ch;
                break;
            }

            yield();
        }
        break;
    case SYS_EXIT:
        printf("process %d exited\n", current_proc.pid);
        current_proc.state = PROC_EXITED;
        yield();
        panic!("unreachable");
        break;
    case SYS_READFILE:
    case SYS_WRITEFILE:
        const char* filename = cast(const char*) f.a0;
        char* buf = cast(char*) f.a1;
        int len = f.a2;
        file* file = fs_lookup(filename);
        if (file is null)
        {
            printf("file not found: %s\n", filename);
            f.a0 = -1;
            break;
        }

        if (len > cast(int) file.data.sizeof)
        {
            len = file.size;
        }

        if (f.a3 == SYS_WRITEFILE)
        {
            memcpy(file.data.ptr, buf, len);
            file.size = len;
            fs_flush();
        }
        else
        {
            memcpy(buf, file.data.ptr, len);
        }

        f.a0 = len;
        break;
    default:
        panic!("unexpected syscall");
    }
}

@naked void kernel_entry()
{
    __asm(`
        .balign 4
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

extern __gshared ubyte __free_ram;
extern __gshared ubyte __free_ram_end;

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
enum PROC_EXITED = 2;

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

extern __gshared ubyte __kernel_base;

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
    map_page(page_table, VIRTIO_BLK_PADDR, VIRTIO_BLK_PADDR, PAGE_R | PAGE_W);

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

__gshared process* current_proc; // 現在実行中のプロセス
__gshared process* idle_proc;    // アイドルプロセス

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

extern __gshared ubyte _binary_shell_bin_start;
extern __gshared ubyte _binary_shell_bin_size;

enum SSTATUS_SPIE = 1 << 5;
enum SSTATUS_SUM = 1 << 18;

@naked void user_entry()
{
    __asm(`
        csrw sepc, $0
        csrw sstatus, $1
        sret
    `, "r,r", USER_BASE, SSTATUS_SPIE | SSTATUS_SUM);
}

enum uint SECTOR_SIZE       = 512;
enum uint VIRTQ_ENTRY_NUM   = 16;
enum uint VIRTIO_DEVICE_BLK = 2;
enum uint VIRTIO_BLK_PADDR = 0x10001000;
enum uint VIRTIO_REG_MAGIC        = 0x00;
enum uint VIRTIO_REG_VERSION      = 0x04;
enum uint VIRTIO_REG_DEVICE_ID    = 0x08;
enum uint VIRTIO_REG_QUEUE_SEL    = 0x30;
enum uint VIRTIO_REG_QUEUE_NUM_MAX = 0x34;
enum uint VIRTIO_REG_QUEUE_NUM    = 0x38;
enum uint VIRTIO_REG_QUEUE_ALIGN  = 0x3c;
enum uint VIRTIO_REG_QUEUE_PFN    = 0x40;
enum uint VIRTIO_REG_QUEUE_READY  = 0x44;
enum uint VIRTIO_REG_QUEUE_NOTIFY = 0x50;
enum uint VIRTIO_REG_DEVICE_STATUS = 0x70;
enum uint VIRTIO_REG_DEVICE_CONFIG = 0x100;
enum uint VIRTIO_STATUS_ACK      = 1;
enum uint VIRTIO_STATUS_DRIVER   = 2;
enum uint VIRTIO_STATUS_DRIVER_OK = 4;
enum uint VIRTIO_STATUS_FEAT_OK  = 8;
enum uint VIRTQ_DESC_F_NEXT         = 1;
enum uint VIRTQ_DESC_F_WRITE        = 2;
enum uint VIRTQ_AVAIL_F_NO_INTERRUPT = 1;
enum uint VIRTIO_BLK_T_IN  = 0;
enum uint VIRTIO_BLK_T_OUT = 1;

struct virtq_desc
{
align(1):
    ulong addr;
    uint len;
    ushort flags;
    ushort next;
}

struct virtq_avail
{
align(1):
    ushort flags;
    ushort index;
    ushort[VIRTQ_ENTRY_NUM] ring;
}

struct virtq_used_elem
{
align(1):
    uint id;
    uint len;
}

struct virtq_used
{
align(1):
    ushort flags;
    ushort index;
    virtq_used_elem[VIRTQ_ENTRY_NUM] ring;
}

struct virtio_virtq
{
align(1):
    virtq_desc[VIRTQ_ENTRY_NUM] descs;
    virtq_avail avail;
    align(PAGE_SIZE) virtq_used used;
    int queue_index;
    ushort* used_index;
    ushort last_used_index;
}

struct virtio_blk_req
{
align(1):
    // 1つ目のディスクリプタ: デバイスからは読み込み専用
    uint type;
    uint reserved;
    ulong sector;

    // 2つ目のディスクリプタ: 読み込み処理の場合は、デバイスから書き込み可 (VIRTQ_DESC_F_WRITE)
    ubyte[512] data;

    // 3つ目のディスクリプタ: デバイスから書き込み可 (VIRTQ_DESC_F_WRITE)
    ubyte status;
}

uint virtio_reg_read32(uint offset)
{
    return volatileLoad(cast(uint*) (VIRTIO_BLK_PADDR + offset));
}

ulong virtio_reg_read64(uint offset)
{
    return volatileLoad(cast(ulong*) (VIRTIO_BLK_PADDR + offset));
}

void virtio_reg_write32(uint offset, uint value)
{
    volatileStore(cast(uint*) (VIRTIO_BLK_PADDR + offset), value);
}

void virtio_reg_fetch_and_or32(uint offset, uint value)
{
    virtio_reg_write32(offset, virtio_reg_read32(offset) | value);
}

__gshared virtio_virtq* blk_request_vq;
__gshared virtio_blk_req* blk_req;
__gshared paddr_t blk_req_paddr;
__gshared uint blk_capacity;

void virtio_blk_init()
{
    if (virtio_reg_read32(VIRTIO_REG_MAGIC) != 0x74726976)
    {
        panic!("virtio: invalid magic value");
    }
    if (virtio_reg_read32(VIRTIO_REG_VERSION) != 1)
    {
        panic!("virtio: invalid version");
    }
    if (virtio_reg_read32(VIRTIO_REG_DEVICE_ID) != VIRTIO_DEVICE_BLK)
    {
        panic!("virtio: invalid device id");
    }

    // 1. Reset the device.
    virtio_reg_write32(VIRTIO_REG_DEVICE_STATUS, 0);
    // 2. Set the ACKNOWLEDGE status bit: the guest OS has noticed the device.
    virtio_reg_fetch_and_or32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_ACK);
    // 3. Set the DRIVER status bit.
    virtio_reg_fetch_and_or32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_DRIVER);
    // 5. Set the FEATURES_OK status bit.
    virtio_reg_fetch_and_or32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_FEAT_OK);
    // 7. Perform device-specific setup, including discovery of virtqueues for the device
    blk_request_vq = virtq_init(0);
    // 8. Set the DRIVER_OK status bit.
    virtio_reg_write32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_DRIVER_OK);

    // ディスクの容量を取得
    blk_capacity = cast(uint) (virtio_reg_read64(VIRTIO_REG_DEVICE_CONFIG + 0) * SECTOR_SIZE);
    printf("virtio-blk: capacity is %d bytes\n", blk_capacity);

    // デバイスへの処理要求を格納する領域を確保
    blk_req_paddr = alloc_pages(alignUp!(PAGE_SIZE)((*blk_req).sizeof) / PAGE_SIZE);
    blk_req = cast(virtio_blk_req*) blk_req_paddr;
}

virtio_virtq* virtq_init(uint index)
{
    paddr_t virtq_paddr = alloc_pages(alignUp!(PAGE_SIZE)(virtio_virtq.sizeof) / PAGE_SIZE);
    virtio_virtq* vq = cast(virtio_virtq*) virtq_paddr;
    vq.queue_index = index;
    vq.used_index = cast(ushort*) &vq.used.index;
    // 1. Select the queue writing its index (first queue is 0) to QueueSel.
    virtio_reg_write32(VIRTIO_REG_QUEUE_SEL, index);
    // 5. Notify the device about the queue size by writing the size to QueueNum.
    virtio_reg_write32(VIRTIO_REG_QUEUE_NUM, VIRTQ_ENTRY_NUM);
    // 6. Notify the device about the used alignment by writing its value in bytes to QueueAlign.
    virtio_reg_write32(VIRTIO_REG_QUEUE_ALIGN, 0);  
    // 7. Write the physical number of the first page of the queue to the QueuePFN register.
    virtio_reg_write32(VIRTIO_REG_QUEUE_PFN, virtq_paddr);
    return vq;
}

// デバイスに新しいリクエストがあることを通知する。desc_indexは、新しいリクエストの
// 先頭ディスクリプタのインデックス。
void virtq_kick(virtio_virtq* vq, int desc_index)
{
    pragma(inline, false);
    vq.avail.ring[vq.avail.index % VIRTQ_ENTRY_NUM] = cast(ushort) desc_index;
    vq.avail.index++;
    // オリジナルに合わせるためにCrossThreadを指定
    llvm_memory_fence(DefaultOrdering, SynchronizationScope.CrossThread);
    virtio_reg_write32(VIRTIO_REG_QUEUE_NOTIFY, vq.queue_index);
    vq.last_used_index++;
}

// デバイスが処理中のリクエストがあるかどうかを返す。
bool virtq_is_busy(virtio_virtq* vq)
{
    return vq.last_used_index != volatileLoad(vq.used_index);
}

// virtio-blkデバイスの読み書き。
void read_write_disk(void* buf, uint sector, int is_write)
{
    if (sector >= blk_capacity / SECTOR_SIZE)
    {
        printf("virtio: tried to read/write sector=%d, but capacity is %d\n",
              sector, blk_capacity / SECTOR_SIZE);
        return;
    }

    // virtio-blkの仕様に従って、リクエストを構築する
    blk_req.sector = sector;
    blk_req.type = is_write ? VIRTIO_BLK_T_OUT : VIRTIO_BLK_T_IN;
    if (is_write)
    {
        memcpy(blk_req.data.ptr, buf, SECTOR_SIZE);
    }

    // virtqueueのディスクリプタを構築する (3つのディスクリプタを使う)
    virtio_virtq* vq = blk_request_vq;
    vq.descs[0].addr = blk_req_paddr;
    vq.descs[0].len = uint.sizeof * 2 + ulong.sizeof;
    vq.descs[0].flags = VIRTQ_DESC_F_NEXT;
    vq.descs[0].next = 1;

    vq.descs[1].addr = blk_req_paddr + virtio_blk_req.data.offsetof;
    vq.descs[1].len = SECTOR_SIZE;
    vq.descs[1].flags = VIRTQ_DESC_F_NEXT | (is_write ? 0 : VIRTQ_DESC_F_WRITE);
    vq.descs[1].next = 2;

    vq.descs[2].addr = blk_req_paddr + virtio_blk_req.status.offsetof;
    vq.descs[2].len = ubyte.sizeof;
    vq.descs[2].flags = VIRTQ_DESC_F_WRITE;

    // デバイスに新しいリクエストがあることを通知する
    virtq_kick(vq, 0);

    // デバイス側の処理が終わるまで待つ
    while (virtq_is_busy(vq)) {}

    // virtio-blk: 0でない値が返ってきたらエラー
    if (blk_req.status != 0)
    {
        printf("virtio: warn: failed to read/write sector=%d status=%d\n",
               sector, blk_req.status);
        return;
    }

    // 読み込み処理の場合は、バッファにデータをコピーする
    if (!is_write)
    {
        memcpy(buf, blk_req.data.ptr, SECTOR_SIZE);
    }
}

enum FILES_MAX     = 2;
enum DISK_MAX_SIZE = alignUp!(SECTOR_SIZE)(file.sizeof * FILES_MAX);

struct tar_header
{
align(1):
    char[100] name;
    char[8] mode;
    char[8] uid;
    char[8] gid;
    char[12] size;
    char[12] mtime;
    char[8] checksum;
    char type;
    char[100] linkname;
    char[6] magic;
    char[2] _version;
    char[32] uname;
    char[32] gname;
    char[8] devmajor;
    char[8] devminor;
    char[155] prefix;
    char[12] padding;
    char[0] data;      // ヘッダに続くデータ領域を指す配列 (フレキシブル配列メンバ)
}

struct file
{
    bool in_use;      // このファイルエントリが使われているか
    char[100] name;   // ファイル名
    char[1024] data;  // ファイルの内容
    size_t size;      // ファイルサイズ
}

__gshared file[FILES_MAX] files;
__gshared ubyte[DISK_MAX_SIZE] disk;

int oct2int(char* oct, int len)
{
    int dec = 0;
    for (int i = 0; i < len; i++) {
        if (oct[i] < '0' || oct[i] > '7')
        {
            break;
        }
        dec = dec * 8 + (oct[i] - '0');
    }
    return dec;
}

void fs_init()
{
    for (uint sector = 0; sector < disk.sizeof / SECTOR_SIZE; sector++)
        read_write_disk(&disk[sector * SECTOR_SIZE], sector, false);

    uint off = 0;
    for (int i = 0; i < FILES_MAX; i++)
    {
        tar_header* header = cast(tar_header*) &disk[off];
        if (header.name[0] == '\0')
        {
            break;
        }

        if (strcmp(header.magic.ptr, "ustar") != 0)
        {
            panic!("invalid tar header:");
        }

        int filesz = oct2int(header.size.ptr, header.size.sizeof);
        file* file = &files[i];
        file.in_use = true;
        strcpy(file.name.ptr, header.name.ptr);
        memcpy(file.data.ptr, header.data.ptr, filesz);
        file.size = filesz;
        printf("file: %s, size=%d\n", file.name.ptr, file.size);

        off += alignUp!(SECTOR_SIZE)(tar_header.sizeof + filesz);
    }
}

void fs_flush()
{
    // files変数の各ファイルの内容をdisk変数に書き込む
    memset(disk.ptr, 0, disk.sizeof);
    uint off = 0;
    for (int file_i = 0; file_i < FILES_MAX; file_i++)
    {
        file* file = &files[file_i];
        if (!file.in_use)
        {
            continue;
        }

        tar_header* header = cast(tar_header*) &disk[off];
        memset(header, 0, (*header).sizeof);
        strcpy(header.name.ptr, file.name.ptr);
        strcpy(header.mode.ptr, "000644");
        strcpy(header.magic.ptr, "ustar");
        strcpy(header._version.ptr, "00");
        header.type = '0';

        // ファイルサイズを8進数文字列に変換
        {
            int filesz = file.size;
            int i = 0;
            do
            {
                header.size[i++] = (filesz % 8) + '0';
                filesz /= 8;
            } while (filesz > 0);
        }

        // チェックサムを計算
        int checksum = ' ' * header.checksum.sizeof;
        for (uint i = 0; i < tar_header.sizeof; i++)
        {
            checksum += cast(ubyte) disk[off + i];
        }

        for (int i = 5; i >= 0; i--)
        {
            header.checksum[i] = (checksum % 8) + '0';
            checksum /= 8;
        }

        // ファイルデータをコピー
        memcpy(header.data.ptr, file.data.ptr, file.size);
        off += alignUp!(SECTOR_SIZE)(tar_header.sizeof + file.size);
    }

    // disk変数の内容をディスクに書き込む
    for (uint sector = 0; sector < disk.sizeof / SECTOR_SIZE; sector++)
    {
        read_write_disk(&disk[sector * SECTOR_SIZE], sector, true);
    }

    printf("wrote %d bytes to disk\n", disk.sizeof);
}

void kernel_main()
{
    memset(&__bss, 0, &__bss_end - &__bss);
    WRITE_CSR!"stvec"(&kernel_entry);
    virtio_blk_init();
    fs_init();

    char[SECTOR_SIZE] buf;
    read_write_disk(buf.ptr, 0, false);
    printf("first sector: %s\n", buf.ptr);

    strcpy(buf.ptr, "hello from kernel!!!\n");
    read_write_disk(buf.ptr, 0, true);

    idle_proc = create_process(null, 0);
    idle_proc.pid = -1;
    current_proc = idle_proc;

    create_process(&_binary_shell_bin_start, cast(size_t) &_binary_shell_bin_size);

    yield();
    panic!("switched to idle process\n");

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
