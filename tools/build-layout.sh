#!/usr/bin/env bash
#
# tools/build-layout.sh — 装配安装树（layout）
#
# 本工程是「纯源码」包，不含：
#   · 设置面板 PetDFYPrefs.bundle（二进制）
#   · 素材 bundle 骨架（Whale.metal / asset-manifest.json / 本地化）
#   · 语音 helper（petdfy-voice）
# 这些从 vendor/base 取：
#   · PetDFY_1.2.1_RootHide.deb  —— 原版 deb，提供上述全部资源
#   · petdfy-voice               —— TTS/ASR helper 可执行
#
# 用法：
#   bash tools/build-layout.sh            # 默认从 vendor/base 取
#   BASE_DEB=/path/x.deb bash tools/build-layout.sh
#
# 产出：layout/（可直接被 make package 打包）
#
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_DEB="${BASE_DEB:-vendor/base/PetDFY_1.2.1_RootHide.deb}"
VOICE_BIN="${VOICE_BIN:-vendor/base/petdfy-voice}"
ASSETS_SRC="${ASSETS_SRC:-assets_src}"

[ -f "$BASE_DEB" ] || { echo "缺少基础 deb: $BASE_DEB" >&2; exit 2; }

echo "== 1. 解基础 deb 到 layout =="
rm -rf layout
mkdir -p layout
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x "$BASE_DEB" layout
    dpkg-deb -e "$BASE_DEB" layout/DEBIAN
else
    # 兜底：ar + tar（不依赖 dpkg）
    TMP=$(mktemp -d)
    ( cd "$TMP" && ar x "$OLDPWD/$BASE_DEB" )
    for f in "$TMP"/data.tar.*; do
        case "$f" in
            *.xz)  tar -xJf "$f" -C layout ;;
            *.gz)  tar -xzf "$f" -C layout ;;
            *.lzma) xz --format=lzma -dc "$f" | tar -xf - -C layout ;;
        esac
    done
    mkdir -p layout/DEBIAN
    for f in "$TMP"/control.tar.*; do
        case "$f" in
            *.xz)  tar -xJf "$f" -C layout/DEBIAN ;;
            *.gz)  tar -xzf "$f" -C layout/DEBIAN ;;
        esac
    done
    rm -rf "$TMP"
fi

# 防御：某些打包方式把 staging 目录一起打进 data.tar
if [ -d layout/rootfs ]; then
    echo "  !! layout 含 rootfs/ 前缀，展开"
    cp -R layout/rootfs/. layout/
    rm -rf layout/rootfs
fi

echo "== 2. 清掉骨架里的旧 dylib（由本次编译产出替代）=="
rm -f layout/Library/MobileSubstrate/DynamicLibraries/PetDFY.dylib
rm -f layout/Library/MobileSubstrate/DynamicLibraries/PDFYEnhance.dylib
rm -f layout/Library/MobileSubstrate/DynamicLibraries/PDFYSecurity.dylib

echo "== 3. 设置面板（源码优先，回退二进制）=="
PREFS_BUNDLE="layout/Library/PreferenceBundles/PetDFYPrefs.bundle"
if [ -f build/prefs/PetDFYPrefs ]; then
    mkdir -p "$PREFS_BUNDLE"
    cp -f build/prefs/PetDFYPrefs "$PREFS_BUNDLE/PetDFYPrefs"
    chmod 0755 "$PREFS_BUNDLE/PetDFYPrefs"
    echo "  用 prefs-src 编译产物（$(stat -c%s "$PREFS_BUNDLE/PetDFYPrefs" 2>/dev/null || wc -c < "$PREFS_BUNDLE/PetDFYPrefs") bytes）"
else
    echo "  未发现 build/prefs/PetDFYPrefs，沿用 vendor deb 里的二进制"
fi

# build.96：vendor Root.plist 的 Outfit 只有 4 项（maid/cape/crew/sailor）。
# 用源码树里的 15 项版本覆盖；缺文件时保持原样，不影响出包。
if [ -f prefs-src/Root.plist ]; then
    cp -f prefs-src/Root.plist "$PREFS_BUNDLE/Root.plist"
    echo "  Root.plist -> 15 outfits"
else
    echo "  WARN prefs-src/Root.plist 缺失，设置页仍是 4 套"
fi

echo "== 4. 放语音 helper =="
if [ -f "$VOICE_BIN" ]; then
    VOICE_DIR="layout/Library/Application Support/PetDFY"
    mkdir -p "$VOICE_DIR"
    cp -f "$VOICE_BIN" "$VOICE_DIR/petdfy-voice"
    chmod 0755 "$VOICE_DIR/petdfy-voice"
    echo "  petdfy-voice -> $VOICE_DIR ($(stat -c%s "$VOICE_DIR/petdfy-voice" 2>/dev/null || wc -c < "$VOICE_DIR/petdfy-voice") bytes)"
else
    echo "  !! 未找到 $VOICE_BIN（语音功能将不可用）" >&2
fi

echo "== 5. 装素材 =="
BUNDLE="layout/Library/Application Support/PetDFY.bundle"
mkdir -p "$BUNDLE"
if [ -d "$ASSETS_SRC/originals" ]; then
    cp -R "$ASSETS_SRC/originals" "$BUNDLE/"
    echo "  originals -> $BUNDLE/originals"
