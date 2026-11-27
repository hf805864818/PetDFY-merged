# build.076 团队复审与修复

## 最新崩溃

075 的两份 SpringBoard ips 仍一致指向：`_Block_copy → -[PDPetView setFrameHandler:] → -[PDOverlayController ensureWindow]`。

独立只读代理点验目标文件确认：074 是 `___copy_helper_block_e8_32w`，075 是 `___copy_helper_block_e8_32s`。weak 改 strong 仍然生成 custom copy helper，无法绕开本机该崩溃路径。

## 修复

- 四个 Pet 回调、方向回调、NSTimer、AI 回调、聊天回调、悬浮按钮回调全部通过 `PDOverlayShared()` 运行时取单例，不再捕获局部对象。
- 首帧 `advanceKeyboardAnimation:` 和方向动画也改为零捕获。
- 删除 `ensureChat` 中仍存在的 `PDIsDeviceLocked()` 提前返回（第二独立代理确认其导致聊天/语音 nil）。
- 保留 074/075 的桌面 scene、60 FPS、运动、触摸、声音、投掷实现。

## 验证

```text
双架构编译链接         exit 0
arm64/arm64e           PASS
双架构 CodeDirectory   PASS
deb 三条 dylib 解包比对 MATCH
主体 SHA-256           3aa80bcbafd88f43446ee5394f0c19201a05a54708af90c59c4364cd81f06ff2
deb SHA-256            见最终交付
```

真机安装与注销：NOT RUN。

## 回滚

修改前源码：`build76-backup-20261126/`；可安装 build.075 旧包或创建 `/var/mobile/Media/petdfy-disable`。
