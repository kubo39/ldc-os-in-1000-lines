#!/bin/bash
set -xue

QEMU=qemu-system-riscv32

LDC=ldc2

DFLAGS="--mtriple=riscv32-none-unknown --mattr=+m --betterC --boundscheck=off --checkaction=halt --defaultlib= -relocation-model=static -g -gcc=clang"

OBJCOPY=/usr/bin/llvm-objcopy

# シェルをビルド
$LDC $DFLAGS -Xcc=--target=riscv32 -Xcc=-march=rv32im -Xcc=-ffreestanding -Xcc=-nostdlib -Xcc=-Wl,-Tuser.ld -Xcc=-Wl,-Map=shell.Map -of=shell.elf \
    shell.d user.d common.d
$OBJCOPY --set-section-flags .bss=alloc,contents -O binary shell.elf shell.bin
$OBJCOPY -Ibinary -Oelf32-littleriscv shell.bin shell.bin.o

# カーネルをビルド
$LDC $DFLAGS -Xcc=--target=riscv32 -Xcc=-march=rv32im -Xcc=-ffreestanding -Xcc=-nostdlib -Xcc=-Wl,-Tkernel.ld -Xcc=-Wl,-Map=kernel.Map -of=kernel.elf \
    common.d kernel.d shell.bin.o

# QEMUを起動
$QEMU -machine virt \
    -bios default \
    -nographic \
    -serial mon:stdio --no-reboot \
    -d unimp,guest_errors,int,cpu_reset -D qemu.log \
    -kernel kernel.elf
