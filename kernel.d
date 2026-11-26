extern (C):

import core.volatile;

import ldc.attributes;
import ldc.intrinsics;
import ldc.llvmasm;

import common;

alias alignUp = imported!"core.stdc.stdarg".alignUp;

extern __gshared ubyte[0] __bss;
extern __gshared ubyte[0] __bss_end;

struct SbiRet
{
    int error;
    int value;
}

SbiRet sbiCall(int arg0, int arg1, int arg2, int arg3, int arg4,
                int arg5, int fid, int eid)
{
    // LLVMはmemory clobberを単に無視し、またLDCは常にインラインアセンブラで
    // ReadWriteMemoryな関数属性が付与され、これはmemory clobberが付与される
    // のと同じ効果があるため `~{memory}` は不要だが、わかりやすさのために
    // 残しておく。
    return __asm!SbiRet(
        "ecall",
        "={a0},={a1},{a0},{a1},{a2},{a3},{a4},{a5},{a6},{a7},~{memory}",
        arg0, arg1, arg2, arg3, arg4, arg5, fid, eid
    );
}

void putchar(char ch)
{
    sbiCall(ch, 0, 0, 0, 0, 0, 0, 1 /* Console Putchar */);
}

int getchar()
{
    pragma(inline, false);
    SbiRet ret = sbiCall(0, 0, 0, 0, 0, 0, 0, 2);
    return ret.error;
}

noreturn panic(string fmt, string file = __FILE__, int line = __LINE__)()
{
    printf!("PANIC: %s:%d: " ~ fmt ~ "\n")(file, line);
    for (;;)
    {
        __asm("wfi", "");
    }
}

noreturn __assert(const(char)* msg, const(char)* file, int line)
{
    printf!"PANIC: %s:%d: assertion failed: %s\n"(file, line, msg);
    for (;;)
    {
        __asm("wfi", "");
    }
}

File* fsLookup(const char* filename)
{
    for (int i = 0; i < FILES_MAX; i++)
    {
        File* file = &files[i];
        if (!strcmp(file.name.ptr, filename))
        {
            return file;
        }
    }

    return null;
}

struct TrapFrame
{
    uint ra, gp, tp;
    uint t0, t1, t2, t3, t4, t5, t6;
    uint a0, a1, a2, a3, a4, a5, a6, a7;
    uint s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11;
    uint sp;
}

static assert(TrapFrame.sizeof == 31 * 4);

enum trapFrameStackSize = alignUp!16(TrapFrame.sizeof);
static assert(trapFrameStackSize == 128);

template regOps(string op, T, size_t i = 0)
{
    static if (i == T.tupleof.length)
        enum regOps = "";
    else static if (__traits(identifier, T.tupleof[i]) == "sp")
        enum regOps = regOps!(op, T, i + 1);
    else
        enum regOps = op ~ " " ~ __traits(identifier, T.tupleof[i]) ~ ", "
            ~ toDecString!(T.tupleof[i].offsetof) ~ "(sp)\n" ~ regOps!(op, T, i + 1);
}

T readCsr(string reg, T)()
{
    return __asm!T("csrr $0, " ~ reg, "=r");
}

void writeCsr(string reg)(void* value)
{
    __asm("csrw " ~ reg ~ ", $0", "r", value);
}

enum SCAUSE_ECALL = 8;

void handleTrap(ref TrapFrame f)
{
    uint scause = readCsr!("scause", uint)();
    uint stval = readCsr!("stval", uint)();
    uint userPc = readCsr!("sepc", uint)();

    if (scause == SCAUSE_ECALL)
    {
        handleSyscall(f);
        userPc += 4;
    }
    else
    {
        printf!"scause: %x\n"(scause);
        printf!"stval: %x\n"(stval);
        printf!"user_pc: %x\n"(userPc);

        panic!("unexpected trap");
    }

    writeCsr!("sepc")(cast(void*)userPc);
}

static assert(SysNo.max - SysNo.min + 1 == __traits(allMembers, SysNo).length);

