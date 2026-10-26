# Frpc

**简体中文** | [English](README.en.md)

使用 Flutter / Material 3 开发的 Android frpc 客户端。支持 **Android 8.0+、ARM64、已 Root 手机**；包名延续 `dev.kuugo.frpc`，可覆盖旧版安装。

## 功能

- **多配置**：新建、编辑、重命名、复制、删除和导入 TOML。所选配置用于下次启动；更改选择或保存内容不会中断正在运行的隧道。当前只运行一个配置，每个 TOML 可以包含多个代理。
- **内核更新**：从 `fatedier/frp` 官方最新稳定版获取 Android ARM64 内核，下载官方 SHA256 清单并校验归档。只提取 ARM64 frpc 可执行文件，不展开任意归档路径。下载、校验或解压失败不切换已安装内核。
- **更新生效**：更新只替换 App 私有目录中的待用内核；当前进程继续运行。点击“应用并重启”后才部署新内核。每次启动先执行新内核的 `verify -c`；校验失败保留原隧道。
- **外观**：跟随系统、浅色、深色；青绿、海蓝、鸢紫、暖橙主题色，设置本地持久保存。
- **后台守护**：Root 独立 shell 监控 frpc，退出后按 3–60 秒退避自动拉起；恢复守护时接管仍存活的子进程，避免重复运行。手动停止同时关闭自动拉起。
- **日志**：最近 120 行、定时刷新、复制。建议保持 `log.to = "console"`；输出文件约 2 MB 时截断，保留最近 64 KB。

## 开机启动由 Android 系统管理

在设置中打开“开机恢复隧道”，再到“系统自启动管理”允许 Frpc 自启动。App 通过 Android 的 `BOOT_COMPLETED` 广播启动前台服务，随后恢复上次运行的配置。**不安装、不维护 Magisk / KernelSU / APatch 开机脚本**；Root 仅负责后台进程管理。

开机恢复使用上次成功启动时保存的配置内容；之后编辑或切换配置不会悄悄改变开机使用的内容。手动停止后不会在下次开机自动恢复，直到再次手动启动。不同 ROM 的自启动设置页不同，自动跳转失败会进入应用详情，需手动放行自启动和后台运行。Android 强行停止、ROM 限制、Doze 或网络策略仍可能影响开机和熄屏运行，需要真机确认。

## 从 1.0 升级

- 保留原包名和当前开发签名，原单配置会迁移为“默认配置”。
- 旧的 Root 开机开关不会映射为新版系统开机开关。
- 升级广播及首次打开会尝试删除旧版 `/data/adb/service.d/90-frpc-android.sh` 和旧 `boot.sh`。若授权被拒绝或超时，设置页会显示待清理提示，可再次授权清理。
- 请打开一次新版确认迁移已完成，再使用新版系统自启动设置。

## 使用

1. 在“配置”中新建或编辑 TOML，填写 `serverAddr`、`serverPort`、`auth.token` 以及代理端口。
2. 在概览选择配置并启动，允许通知和 Root 授权。
3. 通过日志确认服务器登录与代理启动成功；“进程运行中”不代表服务器连接成功。
4. 在设置中调整主题、自启动和内核版本。内置内核为官方 Android ARM64 `0.71.1`，建议 frps 使用兼容版本。

配置和内核保存在应用私有目录；运行副本位于 Root 私有目录 `/data/adb/frpc-android`。配置不参与系统云备份和设备迁移。卸载前请先停止隧道；Root 文件不会被 Android 卸载流程自动清除。

## 开发与构建

已使用 Flutter **3.47.8 / Dart 3.13.7** 验证。需要 JDK 17、Android SDK 36（编译）、Build Tools 35，以及 Android 工具链。最低 Android API 26，目标 API 35。

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

构建产物在 `build/app/outputs/flutter-apk/app-release.apk`。当前 release 构建沿用本机 debug 密钥，方便覆盖旧版；正式分发前应配置自己的长期签名。

本项目只使用预编译原生库，无 C/C++ 编译步骤。若本机已有 LLVM，可把 `FRPC_LLVM_STRIP` 环境变量设为 `llvm-strip` 的绝对路径，再构建以移除预编译库的调试符号、缩小 APK；仅处理项目构建副本，不修改 Flutter 缓存内核。

若 Windows 上 Flutter 选择了不兼容的 Android Studio JDK，请给 Flutter 配置 JDK 17，或使用 `GRADLE_OPTS=-Dorg.gradle.java.home=<JDK17路径>` 指定构建环境。Windows 的 Flutter SDK 应使用无中文路径；在大小写敏感目录运行时，SDK 文件路径大小写也必须匹配。

主要目录：`lib/` 为 Flutter 界面与状态；`android/app/src/main/java/dev/kuugo/frpc/` 为平台通道、配置存储、内核更新和后台服务；`android/app/src/main/assets/` 为内置内核及后台守护脚本。

## GitHub Actions 自动构建

[Android CI 工作流](.github/workflows/android.yml) 会在推送、Pull Request 和手动运行时执行格式检查、Flutter 分析及测试、后台守护回归、内核归档测试，随后构建 ARM64 APK、运行 Android Lint 并验证签名与对齐。

把项目上传到 GitHub 后，打开 **Actions → Android CI**，选择一次运行，或点击 **Run workflow** 手动触发。成功后在该次运行的 **Artifacts** 中下载以 `Frpc-arm64-` 开头的产物，解压可获得 APK 和 SHA256 文件；产物保留 14 天。产物名称包含运行编号及重试次数，检查报告也会单独上传。

工作流固定 Flutter 3.47.8、JDK 17 和 Android 构建版本，自动配置缓存及 LLVM 符号裁剪，不需要添加 Secrets，也不会自动发布 GitHub Release。CI 使用运行器生成的 debug 签名，签名可能随运行变化，且与本机签名不同；如需持续覆盖升级，应先配置稳定的正式签名。

## 验证

- Flutter 静态检查与界面测试覆盖：配置切换不重启运行隧道、新建独立配置、主题及暗黑模式、更新失败保留原内核状态。
- `tests/KernelArchiveTest.java` 验证实际归档提取、错误架构、重复内核、路径忽略、截断和版本输入。
- `tests/watchdog.sh` 验证进程退出重启、避免重复守护、接管存活进程和手动停止。
- Root 授权、实际内核更新执行、厂商自启动策略、锁屏联网和开机恢复仍需真机验证。

内核来自 [fatedier/frp](https://github.com/fatedier/frp)，使用 Apache-2.0 许可证，见 assets 的 `FRP-LICENSE`。`tools/fetch-frpc.ps1` 可重新获取并校验固定的内置版本。
