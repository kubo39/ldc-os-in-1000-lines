#!/bin/bash
set -xue

QEMU=qemu-system-riscv32

LDC=ldc2

DFLAGS="--mtriple=riscv32-none-unknown -O2 --betterC --defaultlib= -relocation-model=static -gcc=clang"

# カーネルをビルド
$LDC $DFLAGS -Xcc=--target=riscv32 -Xcc=-ffreestanding -Xcc=-nostdlib -Xcc=-Wl,-Tkernel.ld -Xcc=-Wl,-Map=kernel.Map -of=kernel.elf \
    kernel.d

# QEMUを起動
$QEMU -machine virt \
    -bios default \
    -nographic \
    -serial mon:stdio --no-reboot \
    -kernel kernel.elf
