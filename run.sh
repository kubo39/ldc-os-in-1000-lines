#!/bin/bash
set -xue

QEMU=qemu-system-riscv32

LDC=ldc2

DFLAGS="--mtriple=riscv32-none-unknown --mattr=+m --mabi=ilp32 -O2 --disable-simplify-libcalls --betterC --boundscheck=off --checkaction=halt --defaultlib= -relocation-model=static -g -gcc=clang"

OBJCOPY=/usr/bin/llvm-objcopy

# シェルをビルド
$LDC $DFLAGS -Xcc=--target=riscv32 -Xcc=-march=rv32im -Xcc=-mabi=ilp32 -Xcc=-ffreestanding -Xcc=-nostdlib -Xcc=-Wl,-Tuser.ld -Xcc=-Wl,-Map=shell.Map -of=shell.elf \
    shell.d user.d common.d
$OBJCOPY --set-section-flags .bss=alloc,contents -O binary shell.elf shell.bin
$OBJCOPY -Ibinary -Oelf32-littleriscv shell.bin shell.bin.o

# カーネルをビルド
$LDC $DFLAGS -Xcc=--target=riscv32 -Xcc=-march=rv32im -Xcc=-ffreestanding -Xcc=-nostdlib -Xcc=-Wl,-Tkernel.ld -Xcc=-Wl,-Map=kernel.Map -of=kernel.elf \
    common.d kernel.d shell.bin.o

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