void handleSyscall(ref TrapFrame f)
{
    if (f.a3 < SysNo.min || f.a3 > SysNo.max)
    {
        panic!("unexpected syscall");
    }

    const sysno = cast(SysNo) f.a3;
    final switch (sysno)
    {
    case SysNo.putchar:
        putchar(cast(char) f.a0);
        break;
    case SysNo.getchar:
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
    case SysNo.exit:
        printf!"process %d exited\n"(currentProc.pid);
        currentProc.state = PROC_EXITED;
        yield();
        panic!("unreachable");
        break;
    case SysNo.readFile, SysNo.writeFile:
        const char* filename = cast(const char*) f.a0;
        char* buf = cast(char*) f.a1;
        int len = f.a2;
        File* file = fsLookup(filename);
        if (file is null)
        {
            printf!"file not found: %s\n"(filename);
            f.a0 = -1;
            break;
        }

        if (len < 0)
        {
            f.a0 = -1;
            break;
        }

        if (sysno == SysNo.writeFile)
        {
            if (len > cast(int) file.data.sizeof)
            {
                len = cast(int) file.data.sizeof;
            }
            memcpy(file.data.ptr, buf, len);
            file.size = len;
            fsFlush();
        }
        else
        {
            if (len > cast(int) file.size)
            {
                len = cast(int) file.size;
            }
            memcpy(buf, file.data.ptr, len);
        }

        f.a0 = len;
        break;
    }
}

enum string kernelEntryAsm = `
    # 実行中プロセスのカーネルスタックをsscratchから取り出す
    # tmp = sp; sp = sscratch; sscratch = tmp;
    csrrw sp, sscratch, sp
    addi sp, sp, -` ~ toDecString!trapFrameStackSize ~ "\n"
    ~ regOps!("sw", TrapFrame) ~ `
    # 例外発生時のspを取り出して保存
    csrr a0, sscratch
    sw a0, ` ~ toDecString!(TrapFrame.sp.offsetof) ~ `(sp)

    # カーネルスタックを設定し直す
    addi a0, sp, ` ~ toDecString!trapFrameStackSize ~ `
    csrw sscratch, a0

    mv a0, sp
    call handleTrap
` ~ regOps!("lw", TrapFrame) ~ `
    lw sp, ` ~ toDecString!(TrapFrame.sp.offsetof) ~ `(sp)
    sret
`;

@section(".text.trap")
@naked void kernelEntry()
{
    __asm(kernelEntryAsm, "");
}

extern __gshared ubyte[0] __free_ram;
extern __gshared ubyte[0] __free_ram_end;

alias PAddr = uint;
alias VAddr = uint;

enum uint PAGE_SIZE = 4096;

__gshared PAddr nextPaddr = 0;

