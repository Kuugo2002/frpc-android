package dev.kuugo.frpc;

import android.content.*;

public final class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) return;
        android.content.SharedPreferences p = context.getSharedPreferences("settings", 0);
        if (Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            PendingResult result = goAsync();
            RootController.WORK.execute(() -> {
                try { new ProfileStore(context); RootController.cleanupLegacyBoot(context, 5); }
                catch (Exception ignored) { /* The app displays pending cleanup on next open. */ }
                finally { result.finish(); }
            });
        }
        if (p.getBoolean("enabled", false) && p.getBoolean("systemBoot", false)) {
            try { context.startForegroundService(new Intent(context, MonitorService.class).setAction("RESTORE")); }
            catch (RuntimeException e) { p.edit().putString("phase", "error").putString("status", "系统阻止了自启动，请在自启动管理中允许 Frpc").apply(); }
        }
    }
}
