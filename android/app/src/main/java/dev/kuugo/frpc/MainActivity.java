package dev.kuugo.frpc;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private MethodChannel.Result pendingImport;
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "dev.kuugo.frpc/control").setMethodCallHandler(this::handle);
    }
    private String arg(MethodCall call, String key) { String value = call.argument(key); return value == null ? "" : value; }
    private void handle(MethodCall call, MethodChannel.Result result) {
        if ("importConfig".equals(call.method)) {
            if (pendingImport != null) { result.error("BUSY", "已有文件选择正在进行", null); return; }
            pendingImport = result;
            try { startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE), 42); }
            catch (RuntimeException e) { pendingImport = null; result.error("IMPORT", e.getMessage(), null); }
            return;
        }
        if ("openAutostartSettings".equals(call.method) || "openBatterySettings".equals(call.method)) {
            openSettings(call.method.equals("openAutostartSettings"), result); return;
        }
        if ("start".equals(call.method)) {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
            try { startForegroundService(new Intent(this, MonitorService.class).setAction("PREPARE")); }
            catch (RuntimeException e) { result.error("SERVICE", e.getMessage(), null); return; }
        }
        java.util.concurrent.ExecutorService executor = ("checkUpdate".equals(call.method) || "installUpdate".equals(call.method)) ? KernelUpdater.NETWORK : RootController.WORK;
        executor.execute(() -> {
            try {
                Object response;
                switch (call.method) {
                    case "initialize": {
                        new ProfileStore(this);
                        // Also removes the previous app's root boot script on upgrade.
                        if (getSharedPreferences("settings", 0).getBoolean("legacyCleanupPending", false)) {
                            try { RootController.cleanupLegacyBoot(this); }
                            catch (Exception ignored) { /* Surface the pending migration in Flutter. */ }
                        }
                        if (getSharedPreferences("settings", 0).getBoolean("enabled", false)) {
                            try { startForegroundService(new Intent(this, MonitorService.class).setAction("MONITOR")); }
                            catch (RuntimeException ignored) { /* Opening the app remains possible if the OS blocks monitoring. */ }
                        }
                        response = TunnelManager.snapshot(this).toString(); break;
                    }
                    case "snapshot": response = TunnelManager.snapshot(this).toString(); break;
                    case "refresh":
                        TunnelManager.cache(this, RootController.status());
                        response = TunnelManager.snapshot(this).toString(); break;
                    case "saveProfile":
                        new ProfileStore(this).save(arg(call, "id"), arg(call, "name"), arg(call, "content"));
                        response = TunnelManager.snapshot(this).toString(); break;
                    case "selectProfile":
                        new ProfileStore(this).select(arg(call, "id"));
                        response = TunnelManager.snapshot(this).toString(); break;
                    case "deleteProfile":
                        new ProfileStore(this).delete(arg(call, "id"));
                        response = TunnelManager.snapshot(this).toString(); break;
                    case "setSettings": {
                        SharedPreferences.Editor edit = getSharedPreferences("settings", 0).edit();
                        if (call.hasArgument("systemBoot")) edit.putBoolean("systemBoot", Boolean.TRUE.equals(call.argument("systemBoot")));
                        if (call.hasArgument("themeMode")) {
                            String mode = arg(call, "themeMode");
                            if (!Arrays.asList("system", "light", "dark").contains(mode)) throw new IOException("无效的外观设置");
                            edit.putString("themeMode", mode);
                        }
                        if (call.hasArgument("themeColor")) {
                            String color = arg(call, "themeColor");
                            if (!Arrays.asList("teal", "blue", "violet", "orange").contains(color)) throw new IOException("无效的主题色");
                            edit.putString("themeColor", color);
                        }
                        edit.apply(); response = TunnelManager.snapshot(this).toString(); break;
                    }
                    case "start":
                        TunnelManager.start(this, arg(call, "id"));
                        startForegroundService(new Intent(this, MonitorService.class).setAction("MONITOR"));
                        response = TunnelManager.snapshot(this).toString(); break;
                    case "stop":
                        TunnelManager.stop(this); stopService(new Intent(this, MonitorService.class));
                        response = TunnelManager.snapshot(this).toString(); break;
                    case "logs": response = RootController.logs(); break;
                    case "checkUpdate": response = KernelUpdater.check().toString(); break;
                    case "installUpdate":
                        KernelUpdater.install(this, arg(call, "version"));
                        // Snapshot runs on the store's serialized worker.
                        RootController.WORK.execute(() -> {
                            try { String state = TunnelManager.snapshot(this).toString(); runOnUiThread(() -> result.success(state)); }
                            catch (Exception e) { runOnUiThread(() -> result.error("STATE", e.getMessage(), null)); }
                        }); return;
                    case "cleanupLegacy":
                        RootController.cleanupLegacyBoot(this); response = TunnelManager.snapshot(this).toString(); break;
                    default: runOnUiThread(result::notImplemented); return;
                }
                runOnUiThread(() -> result.success(response));
            } catch (Exception e) {
                if ("start".equals(call.method)) {
                    try {
                        if (!getSharedPreferences("settings", 0).getBoolean("enabled", false)) stopService(new Intent(this, MonitorService.class));
                        else startForegroundService(new Intent(this, MonitorService.class).setAction("MONITOR"));
                    } catch (RuntimeException ignored) { }
                }
                runOnUiThread(() -> result.error("FRPC", e.getMessage(), null));
            }
        });
    }
    private void openSettings(boolean autostart, MethodChannel.Result result) {
        // Vendor pages are optional; fall back to Android's app details page.
        String[][] components = {
            {"com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"},
            {"com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
            {"com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"},
            {"com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"}
        };
        if (autostart) for (String[] pair : components) {
            try { startActivity(new Intent().setComponent(new ComponentName(pair[0], pair[1]))); result.success(null); return; }
            catch (RuntimeException ignored) { }
        }
        try {
            Intent i = autostart ? new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName())) : new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
            startActivity(i); result.success(null);
        } catch (RuntimeException e) { result.error("SETTINGS", "请手动在系统设置中找到 Frpc 并允许自启动与后台运行", null); }
    }
    @Override protected void onActivityResult(int request, int resultCode, Intent data) {
        super.onActivityResult(request, resultCode, data);
        if (request != 42 || pendingImport == null) return;
        MethodChannel.Result result = pendingImport; pendingImport = null;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) { result.success(null); return; }
        Uri uri = data.getData();
        RootController.WORK.execute(() -> {
            try (InputStream in = getContentResolver().openInputStream(uri); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                if (in == null) throw new IOException("无法读取配置");
                byte[] b = new byte[4096]; int n;
                while ((n = in.read(b)) != -1) { out.write(b, 0, n); if (out.size() > 262144) throw new IOException("配置文件不能超过 256 KB"); }
                String text = out.toString(StandardCharsets.UTF_8.name());
                runOnUiThread(() -> result.success(text));
            } catch (Exception e) { runOnUiThread(() -> result.error("IMPORT", e.getMessage(), null)); }
        });
    }
    @Override protected void onDestroy() {
        if (pendingImport != null) { pendingImport.error("CANCELLED", "文件选择已取消", null); pendingImport = null; }
        super.onDestroy();
    }
}
