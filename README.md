# Wrinting OS in 1000 lines, in D

[Writing an OS in 1,000 Lines](https://operating-system-in-1000-lines.vercel.app/ja/welcome)をD言語で書くやつ

## 環境構築

- LDC

```console
curl -fsS https://dlang.org/install.sh | bash -s ldc
```

### Ubuntu 22.04

以下をパッケージとcurlで入れる。

```console
sudo apt install qemu-system-misc clang lld
curl -LO https://github.com/qemu/qemu/raw/v8.0.4/pc-bios/opensbi-riscv32-generic-fw_dynamic.bin
```

Ubuntu 22.04がaptで提供しているopensbiは64ビットRISC-Vなので今回は利用できない。

動作確認。qemuが立ち上がるはずなので `q` で終了。

```console
qemu-system-riscv32
```

実行は `./run.sh` を叩く。

```console
./run.sh
```

## 他の他のプログラミング言語での再実装プロジェクト

### Rust

- Totsugekitai/kanios
  - レポジトリ: https://github.com/Totsugekitai/kanios
  - ブログ記事: [「Writing an OS in 1000 Lines」をRISC-V 64bit向けにRustで書いた](https://hanazonochateau.net/posts/2023/09/05/operating-system-in-1000-lines-rs/)

### Zig

- bokuweb/zig-os-in-1000-lines
  - レポジトリ: https://github.com/bokuweb/zig-os-in-1000-lines
  - ブログ記事: [ZigでWriting an OS in 1,000 Linesをやる](https://bokuweb.github.io/undefined/articles/20231121.html)
