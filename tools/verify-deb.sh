#!/usr/bin/env bash
#
# tools/verify-deb.sh — 校验 CI 产出的 deb（Linux / macOS 均可运行）
#
set -euo pipefail
cd "$(dirname "$0")/.."

DEB=$(ls -1 packages/*.deb 2>/dev/null | head -1 || true)
[ -n "$DEB" ] || { echo "没有产出 deb" >&2; exit 1; }
echo "DEB: $DEB"
ls -la "$DEB"

echo "== deb 元数据 =="
dpkg-deb -f "$DEB"

echo "== 内容清单 =="
dpkg-deb -c "$DEB"

echo "== 致命检查：rootfs 前缀 =="
if dpkg-deb -c "$DEB" | awk '{print $NF}' | grep -qE '^(\./)?rootfs(/|$)'; then
    echo "FAIL: deb 内含 rootfs/ 前缀路径，安装会报 'error creating directory ./rootfs/...'" >&2
    dpkg-deb -c "$DEB" | awk '{print $NF}' | grep -E '^(\./)?rootfs(/|$)' | head -10 >&2
    exit 1
fi
echo "OK: 无 rootfs 前缀"

TMP=$(mktemp -d)
dpkg-deb -x "$DEB" "$TMP"

echo "== 三个 dylib =="
fail=0
for name in PetDFY PDFYEnhance PDFYSecurity; do
    D="$TMP/Library/MobileSubstrate/DynamicLibraries/$name.dylib"
    if [ -f "$D" ]; then
        echo "  OK $name.dylib ($(stat -c%s "$D" 2>/dev/null || wc -c < "$D") bytes)"
    else
        echo "  FAIL 缺 $name.dylib" >&2
        fail=1
    fi
done

echo "== Mach-O 架构 =="
python3 - "$TMP/Library/MobileSubstrate/DynamicLibraries/PetDFY.dylib" <<'PY'
import struct, sys
p = sys.argv[1]
d = open(p, "rb").read()
magic = struct.unpack_from("<I", d, 0)[0]
if magic == 0xBEBAFECA:
    n = struct.unpack_from(">I", d, 4)[0]
    names = {0x0100000C: "arm64", 0x01000007: "arm", 0x0000000C: "x86_64"}
    have = []
    for i in range(n):
        ct, cs, off, size, al = struct.unpack_from(">5I", d, 8 + i * 20)
        nm = names.get(ct, hex(ct))
        have.append(nm)
        print(f"  arch[{i}] {nm} subtype={hex(cs)} size={size}")
    print("  ARCH:", ",".join(have))
elif magic == 0xFEEDFACF:
    ct = struct.unpack_from("<I", d, 4)[0]
    print(f"  thin mach-o cputype={hex(ct)}")
else:
    print(f"FAIL: 未知 magic {hex(magic)}"); sys.exit(1)
PY

echo "== 设置面板 =="
PREFS_DIR="$TMP/Library/PreferenceBundles/PetDFYPrefs.bundle"
if [ -d "$PREFS_DIR" ]; then
    ls "$PREFS_DIR" | head
    if [ -f "$PREFS_DIR/Root.plist" ]; then
        if ! python3 - "$PREFS_DIR/Root.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
n = 0
for it in d.get("items", []):
    if it.get("key") == "Outfit":
        n = len(it.get("validValues", []))
print(f"  Outfit validValues={n}")
sys.exit(0 if n >= 15 else 1)
PY
        then
            echo "FAIL: 设置页服装少于 15 项（Root.plist 未覆盖？）" >&2
            fail=1
        fi
    else
        echo "FAIL: 缺 Root.plist" >&2
        fail=1
    fi
else
    echo "FAIL: 缺 PetDFYPrefs.bundle" >&2
    fail=1
fi

echo "== 素材骨架 =="
BUNDLE="$TMP/Library/Application Support/PetDFY.bundle"
if [ -d "$BUNDLE" ]; then
    # build.96：着色器是渲染硬依赖，bundle 存在时必须随包；缺了会在运行时走内嵌兜底，
    # 但打包阶段就该报出来，避免又出现 build.95 那种“素材根没 Whale.metal”的静默故障。
    [ -f "$BUNDLE/Whale.metal" ] && echo "  OK Whale.metal" || { echo "  FAIL 缺 Whale.metal" >&2; fail=1; }
    [ -f "$BUNDLE/live/model.json" ] && echo "  OK live/model.json" || echo "  WARN 缺 live/model.json（程序/素材分离包允许）"
else
    echo "  WARN 无 PetDFY.bundle（程序/素材分离包）"
fi

echo "== 语音 helper =="
V="$TMP/Library/Application Support/PetDFY/petdfy-voice"
[ -f "$V" ] && echo "  OK petdfy-voice ($(stat -c%s "$V" 2>/dev/null || wc -c < "$V") bytes)" || echo "  WARN 缺 petdfy-voice"

echo "== 合并产物标识（第一套修复点）=="
DYLIB="$TMP/Library/MobileSubstrate/DynamicLibraries/PetDFY.dylib"
for s in "PetDFY.Import" "AssetImports" "asset-import-token" "PDZipExtract" "boot guard" "model injected"; do
    if strings -a "$DYLIB" | grep -q "$s"; then
        echo "  OK $s"
    else
        echo "  WARN 未找到 $s"
    fi
done

rm -rf "$TMP"
[ "$fail" = "0" ] || { echo "VERIFY FAILED" >&2; exit 1; }
echo "VERIFY OK"
