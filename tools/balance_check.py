#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""精确括号检查：真实词法扫描（注释 / 字符串 / 字符 / 续行），定位第一个不匹配位置。"""
import os, sys

ROOT = r"C:\Users\Administrator\.dsh\profiles\desktop\pet_audit\merged\PetDFY\src"
TARGETS = [
    "Sources/PDAIMissingSymbols.m",
    "Sources/PDChatService.m",
    "Sources/PDDeviceToolDeclarationsJSON.m",
    "Sources/PDNative_ClipboardManager.m",
    "Sources/PDNative_TextInputManager.m",
]

PAIRS = {"{": "}", "(": ")", "[": "]"}


def scan(path):
    """返回 (stack, line, col) 中第一个不匹配；全部配平返回 None。"""
    src = open(path, encoding="utf-8", errors="replace").read()
    i, n = 0, len(src)
    line = 1
    stack = []  # (char, line, col)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        # 行注释
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        # 块注释
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 2
            continue
        # 字符串 / 字符字面量
        if c in ('"', "'"):
            q = c
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == q:
                    i += 1
                    break
                if src[i] == "\n":
                    line += 1
                i += 1
            continue
        if c in PAIRS:
            stack.append((c, line))
            i += 1
            continue
        if c in ")]}":
            if not stack:
                return ("EXTRA_CLOSE", c, line)
            op, ln = stack.pop()
            if PAIRS[op] != c:
                return ("MISMATCH", f"{op}@{ln} vs {c}@{line}", line)
            i += 1
            continue
        i += 1
    if stack:
        op, ln = stack[-1]
        return ("UNCLOSED", f"{op}@{ln}", ln)
    return None


print(f"{'file':52s} 结果")
bad = 0
for rel in TARGETS:
    p = os.path.join(ROOT, rel.replace("/", os.sep))
    if not os.path.exists(p):
        print(f"{rel:52s} MISSING")
        bad += 1
        continue
    r = scan(p)
    if r is None:
        print(f"{rel:52s} BALANCED")
    else:
        print(f"{rel:52s} {r}")
        bad += 1

print(f"\n结论: {bad} 个文件有真实问题" if bad else "\n结论: 全部配平（此前为检查器误报）")
sys.exit(0 if bad == 0 else 1)