PAddr allocPages(uint n)
{
    if (nextPaddr == 0)
    {
        nextPaddr = cast(PAddr) __free_ram.ptr;
    }
    PAddr paddr = nextPaddr;
    nextPaddr += n * PAGE_SIZE;

    if (nextPaddr > cast(PAddr) __free_ram_end.ptr)
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

struct Process
{
    int pid;
    int state;
    VAddr sp; // コンテキストスイッチ時のスタックポインタ
    uint* pageTable;
    align(16) ubyte[8192] stack; // カーネルスタック

    ubyte* stackTop()
    {
        return stack.ptr + stack.length;
    }
}

static assert(Process.alignof == 16 && Process.stack.offsetof % 16 == 0);

__gshared Process[PROC_MAX] procs;

struct SwitchFrame
{
    uint ra;
    uint s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11;
}

static assert(SwitchFrame.sizeof == 13 * 4);

enum switchFrameStackSize = alignUp!16(SwitchFrame.sizeof);
static assert(switchFrameStackSize == 64);

enum string switchContextAsm = `
    addi sp, sp, -` ~ toDecString!switchFrameStackSize ~ "\n"
    ~ regOps!("sw", SwitchFrame) ~ `
    sw sp, (a0)
    lw sp, (a1)
` ~ regOps!("lw", SwitchFrame) ~ `
    addi sp, sp, ` ~ toDecString!switchFrameStackSize ~ `
    ret
`;

@naked void switchContext(uint* prevSp, uint* nextSp)
{
    pragma(inline, false);
    __asm(switchContextAsm, "");
}

extern __gshared ubyte[0] __kernel_base;

Process* createProcess(const(ubyte)[] image)
{
    Process* proc = null;
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

    // switchContext() で復帰できるように、
    // スタックに呼び出し先保存レジスタを積む
    auto frame = cast(SwitchFrame*) (proc.stackTop() - switchFrameStackSize);
    *frame = SwitchFrame.init;
    frame.ra = cast(uint) &userEntry;

    uint* pageTable = cast(uint*) allocPages(1);

    // カーネルのページをマッピングする
    for (PAddr paddr = cast(PAddr) __kernel_base.ptr;
         paddr < cast(PAddr) __free_ram_end.ptr; paddr += PAGE_SIZE)
    {
        mapPage(pageTable, paddr, paddr, PAGE_R | PAGE_W | PAGE_X);
    }
    mapPage(pageTable, VIRTIO_BLK_PADDR, VIRTIO_BLK_PADDR, PAGE_R | PAGE_W);

    // ユーザーのページをマッピングする
    for (uint off; off < image.length; off += PAGE_SIZE)
    {
        PAddr page = allocPages(1);
        size_t remaining = image.length - off;
        memcpy(cast(void*) page, image.ptr + off, remaining < PAGE_SIZE ? remaining : PAGE_SIZE);
        mapPage(pageTable, USER_BASE + off, page,
                 PAGE_U | PAGE_R | PAGE_W | PAGE_X);
    }

    // 各フィールドを初期化
    proc.pid = i + 1;
    proc.state = PROC_RUNNABLE;
    proc.sp = cast(uint) frame;
    proc.pageTable = pageTable;
    return proc;
}

__gshared Process* currentProc; // 現在実行中のプロセス
__gshared Process* idleProc;    // アイドルプロセス

void yield()
{
    // 実行可能なプロセスを探す
    Process* next = idleProc;
    foreach (i; 0 .. PROC_MAX)
    {
        Process* proc = &procs[(currentProc.pid + i + PROC_MAX) % PROC_MAX];
        if (proc.state == PROC_RUNNABLE && proc.pid > 0)
        {
            next = proc;
            break;
        }
    }

    // 現在実行中のプロセス以外に、実行可能なプロセスがない。
    // 戻って処理を続行する
    if (next == currentProc)
        return;

    // コンテキストスイッチ
    Process* prev = currentProc;
    currentProc = next;

    __asm(`
            sfence.vma
            csrw satp, $0
            sfence.vma
            csrw sscratch, $1
        `,
        "r,r",
        (SATP_SV32 | (cast(uint) next.pageTable / PAGE_SIZE)),
        next.stackTop()
    );

    switchContext(&prev.sp, &next.sp);
}

enum uint SATP_SV32 = 1 << 31;
enum uint PAGE_V = 1 << 0;   // 有効化ビット
enum uint PAGE_R = 1 << 1;   // 読み込み可能
enum uint PAGE_W = 1 << 2;   // 書き込み可能
enum uint PAGE_X = 1 << 3;   // 実行可能
enum uint PAGE_U = 1 << 4;   // ユーザーモードでアクセス可能

void mapPage(uint* table1, uint vaddr, PAddr paddr, uint flags)
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
        uint ptPaddr = allocPages(1);
        table1[vpn1] = ((ptPaddr / PAGE_SIZE) << 10) | PAGE_V;
    }

    // 2段目のページテーブルにエントリを追加する
    uint vpn0 = (vaddr >> 12) & 0x3ff;
    uint* table0 = cast(uint*) ((table1[vpn1] >> 10) * PAGE_SIZE);
    table0[vpn0] = ((paddr / PAGE_SIZE) << 10) | flags | PAGE_V;
}

enum USER_BASE = 0x1000000;

enum SSTATUS_SPIE = 1 << 5;
enum SSTATUS_SUM = 1 << 18;

immutable ubyte[] shellImage = cast(immutable(ubyte)[]) import("shell.bin");

