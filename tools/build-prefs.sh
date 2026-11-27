#!/usr/bin/env bash
#
# tools/build-prefs.sh — 用第四套（reverse-full）还原的源码编译设置面板
#
# 产物：build/prefs/PetDFYPrefs（PreferenceBundle 可执行）
#
# 说明：
#   prefs-src/ 是 PetDFYPrefs 的源码还原（18 类 / 264 方法 / 55 C 函数，
#   经独立审计 16 条差异全部修复）。本脚本只负责编译，不改源码。
#
#   若编译失败，build-layout.sh 会自动回退到 vendor deb 里的二进制版本，
#   不影响出包 —— 这是有意的降级路径。
#
# 用法：
#   bash tools/build-prefs.sh
#   SDKROOT=/path/iPhoneOS16.5.sdk bash tools/build-prefs.sh
#   ARCH=arm64e bash tools/build-prefs.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d prefs-src ] || { echo "缺少 prefs-src/" >&2; exit 2; }

SDKROOT="${SDKROOT:-}"
if [ -z "$SDKROOT" ]; then
    if [ -n "${THEOS:-}" ] && compgen -G "$THEOS/sdks/iPhoneOS*.sdk" >/dev/null; then
        SDKROOT=$(ls -d "$THEOS"/sdks/iPhoneOS*.sdk | tail -1)
    else
        SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
    fi
fi
[ -n "$SDKROOT" ] && [ -d "$SDKROOT" ] || { echo "找不到 iOS SDK（设置 SDKROOT 或 THEOS）" >&2; exit 2; }

CC="${CC:-clang}"
ARCH="${ARCH:-arm64}"
TRIPLE="${TRIPLE:-${ARCH}-apple-ios16.0}"
OUT="build/prefs"
mkdir -p "$OUT"

SRCS=$(ls prefs-src/*.m)
echo "SDK: $SDKROOT"
echo "CC: $($CC --version | head -1)"
echo "源文件: $(echo "$SRCS" | wc -l)"
echo "目标: $TRIPLE"

# shellcheck disable=SC2086
"$CC" -target "$TRIPLE" -isysroot "$SDKROOT" \
    -fobjc-arc -fmodules -fobjc-exceptions \
    -O2 -g -Wno-deprecated-declarations -Wno-unused-function \
    -Wno-nullability-completeness -Wno-objc-multiple-method-names \
    -Wno-unused-variable -Wno-unused-but-set-variable \
    -I prefs-src -I prefs-shim \
    -dynamiclib -fuse-ld=lld -install_name @rpath/PetDFYPrefs.dylib \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    -framework AVFoundation -framework ImageIO -framework UniformTypeIdentifiers \
    -framework Preferences -framework CoreFoundation \
    -o "$OUT/PetDFYPrefs" $SRCS

if command -v ldid >/dev/null 2>&1; then
    ldid -S "$OUT/PetDFYPrefs" && echo "ldid ok"
else
    echo "  警告: 未找到 ldid，跳过签名" >&2
fi

echo "built: $OUT/PetDFYPrefs ($(stat -c%s "$OUT/PetDFYPrefs" 2>/dev/null || wc -c < "$OUT/PetDFYPrefs") bytes)"