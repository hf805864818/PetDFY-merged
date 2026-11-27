# PetDFYPrefs — Makefile（reconstruction）

# 产物：PreferenceBundle dylib（arm64，iOS 16），装到
#   /Library/PreferenceBundles/PetDFYPrefs.bundle/PetDFYPrefs
#
#   make SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
#   make THEOS=...            # 或用 theos 的 common.mk
#
# 依赖：Preferences / UIKit / CoreGraphics / AVFoundation / ImageIO /
#       UniformTypeIdentifiers（系统框架）；无第三方库。

BUNDLE_NAME := PetDFYPrefs
CC          ?= clang
TARGET      ?= arm64-apple-ios16.0
MIN_VERSION := 16.0
SDKROOT     ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
BUILD_DIR   := build

SOURCES := $(wildcard *.m)

CFLAGS := -target $(TARGET) -mios-version-min=$(MIN_VERSION) -O2 -g -Wall \
          -Wno-deprecated-declarations -fobjc-arc -fmodules \
          -I. -isysroot $(SDKROOT)
LDFLAGS := -dynamiclib -install_name @rpath/$(BUNDLE_NAME).dylib \
           -framework Foundation -framework UIKit -framework CoreGraphics \
           -framework AVFoundation -framework ImageIO -framework UniformTypeIdentifiers \
           -framework Preferences -framework CoreFoundation

.PHONY: all clean bundle

all: $(BUILD_DIR)/$(BUNDLE_NAME).dylib

$(BUILD_DIR)/$(BUNDLE_NAME).dylib: $(SOURCES) $(wildcard *.h)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SOURCES)
	@echo "built $@"

# 组装 .bundle 目录（dylib + Info.plist + 资源）
bundle: all
	@mkdir -p $(BUILD_DIR)/$(BUNDLE_NAME).bundle
	cp $(BUILD_DIR)/$(BUNDLE_NAME).dylib $(BUILD_DIR)/$(BUNDLE_NAME).bundle/$(BUNDLE_NAME)
	cp Info.plist $(BUILD_DIR)/$(BUNDLE_NAME).bundle/Info.plist
	@echo "bundle ready: $(BUILD_DIR)/$(BUNDLE_NAME).bundle"

clean:
	rm -rf $(BUILD_DIR)
