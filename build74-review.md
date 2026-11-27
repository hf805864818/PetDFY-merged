# PetDFY build.074 修复与交付记录

## 结论

- 编译：PASS（arm64 + arm64e，退出码 0）
- 签名：PASS（两个架构均有 sha256 CodeDirectory）
- deb 解包一致性：PASS（三条 dylib 与 layout 逐字节一致）
- 真机安装/注销/交互：NOT RUN（未自动安装，避免再次触发安全模式）

## 修复

1. 窗口场景排除 `SBSystemAperture* / Curtain / CoverSheet / LockScreen`，优先使用前台 `SBWindowScene`。
2. 修复资源、宠物帧回调、AI、聊天、语音采集的 Block 生命周期；方向回调不再用 `object_setIvar` 保存栈 Block。
3. 建窗收尾新增分段日志，启动守卫版本升至 build.074。
4. 绘制与提交上限 60 FPS，不再跟随 120 Hz 屏幕满帧运行。
5. 单击与拖动分离；移动超过 6 stage px 才抓取；松手进入 throw/drop 空中物理并落地。
6. 恢复 AI visible/poll，运动音效继续由 `drainSoundEvents` 投递。
7. 长按 menu 命令接到悬浮按钮；voice 命令接到语音输入；懒建 `PDCloudVoiceInput`。
8. 聊天输入框清空正文、设置真正占位标签并主动聚焦；键盘 key window 切换方向修正。

## MODIFIED（前后 SHA-256 前缀）

| 文件 | 修改前 | 修改后 |
|---|---|---|
| `src/Core/PDBootstrap.m` | `fe23878908c27f7c…` | `c5ebe00186ce64b0…` |
| `src/Core/PDOverlayController.m` | `8b57dd990cf47ab7…` | `6bb78efddf9257ca…` |
| `src/Core/PDPetView.m` | `d40179276f132dc5…` | `98a9b32f0e0974ee…` |
| `src/Core/PDAssetManager.m` | `24997078d7d9f57d…` | `ce0761bef9bb2402…` |
| `src/Core/WNMotion+Input.m` | `46660208bc030fbf…` | `48c709990564243a…` |
| `src/Core/WNMotion+Step.m` | `1883a6052b40df4b…` | `5bc27632d694c804…` |
| `src/Sources/PDAIPetRuntime.m` | `7d043bf2b009ddb6…` | `a93842bad83c6871…` |
| `src/Sources/PDChatController.m` | `bf9fc093f8d6d8d5…` | `f67ecdefaa4a3a56…` |
| `src/Sources/PDCloudVoiceInput.m` | `65a542fe3b3df809…` | `278960ef9b621ccc…` |
| `layout/DEBIAN/control` | `fa5b7bba5291175c…` | `2cd9a51398226251…` |

## VERIFICATION

```text
make -j2 all                         exit 0
Package: com.ojbkclub.petdfy
Version: 0.1.8-e2+build.074
Architecture: iphoneos-arm64e
PetDFY.dylib                        arm64 arm64e
PetDFY.dylib SHA-256                c2fdab692bc1a6f9130ab76565748c9a93941e54bc00a64815f2d07058143192
deb SHA-256                         30a6a72bf704e72f831a8bc15b4f1c6527064651d219397655dc62486dc4e2dc
deb bytes                           36,098,168
```

## ROLLBACK

- 修改前源码：`/var/mobile/Documents/小肥鱼/build74-backup-20261126/`
- 修改前哈希：`build74-backup-20261126/SHA256-before.txt`
- 安装旧包：`dpkg -i /var/mobile/Media/PetDFY_0.1.8-e2+build.073_iphoneos-arm64e.deb`
- 彻底停用：创建 `/var/mobile/Media/petdfy-disable` 后注销。

## 真机定位

```text
/var/mobile/Media/petdfy-diag.txt
/var/mobile/Media/petdfy-draw.txt
/var/mobile/Media/petdfy-rig.txt
/var/mobile/Media/petdfy-sound.txt
```

自主对话/TTS 和云语音仍依赖项目已有的服务配置、网络与麦克风权限；本轮只验证代码链和构建产物，未伪报真机服务调用成功。