uint elfEntry()(string elf)
{
    assert(elf.length >= 28 && elf[0 .. 4] == "\x7fELF", "check failed: cannot find elf magic.");
    return elf[24] | (elf[25] << 8) | (elf[26] << 16) | (elf[27] << 24);
}
static assert(elfEntry(import("shell.elf")) == USER_BASE, "unmatched entry address.");

@naked void userEntry()
{
    __asm(`
        li t0, $0
        csrw sepc, t0
        li t0, $1
        csrw sstatus, t0
        sret
    `, "n,n", USER_BASE, SSTATUS_SPIE | SSTATUS_SUM);
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

struct VirtqDesc
{
align(1):
    ulong addr;
    uint len;
    ushort flags;
    ushort next;
}

struct VirtqAvail
{
align(1):
    ushort flags;
    ushort index;
    ushort[VIRTQ_ENTRY_NUM] ring;
}

struct VirtqUsedElem
{
align(1):
    uint id;
    uint len;
}

struct VirtqUsed
{
align(1):
    ushort flags;
    ushort index;
    VirtqUsedElem[VIRTQ_ENTRY_NUM] ring;
}

struct VirtioVirtq
{
align(1):
    VirtqDesc[VIRTQ_ENTRY_NUM] descs;
    VirtqAvail avail;
    align(PAGE_SIZE) VirtqUsed used;
    int queueIndex;
    ushort* usedIndex;
    ushort lastUsedIndex;
}

struct VirtioBlkReq
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

uint virtioRegRead32(uint offset)
{
    return volatileLoad(cast(uint*) (VIRTIO_BLK_PADDR + offset));
}

ulong virtioRegRead64(uint offset)
{
    return volatileLoad(cast(ulong*) (VIRTIO_BLK_PADDR + offset));
}

void virtioRegWrite32(uint offset, uint value)
{
    volatileStore(cast(uint*) (VIRTIO_BLK_PADDR + offset), value);
}

void virtioRegFetchAndOr32(uint offset, uint value)
{
    virtioRegWrite32(offset, virtioRegRead32(offset) | value);
}

__gshared VirtioVirtq* blkRequestVq;
__gshared VirtioBlkReq* blkReq;
__gshared PAddr blkReqPaddr;
__gshared uint blkCapacity;

void virtioBlkInit()
{
    if (virtioRegRead32(VIRTIO_REG_MAGIC) != 0x74726976)
    {
        panic!("virtio: invalid magic value");
    }
    if (virtioRegRead32(VIRTIO_REG_VERSION) != 1)
    {
        panic!("virtio: invalid version");
    }
    if (virtioRegRead32(VIRTIO_REG_DEVICE_ID) != VIRTIO_DEVICE_BLK)
    {
        panic!("virtio: invalid device id");
    }

    // 1. Reset the device.
    virtioRegWrite32(VIRTIO_REG_DEVICE_STATUS, 0);
    // 2. Set the ACKNOWLEDGE status bit: the guest OS has noticed the device.
    virtioRegFetchAndOr32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_ACK);
    // 3. Set the DRIVER status bit.
    virtioRegFetchAndOr32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_DRIVER);
    // 5. Set the FEATURES_OK status bit.
    virtioRegFetchAndOr32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_FEAT_OK);
    // 7. Perform device-specific setup, including discovery of virtqueues for the device
    blkRequestVq = virtqInit(0);
    // 8. Set the DRIVER_OK status bit.
    virtioRegWrite32(VIRTIO_REG_DEVICE_STATUS, VIRTIO_STATUS_DRIVER_OK);

    // ディスクの容量を取得
    blkCapacity = cast(uint) (virtioRegRead64(VIRTIO_REG_DEVICE_CONFIG + 0) * SECTOR_SIZE);
    printf!"virtio-blk: capacity is %d bytes\n"(blkCapacity);

    // デバイスへの処理要求を格納する領域を確保
    blkReqPaddr = allocPages(alignUp!(PAGE_SIZE)((*blkReq).sizeof) / PAGE_SIZE);
    blkReq = cast(VirtioBlkReq*) blkReqPaddr;
}

