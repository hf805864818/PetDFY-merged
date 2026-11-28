#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 thin Mach-O 的 cpusubtype 从 arm64(0) 改成 arm64e(0x80000002)。

背景：Linux 上的 clang/ld64.lld 用 -target arm64e-apple-ios 编出的 Mach-O，
cpusubtype 仍是 0（arm64），于是 iOS 的 dlopen_preflight 会报
"incompatible architecture (have 'arm64', need 'arm64e')"。

只改 header（offset 8 的 cpusubtype 字段），代码段不动：
arm64 指令在 arm64e 进程里是合法子集，dyld 接受该 subtype；
代价是没有 PAC（指针认证）指令，安全性略低于真 arm64e，但功能正常。
"""
import struct, sys, os

def patch(path):
    with open(path, "rb") as f:
        d = bytearray(f.read())
    if len(d) < 32:
        return f"{os.path.basename(path)}: too small"
    be = struct.unpack_from(">I", d, 0)[0]
    if be == 0xCAFEBABE:
        # fat：逐个 slice 处理
        n = struct.unpack_from(">I", d, 4)[0]
        changed = 0
        for i in range(n):
            off = 8 + i * 20
            ct, cs = struct.unpack_from(">II", d, off)
            if cs == 0 and ct == 0x0100000C:
                struct.pack_into(">I", d, off + 4, 0x80000002)
                changed += 1
        if changed:
            open(path, "wb").write(d)
        return f"{os.path.basename(path)}: fat, patched {changed} slice(s)"
    le = struct.unpack_from("<I", d, 0)[0]
    if le != 0xFEEDFACF:
        return f"{os.path.basename(path)}: not 64-bit mach-o (magic {hex(le)})"
    ct, cs = struct.unpack_from("<II", d, 4)
    if cs == 0x80000002:
        return f"{os.path.basename(path)}: already arm64e"
    if cs != 0:
        return f"{os.path.basename(path)}: subtype {hex(cs)} untouched"
    struct.pack_into("<I", d, 8, 0x80000002)
    with open(path, "wb") as f:
        f.write(d)
    return f"{os.path.basename(path)}: arm64 -> arm64e (header patched)"

if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(patch(p))