else
    echo "  !! $ASSETS_SRC/originals 不存在：桌面不会出现角色（需另行提供素材包）" >&2
fi
if [ -d "$ASSETS_SRC/live" ]; then
    cp -R "$ASSETS_SRC/live" "$BUNDLE/"
    echo "  live -> $BUNDLE/live"
else
    echo "  !! $ASSETS_SRC/live 不存在：缺 live/model.json 时 ensureWindow 直接失败" >&2
fi
[ -f "$ASSETS_SRC/PDLayout.json" ] && cp -f "$ASSETS_SRC/PDLayout.json" "$BUNDLE/"

echo "== 6. 生成 postinst（RootHide 镜像 + 权限）=="
mkdir -p layout/DEBIAN
cat > layout/DEBIAN/postinst <<'POSTINST'
#!/bin/sh
set -e
JB=""
for c in /var/jb /var/containers/Bundle/Application/.jbroot-* /var/containers/Bundle/Application/*/.jbroot-* /.jbroot-* /rootfs; do
    [ -d "$c" ] || continue
    case "$c" in *\**) continue ;; esac
    if [ -d "$c/Library" ] && [ -z "$JB" ]; then JB="$c"; fi
done
[ -n "$JB" ] || JB=""

BUNDLE="$JB/Library/Application Support/PetDFY.bundle"
for name in originals live .asset-state; do
    [ -e "$BUNDLE/$name" ] || continue
    chown -hR 501:501 "$BUNDLE/$name" 2>/dev/null || true
    chmod 0755 "$BUNDLE/$name" 2>/dev/null || true
done
VOICE="$JB/Library/Application Support/PetDFY/petdfy-voice"
if [ -f "$VOICE" ]; then
    chown 501:501 "$VOICE" 2>/dev/null || true
    chmod 0755 "$VOICE" 2>/dev/null || true
fi

# ---- build.95：素材根 /var/mobile/Xfy ----
# postinst 跑在 Sileo 的临时 root 里，mkdir 建完就丢弃（实测 find 找不到）。
# 真实目录由 dylib 运行时创建（PDAssetInstaller ensureAssetRootLayout:）。
# 这里只做提示 + 尽力拷贝（若环境允许）。
XFY="/var/mobile/Xfy"

if [ -d "$XFY" ]; then
    echo "PetDFY: asset root exists: $XFY"
else
    echo "PetDFY: asset root will be created at first launch: $XFY"
    echo "         (postinst runs in a temp root; the tweak creates the real dir)"
fi

# 尽力拷贝（在临时 root 里通常无效，不影响运行）
for f in Whale.metal Info.plist; do
    if [ -f "$BUNDLE/$f" ] && [ ! -f "$XFY/$f" ]; then
        cp -f "$BUNDLE/$f" "$XFY/$f" 2>/dev/null || true
    fi
done

# 把 dylib / plist / 偏好包镜像进 jbroot（RootHide 注入路径）
for real in /var/containers/Bundle/Application/.jbroot-* \
            /var/containers/Bundle/Application/*/.jbroot-* \
            /.jbroot-* /var/jb; do
    [ -d "$real" ] || continue
    [ -L "$real" ] && continue
    tgt="$real/Library/MobileSubstrate/DynamicLibraries"
    mkdir -p "$tgt" 2>/dev/null || continue
    for f in PetDFY.dylib PetDFY.plist PDFYEnhance.dylib PDFYEnhance.plist PDFYSecurity.dylib PDFYSecurity.plist; do
        [ -f "/Library/MobileSubstrate/DynamicLibraries/$f" ] || continue
        cp -f "/Library/MobileSubstrate/DynamicLibraries/$f" "$tgt/$f" 2>/dev/null || true
    done
    echo "PetDFY: mirrored dylibs into $tgt" >&2
done

exit 0
POSTINST
chmod 0755 layout/DEBIAN/postinst

echo "== 7. 布局自检 =="
fail=0
[ -d layout/Library/PreferenceBundles/PetDFYPrefs.bundle ] && echo "  OK 偏好包" || { echo "  FAIL 偏好包缺失" >&2; fail=1; }
[ -f "$BUNDLE/Whale.metal" ] && echo "  OK Whale.metal" || { echo "  FAIL Whale.metal 缺失" >&2; fail=1; }
[ -f "layout/Library/Application Support/PetDFY/petdfy-voice" ] && echo "  OK petdfy-voice" || echo "  WARN petdfy-voice 缺失"
[ -f "$BUNDLE/live/model.json" ] && echo "  OK live/model.json" || echo "  WARN live/model.json 缺失（角色不显示）"
grep -q '/var/mobile/Xfy' layout/DEBIAN/postinst && echo "  OK postinst 创建 Xfy" || { echo "  FAIL postinst 缺 Xfy 创建" >&2; fail=1; }
[ -f layout/DEBIAN/control ] && echo "  OK control" || { echo "  FAIL control 缺失" >&2; fail=1; }

echo "== layout 大小 =="
du -sh layout

[ "$fail" = "0" ] || { echo "layout 自检未通过" >&2; exit 1; }
echo "LAYOUT OK"