VirtioVirtq* virtqInit(uint index)
{
    PAddr virtqPaddr = allocPages(alignUp!(PAGE_SIZE)(VirtioVirtq.sizeof) / PAGE_SIZE);
    VirtioVirtq* vq = cast(VirtioVirtq*) virtqPaddr;
    vq.queueIndex = index;
    vq.usedIndex = cast(ushort*) &vq.used.index;
    // 1. Select the queue writing its index (first queue is 0) to QueueSel.
    virtioRegWrite32(VIRTIO_REG_QUEUE_SEL, index);
    // 5. Notify the device about the queue size by writing the size to QueueNum.
    virtioRegWrite32(VIRTIO_REG_QUEUE_NUM, VIRTQ_ENTRY_NUM);
    // 6. Notify the device about the used alignment by writing its value in bytes to QueueAlign.
    virtioRegWrite32(VIRTIO_REG_QUEUE_ALIGN, 0);
    // 7. Write the physical number of the first page of the queue to the QueuePFN register.
    virtioRegWrite32(VIRTIO_REG_QUEUE_PFN, virtqPaddr);
    return vq;
}

// デバイスに新しいリクエストがあることを通知する。descIndexは、新しいリクエストの
// 先頭ディスクリプタのインデックス。
void virtqKick(VirtioVirtq* vq, int descIndex)
{
    pragma(inline, false);
    vq.avail.ring[vq.avail.index % VIRTQ_ENTRY_NUM] = cast(ushort) descIndex;
    vq.avail.index++;
    // オリジナルに合わせるためにCrossThreadを指定
    llvm_memory_fence(DefaultOrdering, SynchronizationScope.CrossThread);
    virtioRegWrite32(VIRTIO_REG_QUEUE_NOTIFY, vq.queueIndex);
    vq.lastUsedIndex++;
}

// デバイスが処理中のリクエストがあるかどうかを返す。
bool virtqIsBusy(VirtioVirtq* vq)
{
    return vq.lastUsedIndex != volatileLoad(vq.usedIndex);
}

// virtio-blkデバイスの読み書き。
void readWriteDisk(void* buf, uint sector, int isWrite)
{
    if (sector >= blkCapacity / SECTOR_SIZE)
    {
        printf!"virtio: tried to read/write sector=%d, but capacity is %d\n"(
              sector, blkCapacity / SECTOR_SIZE);
        return;
    }

    // virtio-blkの仕様に従って、リクエストを構築する
    blkReq.sector = sector;
    blkReq.type = isWrite ? VIRTIO_BLK_T_OUT : VIRTIO_BLK_T_IN;
    if (isWrite)
    {
        memcpy(blkReq.data.ptr, buf, SECTOR_SIZE);
    }

    // virtqueueのディスクリプタを構築する (3つのディスクリプタを使う)
    VirtioVirtq* vq = blkRequestVq;
    vq.descs[0].addr = blkReqPaddr;
    vq.descs[0].len = uint.sizeof * 2 + ulong.sizeof;
    vq.descs[0].flags = VIRTQ_DESC_F_NEXT;
    vq.descs[0].next = 1;

    vq.descs[1].addr = blkReqPaddr + VirtioBlkReq.data.offsetof;
    vq.descs[1].len = SECTOR_SIZE;
    vq.descs[1].flags = VIRTQ_DESC_F_NEXT | (isWrite ? 0 : VIRTQ_DESC_F_WRITE);
    vq.descs[1].next = 2;

    vq.descs[2].addr = blkReqPaddr + VirtioBlkReq.status.offsetof;
    vq.descs[2].len = ubyte.sizeof;
    vq.descs[2].flags = VIRTQ_DESC_F_WRITE;

    // デバイスに新しいリクエストがあることを通知する
    virtqKick(vq, 0);

    // デバイス側の処理が終わるまで待つ
    while (virtqIsBusy(vq)) {}

    // virtio-blk: 0でない値が返ってきたらエラー
    if (blkReq.status != 0)
    {
        printf!"virtio: warn: failed to read/write sector=%d status=%d\n"(
               sector, blkReq.status);
        return;
    }

    // 読み込み処理の場合は、バッファにデータをコピーする
    if (!isWrite)
    {
        memcpy(buf, blkReq.data.ptr, SECTOR_SIZE);
    }
}

