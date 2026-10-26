# Frpc

[简体中文](README.md) | **English**

An Android frpc client built with Flutter and Material 3 for **rooted ARM64 devices running Android 8.0 or later**. The application ID remains `dev.kuugo.frpc`, allowing upgrades over the previous version.

## Features

- **Multiple profiles:** Create, edit, rename, duplicate, delete, and import TOML configurations. The selected profile is used for the next start. Selecting another profile or saving changes does not interrupt the running tunnel. One profile runs at a time, and each configuration can contain multiple proxies.
- **frpc updates:** Download the latest stable Android ARM64 binary from the official `fatedier/frp` releases and verify the archive against the official SHA256 checksum list. Only the ARM64 frpc executable is extracted; other archive paths are not written to disk. A failed download, checksum check, or extraction leaves the installed binary unchanged.
- **Applying updates:** Downloads install a pending binary in the app's private directory while the current process continues running. Use **Apply and restart** to deploy it. Each start runs `verify -c` with the candidate binary before stopping the current tunnel. Failed validation preserves the existing tunnel.
- **Appearance:** Follow the system theme or choose light or dark mode. Select teal, blue, violet, or orange as the theme color. Preferences are saved locally.
- **Background supervision:** An independent root shell monitors frpc and restarts it after an exit, using a retry delay of 3–60 seconds. A replacement supervisor adopts a surviving child process to avoid duplicate instances. Stopping the tunnel also disables automatic restarts.
- **Logs:** View the latest 120 lines, refresh automatically, and copy logs. Keep `log.to = "console"` to display frpc output in the app. The output file is truncated at approximately 2 MB, with the latest 64 KB retained separately.

## Android-managed boot startup

Enable **Restore tunnel at boot** in the app settings, then allow Frpc in your phone's **system autostart manager**. Android's `BOOT_COMPLETED` broadcast starts a foreground service, which restores the previously running configuration. The app **does not install or maintain Magisk, KernelSU, or APatch boot scripts**. Root is used for background process management.

Boot recovery uses the configuration content saved at the last successful start. Later edits or profile selections do not silently change what will run after a reboot. Manually stopping the tunnel prevents boot recovery until you start it again.

Autostart settings vary by device manufacturer. If the dedicated settings page is unavailable, the app opens its Android app details page instead. Allow autostart and background execution manually. Android force-stop behavior, ROM restrictions, Doze, and network policies can still affect boot recovery and operation with the screen off; verify these on your device.

## Upgrading from 1.0

- The application ID and current development signing certificate are retained. Your existing configuration is migrated to a profile named **默认配置** (Default profile).
- The old root boot setting is not carried over to the new Android-managed boot setting.
- On upgrade and first launch, the app attempts to remove the legacy `/data/adb/service.d/90-frpc-android.sh` script and the old `boot.sh`. If root access is denied or the operation times out, settings show a pending cleanup notice so you can retry.
- Open the updated app once to confirm migration and cleanup before configuring system autostart.

## Usage

The current app interface is in Simplified Chinese. The English labels below describe the corresponding controls.

1. Open **Profiles (配置)** and create or edit a TOML configuration. Set `serverAddr`, `serverPort`, `auth.token`, and the proxy ports.
2. Select a profile on **Overview (概览)** and tap **Start (启动)**. Allow notifications and grant root access.
3. Check the logs for successful server login and proxy startup. A running process does not necessarily mean the server connection has succeeded.
4. Open **Settings (设置)** to change the theme, configure boot recovery, or update frpc. The bundled binary is the official Android ARM64 release **0.71.1**; use a compatible frps version.

Configurations and downloaded binaries are stored in the app's private directory. Runtime copies are stored in the root-only directory `/data/adb/frpc-android`. Configurations are excluded from Android cloud backups and device transfers. **Stop the tunnel before uninstalling:** Android does not automatically remove the root-managed files during uninstallation.

## Development and builds

Validated with **Flutter 3.47.8 / Dart 3.13.7**. Requirements include JDK 17, Android SDK 36 for compilation, Build Tools 35, and the Android toolchain. The minimum Android API level is 26; the target API level is 35.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`. Release builds currently use the local debug signing key to support upgrades over the previous development build. Configure your own long-term signing key before distributing a production release.

The project packages prebuilt native libraries and has no C/C++ compilation step. If LLVM is installed, set the `FRPC_LLVM_STRIP` environment variable to the absolute path of `llvm-strip` before building to remove debug symbols and reduce the APK size. Only build copies are processed; Flutter's cached libraries are not modified.

If Flutter selects an incompatible Android Studio JDK on Windows, configure Flutter to use JDK 17, or set `GRADLE_OPTS=-Dorg.gradle.java.home=<JDK17_PATH>` for the build environment. Use a Flutter SDK path without Chinese characters on Windows. When building in a case-sensitive directory, SDK file paths must also match the actual filename casing.

Project layout:

- `lib/`: Flutter UI and application state.
- `android/app/src/main/java/dev/kuugo/frpc/`: Platform channel, profile storage, binary updates, and background services.
- `android/app/src/main/assets/`: Bundled frpc binary and background supervisor scripts.

## GitHub Actions builds

The [Android CI workflow](.github/workflows/android.yml) runs on pushes, pull requests, and manual dispatches. It checks formatting, runs Flutter analysis and tests, exercises the background supervisor and archive parser, builds an ARM64 APK, runs Android Lint, and verifies the APK signature and alignment.

After uploading the project to GitHub, open **Actions → Android CI** and select a run, or use **Run workflow** to start one manually. On success, download the artifact whose name starts with `Frpc-arm64-` from that run's **Artifacts** section. The archive contains the APK and its SHA256 checksum file. Names include the run number and attempt number. Artifacts are retained for 14 days, and check reports are uploaded separately.

The workflow pins Flutter 3.47.8, JDK 17, and the Android build versions, and configures caching and LLVM symbol stripping. It needs no repository secrets and does not publish GitHub Releases. CI builds use a runner-generated debug signing key, which may change between runs and differs from your local key. Configure a stable production signing key before relying on continuous upgrade installation.

## Validation

- Flutter static analysis and UI tests cover selecting profiles without restarting the running tunnel, creating separate profiles, theme and dark mode settings, and preserving the installed binary state after a failed update.
- `tests/KernelArchiveTest.java` covers archive extraction, incorrect architecture, duplicate executables, ignoring unrelated paths, truncated archives, and version input validation.
- `tests/watchdog.sh` covers restarting exited processes, preventing duplicate supervisors, adopting surviving child processes, and manual shutdown.
- Root authorization, actual binary update execution, manufacturer autostart policies, networking with the screen off, and boot recovery still require testing on a physical device.

The frpc binary comes from [fatedier/frp](https://github.com/fatedier/frp) and is licensed under Apache-2.0. See `FRP-LICENSE` in the app assets. Use `tools/fetch-frpc.ps1` to download and verify the pinned bundled version again.
