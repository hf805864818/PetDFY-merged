# PetDFY — Theos 工程（CI 构建用，基线：源码完整版 0.1.8-editable）
#
# 产出三个 dylib + 一份 layout（资源/plist/偏好包）：
#   PetDFY.dylib        主体（54 类，还原 + 可编辑化扩展）
#   PDFYEnhance.dylib   透明度 / 仅主屏 / 单击气泡
#   PDFYSecurity.dylib  数据目录与密钥文件权限
#
# 用法：
#   export THEOS=$HOME/theos
#   make assets        # 把 assets_src 装进 layout（CI 必做）
#   make clean all     # 只编译
#   make package       # 出 deb
#
# 注意：src/Aux 是 Windows 保留设备名，仓库中已重命名为 src/Auxiliary。

# 只出 arm64：Linux 上的 clang/ld64.lld 编 arm64e 时 cpusubtype 不写 0x80000002，
# lipo 会判定两个 slice 同架构而拒绝合并。arm64 在 arm64e 设备上可正常加载。
# 设备侧（A12+）的 Preferences.app / SpringBoard 只接受 arm64e；arm64 会被 dlopen_preflight 拒绝
export ARCHS ?= arm64e
export TARGET = iphone:clang:latest:16.0
export INSTALL_TARGET_PROCESSES = SpringBoard

BUNDLE_DIR = layout/Library/Application Support/PetDFY.bundle

include $(THEOS)/makefiles/common.mk

# ---------------------------------------------------------------- 主体
TWEAK_NAME = PetDFY
PetDFY_FILES = $(shell find src/Core src/Sources src/Ext -name '*.m')
PetDFY_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function \
                -Wno-nullability-completeness -Wno-objc-multiple-method-names \
                -Wno-unused-variable -Wno-unused-but-set-variable \
                -Isrc -Isrc/Core -Isrc/Sources -Isrc/Ext -Ishim -Wno-error
PetDFY_FRAMEWORKS = Foundation UIKit Metal MetalKit MetalPerformanceShaders QuartzCore \
                    CoreGraphics ImageIO AVFoundation AVFAudio AudioToolbox Security \
                    CoreFoundation CoreText Accelerate
PetDFY_PRIVATE_FRAMEWORKS = MobileCoreServices
# -lz：PDZipExtract 的进程内 ZIP 解压依赖 libz（iOS SDK 自带 libz.tbd）
# -fuse-ld=lld：Darwin target 下 clang 会解析为 ld64.lld（Mach-O），
# 否则 Linux 上会误用系统 GNU ld / ELF ld.lld，报 unknown argument '-dynamic'
PetDFY_LDFLAGS = -Wl,-undefined,dynamic_lookup -lz -fuse-ld=lld
PetDFY_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

# ---------------------------------------------------------------- 增强层
TWEAK_NAME = PDFYEnhance
PDFYEnhance_FILES = src/Auxiliary/PDFYEnhance.m
PDFYEnhance_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Isrc -Isrc/Core -Isrc/Sources -Ishim -Wno-error
PDFYEnhance_FRAMEWORKS = Foundation UIKit
PDFYEnhance_LDFLAGS = -fuse-ld=lld
PDFYEnhance_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

# ---------------------------------------------------------------- 权限加固
TWEAK_NAME = PDFYSecurity
PDFYSecurity_FILES = src/Auxiliary/PDFYSecurity.m
PDFYSecurity_CFLAGS = -fno-objc-arc -Isrc -Isrc/Core -Ishim -Wno-error
PDFYSecurity_FRAMEWORKS = Foundation
PDFYSecurity_LDFLAGS = -fuse-ld=lld
PDFYSecurity_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

# ---------------------------------------------------------------- layout / 素材
.PHONY: assets
assets:
	@mkdir -p "$(BUNDLE_DIR)"
	@if [ -d assets_src/originals ]; then \
	  cp -R assets_src/originals assets_src/live "$(BUNDLE_DIR)/"; \
	  echo "assets -> $(BUNDLE_DIR)"; \
	else \
	  echo "assets_src/originals 不存在，跳过素材安装（仅编译）"; \
	fi
	@if [ -f assets_src/PDLayout.json ]; then cp assets_src/PDLayout.json "$(BUNDLE_DIR)/PDLayout.json"; fi

after-install::
	install.exec "killall -9 SpringBoard" || true

# ---------------------------------------------------------------- arm64e 修正
# Linux 的 ld64.lld 编 arm64e 时 cpusubtype 仍写 0，dyld 会拒（Preferences.app 尤其严格）。
# 打包前把 staging 里的 Mach-O header 改成 0x80000002（只改 header，不改代码）。
before-package::
	@for f in "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/"*.dylib; do \
	  [ -f "$$f" ] && python3 tools/fix_arm64e_subtype.py "$$f" || true; \
	done
	@if [ -f "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/PetDFYPrefs.bundle/PetDFYPrefs" ]; then \
	  python3 tools/fix_arm64e_subtype.py "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/PetDFYPrefs.bundle/PetDFYPrefs"; \
	fi