enum FILES_MAX     = 2;
enum DISK_MAX_SIZE = FILES_MAX * (TarHeader.sizeof + alignUp!(SECTOR_SIZE)(File.data.sizeof));

struct TarHeader
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

struct File
{
    bool inUse;      // このファイルエントリが使われているか
    char[100] name;   // ファイル名
    char[1024] data;  // ファイルの内容
    size_t size;      // ファイルサイズ
}

__gshared File[FILES_MAX] files;
static assert(TarHeader.sizeof == SECTOR_SIZE);

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

void fsInit()
{
    for (uint sector = 0; sector < disk.sizeof / SECTOR_SIZE; sector++)
        readWriteDisk(&disk[sector * SECTOR_SIZE], sector, false);

    uint off = 0;
    for (int i = 0; i < FILES_MAX; i++)
    {
        if (off + TarHeader.sizeof > disk.sizeof)
        {
            break;
        }

        TarHeader* header = cast(TarHeader*) &disk[off];
        if (header.name[0] == '\0')
        {
            break;
        }

        if (header.magic != "ustar\0")
        {
            panic!("invalid tar header:");
        }

        int filesz = oct2int(header.size.ptr, header.size.sizeof);
        if (filesz > files[i].data.sizeof || off + TarHeader.sizeof + filesz > disk.sizeof)
        {
            panic!("file too large");
        }

        File* file = &files[i];
        file.inUse = true;
        strcpy(file.name.ptr, header.name.ptr);
        memcpy(file.data.ptr, header.data.ptr, filesz);
        file.size = filesz;
        printf!"file: %s, size=%d\n"(file.name.ptr, file.size);

        off += alignUp!(SECTOR_SIZE)(TarHeader.sizeof + filesz);
    }
}

void fsFlush()
{
    // files変数の各ファイルの内容をdisk変数に書き込む
    memset(disk.ptr, 0, disk.sizeof);
    uint off = 0;
    for (int fileIndex = 0; fileIndex < FILES_MAX; fileIndex++)
    {
        File* file = &files[fileIndex];
        if (!file.inUse)
        {
            continue;
        }

        TarHeader* header = cast(TarHeader*) &disk[off];
        memset(header, 0, (*header).sizeof);
        strcpy(header.name.ptr, file.name.ptr);
        strcpy(header.mode.ptr, "000644");
        strcpy(header.magic.ptr, "ustar");
        strcpy(header._version.ptr, "00");
        header.type = '0';

        // ファイルサイズを8進数文字列に変換
        {
            int filesz = file.size;
            for (int i = cast(int) header.size.sizeof - 2; i >= 0; i--)
            {
                header.size[i] = (filesz % 8) + '0';
                filesz /= 8;
            }
        }

        // チェックサムを計算
        int checksum = ' ' * header.checksum.sizeof;
        for (uint i = 0; i < TarHeader.sizeof; i++)
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
        off += alignUp!(SECTOR_SIZE)(TarHeader.sizeof + file.size);
    }

    // disk変数の内容をディスクに書き込む
    for (uint sector = 0; sector < disk.sizeof / SECTOR_SIZE; sector++)
    {
        readWriteDisk(&disk[sector * SECTOR_SIZE], sector, true);
    }

    printf!"wrote %d bytes to disk\n"(disk.sizeof);
}

void kernelMain()
{
    memset(__bss.ptr, 0, __bss_end.ptr - __bss.ptr);
    writeCsr!"stvec"(&kernelEntry);
    virtioBlkInit();
    fsInit();

    idleProc = createProcess(null);
    idleProc.pid = -1;
    currentProc = idleProc;

    createProcess(shellImage);

    yield();
    panic!("switched to idle process\n");

    printf!"unreachable here!\n"();

    for (;;)
    {
        __asm("wfi", "");
    }
}

@section(".text.boot")
@naked void boot()
{
    __asm(`
        la sp, __stack_top
        li fp, 0
        li ra, 0
        j kernelMain
    `, "");
}
