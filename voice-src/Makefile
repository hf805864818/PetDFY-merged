# petdfy-voice — Makefile (reconstruction)
#
# 目标：arm64 iOS 16 CLI helper，ARC，ObjC。
#
#   make                      # 用 clang + iPhoneOS SDK
#   make SDKROOT=...          # 指定 SDK
#   make OPENSSL_DIR=...      # 指向含 include/openssl 与 lib/libcrypto.a 的目录
#   make clean
#
# 原二进制把 opus 1.6.1 / OpenSSL 3 / miniz 全静态编进来（见 README），本工程改为
# 链接同版本库，源码里的调用参数与原实现逐项对齐。

APP        := petdfy-voice
SRC_DIR    := .
BUILD_DIR  := build

CC         ?= clang
TARGET     ?= arm64-apple-ios16.0
SDKROOT    ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
MIN_VERSION := 16.0

VENDOR      := vendor
OPUS_DIR   ?= $(VENDOR)/opus
OPENSSL_DIR?= $(VENDOR)/openssl
MINIZ_DIR  ?= $(VENDOR)/miniz

SOURCES := $(SRC_DIR)/main.m \
           $(SRC_DIR)/PDVoiceWorker.m \
           $(SRC_DIR)/PDWeTypeClient.m \
           $(SRC_DIR)/PDWeTypeKeyAgreement.m \
           $(SRC_DIR)/PDVoiceProtocol.m \
           $(SRC_DIR)/PDVoiceOutput.m \
           $(SRC_DIR)/PDAssetImporter.m

ifeq ($(wildcard $(MINIZ_DIR)/miniz.c),)
$(error vendor/miniz/miniz.c 缺失：把 miniz 单文件实现放到 $(MINIZ_DIR)/ 再编)
endif
SOURCES += $(MINIZ_DIR)/miniz.c

OBJC_FLAGS := -fobjc-arc -fmodules -fobjc-exceptions -fexceptions
COMMON_FLAGS := -target $(TARGET) -mios-version-min=$(MIN_VERSION) \
                -O2 -g -Wall -Wno-deprecated-declarations \
                -I$(SRC_DIR) -I$(OPUS_DIR)/include -I$(OPENSSL_DIR)/include -I$(MINIZ_DIR)

FRAMEWORKS := -framework Foundation -framework Security
LIBS       := -L$(OPUS_DIR)/lib -lopus -L$(OPENSSL_DIR)/lib -lcrypto -lz

.PHONY: all clean check

all: $(BUILD_DIR)/$(APP)

$(BUILD_DIR)/$(APP): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(COMMON_FLAGS) $(OBJC_FLAGS) -isysroot $(SDKROOT) \
	      -o $@ $(SOURCES) $(FRAMEWORKS) $(LIBS)
	@echo "built $@"

# 线路格式自检（不需要 iOS 工具链，纯 Python）
check:
	python3 ../../tools/proto_ref.py

clean:
	rm -rf $(BUILD_DIR)

