# build.075 崩溃证据与修复

## 最新证据

`SpringBoard-2026-11-26-104631.ips` 与 `104637.ips` 的 faultingThread 均为 0，堆栈一致：

```text
EXC_BAD_ACCESS / SIGBUS
_call_custom_copy_helper
_call_copy_helpers_excp
_Block_copy
-[PDPetView setFrameHandler:]
-[PDOverlayController ensureWindow]
-[PDOverlayController start]
__PDBootstrap_block_invoke
```

074 在 `pet init: OK` 后给 `frameHandler` 设置捕获 `weakSelf` 的 block，因此 `petdfy-rig.txt` / `petdfy-sound.txt` 尚未生成就已崩溃。

## 修复

- 启动、Pet 回调、方向、定时器、AI、聊天、声音和云语音回调中的局部 weakSelf/weakVoice 捕获改为普通强捕获，避免 weak-byref custom copy helper。
- 所有控制器/服务属于 SpringBoard 进程生命周期；异步语音块仅延长到任务结束。
- 启动标记、启动守卫和包版本升至 build.075。
- 保留 074 的桌面 scene 选择、60 FPS、运动、长按聊天/语音和投掷修复。

## 验证

```text
make -j2 all                  exit 0
PDOverlayController arm64 object weak copy/move symbols: none
PetDFY architectures          arm64 arm64e
deb control version           0.1.8-e2+build.075
三条 dylib 解包与 layout      MATCH
主体 dylib SHA-256            6d87f2d13f5b0731fae43b37bdf70af99eb2300a200fb729fc94c8b9d25118b6
deb SHA-256                   8903beb467ec909676c2996bd42eae3c0f4019f2b0828a8517231418014a6e0d
deb bytes                     36,093,056
```

真机安装/注销：NOT RUN（未自动执行）。

## 回滚

修改前源码与哈希位于 `build75-backup-20261126/`；旧包可安装 build.074。永久停用仍可创建 `/var/mobile/Media/petdfy-disable` 后注销。
