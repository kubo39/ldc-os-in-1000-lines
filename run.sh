#!/bin/bash
set -xue

QEMU=qemu-system-riscv32

LDC=ldc2
LD=ld.lld
OBJCOPY=llvm-objcopy

DFLAGS="--mtriple=riscv32-unknown-none-elf --mattr=+m,+c,+relax --mabi=ilp32 -O2 -g --force-dwarf-frame-section -fno-builtin --disable-simplify-libcalls --betterC -transition=tls --checkaction=C --defaultlib= -relocation-model=static --frame-pointer=all"

# シェルをビルド
$LDC $DFLAGS -c -od=build/shell shell.d user.d common.d
$LD -T user.ld -Map=shell.Map --gc-sections -o shell.elf \
    build/shell/shell.o build/shell/user.o build/shell/common.o
$OBJCOPY -O binary --set-section-flags .bss=alloc,contents shell.elf shell.bin

# カーネルをビルド
$LDC $DFLAGS -J. -c -od=build/kernel kernel.d common.d
$LD -T kernel.ld -Map=kernel.Map --gc-sections -o kernel.elf \
    build/kernel/kernel.o build/kernel/common.o

(cd disk && tar cf ../disk.tar --format=ustar *.txt)

# QEMUを起動
$QEMU -machine virt \
    -bios default \
    -nographic \
    -serial mon:stdio --no-reboot \
    -d unimp,guest_errors,int,cpu_reset -D qemu.log \
    -drive id=drive0,file=disk.tar,format=raw \
    -device virtio-blk-device,drive=drive0,bus=virtio-mmio-bus.0 \
    -kernel kernel.elf
