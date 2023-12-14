# D OS in 1000 lines

- https://operating-system-in-1000-lines.vercel.app/ja/welcome

## 環境構築

- LDC

```
curl -fsS https://dlang.org/install.sh | bash -s ldc
```

### Ubuntu 22.04

以下をパッケージとcurlで入れる。

```console
sudo apt install qemu-system-misc clang lld
curl -LO https://github.com/qemu/qemu/raw/v8.0.4/pc-bios/opensbi-riscv32-generic-fw_dynamic.elf
```

Ubuntu 22.04がaptで提供しているopensbiは64ビットRISC-Vなので今回は利用できない。

動作確認。qemuが立ち上がるはずなので `q` で終了。

```console
qemu-system-riscv32
```
