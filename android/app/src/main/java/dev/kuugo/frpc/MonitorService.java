package dev.kuugo.frpc;

import android.app.*;
import android.content.*;
import android.os.*;

public final class MonitorService extends Service {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean working;
    private boolean destroyed;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (!working && !destroyed) {
                working = true;
                RootController.WORK.execute(() -> {
                    String text;
                    try {
                        text = RootController.status();
                        if (text.contains("异常：")) {
                            RootController.run("[ ! -f " + RootController.DIR + "/enabled ] || nohup /system/bin/sh "
                                + RootController.DIR + "/supervisor.sh </dev/null >/dev/null 2>&1 &\n");
                            text = "正在恢复 root 守护进程";
                        }
                        TunnelManager.cache(MonitorService.this, text);
                    } catch (Exception e) {
                        text = "无法读取状态：" + e.getMessage();
                        getSharedPreferences("settings", 0).edit().putString("phase", "error").putString("status", text).apply();
                    }
                    final String result = text;
                    handler.post(() -> {
                        working = false;
                        if (!destroyed) {
                            getSystemService(NotificationManager.class).notify(1, notification(result));
                            handler.postDelayed(this, 15000);
                        }
                    });
                });
            }
        }
    };
    @Override public void onCreate() {
        super.onCreate();
        NotificationChannel channel = new NotificationChannel("tunnel", "隧道运行状态", NotificationManager.IMPORTANCE_LOW);
        channel.setShowBadge(false);
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
        startForeground(1, notification("正在读取隧道状态"));
    }
    private Notification notification(String text) {
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent stop = PendingIntent.getService(this, 1, new Intent(this, MonitorService.class).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this, "tunnel").setSmallIcon(dev.kuugo.frpc.R.drawable.ic_notification)
            .setContentTitle("Frpc").setContentText(text.split("\n")[0]).setStyle(new Notification.BigTextStyle().bigText(text))
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(new Notification.Action.Builder(null, "停止隧道", stop).build()).build();
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "STOP".equals(intent.getAction())) {
            RootController.WORK.execute(() -> {
                try {
                    TunnelManager.stop(this);
                    handler.post(() -> { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); });
                } catch (Exception e) {
                    handler.post(() -> getSystemService(NotificationManager.class).notify(1, notification("停止失败：" + e.getMessage())));
                }
            });
        } else if (intent != null && "PREPARE".equals(intent.getAction())) {
            // User initiated operation: show the foreground notification before root authorization.
            return START_NOT_STICKY;
        } else if (intent != null && "RESTORE".equals(intent.getAction())) {
            RootController.WORK.execute(() -> {
                try {
                    android.content.SharedPreferences p = getSharedPreferences("settings", 0);
                    if (!p.getBoolean("enabled", false) || !p.getBoolean("systemBoot", false)) {
                        handler.post(this::stopSelf); return;
                    }
                    new ProfileStore(this);
                    TunnelManager.restore(this);
                    handler.post(tick);
                } catch (Exception e) {
                    getSharedPreferences("settings", 0).edit().putString("phase", "error").putString("status", "开机恢复失败：" + e.getMessage()).apply();
                    handler.post(() -> getSystemService(NotificationManager.class).notify(1, notification("开机恢复失败，请打开 Frpc 检查授权与配置")));
                }
            });
        } else if (!getSharedPreferences("settings", 0).getBoolean("enabled", false)) {
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
            return START_NOT_STICKY;
        } else {
            handler.removeCallbacks(tick);
            handler.post(tick);
        }
        return START_STICKY;
    }
    @Override public void onDestroy() {
        destroyed = true;
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent i) { return null; }
}
