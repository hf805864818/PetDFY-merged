#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""合并工程静态自检：import 闭环 / 括号配平（真实词法）/ 类重复 / 依赖缺失。"""
import os, re, sys, collections

ROOT = r"C:\Users\Administrator\.dsh\profiles\desktop\pet_audit\merged\PetDFY"
SRC = os.path.join(ROOT, "src")

files = []
for dp, _, fs in os.walk(SRC):
    for f in fs:
        if f.endswith((".m", ".h", ".xm")):
            files.append(os.path.join(dp, f))
files.sort()

headers = {os.path.basename(p) for p in files if p.endswith(".h")}
incdirs = [SRC, os.path.join(SRC, "Core"), os.path.join(SRC, "Sources"),
           os.path.join(SRC, "Ext"), os.path.join(ROOT, "shim"),
           os.path.join(ROOT, "shim", "ApplicationServices")]
problems = collections.defaultdict(list)

# 1) import 闭环
for p in files:
    t = open(p, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r'^\s*#\s*(?:import|include)\s+"([^"]+)"', t, re.M):
        h = m.group(1)
        if h in headers:
            continue
        if not any(os.path.exists(os.path.join(d, h)) for d in incdirs):
            problems["missing_import"].append(f"{os.path.relpath(p, ROOT)}: {h}")

# 2) 括号配平（真实词法扫描）
PAIRS = {"{": "}", "(": ")", "[": "]"}


def balance(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    i, n, line = 0, len(src), 1
    stack = []
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 2
            continue
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
                return f"多余闭合 {c} 第 {line} 行"
            op, ln = stack.pop()
            if PAIRS[op] != c:
                return f"{op}@{ln} 与 {c}@{line} 不匹配"
            i += 1
            continue
        i += 1
    if stack:
        op, ln = stack[-1]
        return f"未闭合 {op} 第 {ln} 行"
    return None


for p in files:
    r = balance(p)
    if r:
        problems["unbalanced"].append(f"{os.path.relpath(p, ROOT)}: {r}")

# 3) 类重复
impl = collections.defaultdict(list)
for p in files:
    t = open(p, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r'^@implementation\s+(\w+)', t, re.M):
        impl[m.group(1)].append(os.path.relpath(p, ROOT))

# 4) 关键依赖
must = {
    "PDZipExtract.m": ["PDZipExtract.h", "zlib.h"],
    "PDAssetInstaller.m": ["PDJailbreak.h", "PDZipExtract.h", "PDDiag.h", "PDDiagnostics.h", "PDToast.h"],
    "PDFramePlayer.m": ["PDJailbreak.h", "ImageIO/ImageIO.h"],
    "PDDiagnostics.m": ["PDJailbreak.h", "PDAssetInstaller.h"],
    "PDDiag.h": ["PDJailbreak.h"],
}
for f, deps in must.items():
    path = os.path.join(SRC, "Core", f)
    if not os.path.exists(path):
        problems["missing_file"].append(f)
        continue
    t = open(path, encoding="utf-8", errors="replace").read()
    for d in deps:
        if f'"{d}"' not in t and f"<{d}>" not in t:
            problems["missing_dep"].append(f"{f} 缺 {d}")

# 5) 合并接入点
ot = open(os.path.join(SRC, "Core", "PDOverlayController.m"), encoding="utf-8", errors="replace").read()
for sym in ["PDResourceBundlePath", "PDInstallCombinedArchive", "PDAssetInstaller",
            "PDJailbreak.h", "discardAssetViews", "PDImportSpoolDirectories"]:
    if sym not in ot:
        problems["overlay_missing"].append(sym)

# 6) 构建清单
mk = open(os.path.join(ROOT, "Makefile"), encoding="utf-8", errors="replace").read()
for sym in ["-lz", "src/Core", "src/Ext", "PDFYEnhance", "PDFYSecurity"]:
    if sym not in mk:
        problems["makefile_missing"].append(sym)

print(f"源文件 {len(files)}（.m {sum(1 for p in files if p.endswith('.m'))} / "
      f".h {sum(1 for p in files if p.endswith('.h'))}）")
titles = {
    "missing_import": "import 闭环缺失",
    "unbalanced": "括号不配平",
    "missing_file": "缺失文件",
    "missing_dep": "依赖缺失",
    "overlay_missing": "PDOverlayController 接入点缺失",
    "makefile_missing": "Makefile 缺少项",
}
for k, title in titles.items():
    print(f"\n=== {title} ===")
    for x in (problems[k] or ["(无)"]):
        print("  ", x)

print("\n=== 多实现类（category，正常）===")
for k, v in sorted(impl.items()):
    if len(v) > 1:
        print(f"  {k}: {', '.join(v)}")

bad = sum(len(v) for v in problems.values())
print(f"\n=== 结论: {'PASS' if bad == 0 else f'{bad} 个问题'} ===")
sys.exit(0 if bad == 0 else 1)
