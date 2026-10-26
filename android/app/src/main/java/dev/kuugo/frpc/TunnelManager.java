package dev.kuugo.frpc;

import android.content.*;
import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import org.json.*;

final class TunnelManager {
    private static AtomicFile activeFile(Context c) { return new AtomicFile(new File(c.getFilesDir(), "last-running.toml")); }
    static void ensureLegacySnapshot(Context c) throws Exception {
        AtomicFile file = activeFile(c);
        if (file.getBaseFile().exists() || new File(file.getBaseFile().getPath() + ".bak").exists()) return;
        FileOutputStream out = file.startWrite();
        try { out.write(RootController.readConfig(c).getBytes(StandardCharsets.UTF_8)); file.finishWrite(out); }
        catch (Exception e) { file.failWrite(out); throw e; }
    }
    static void start(Context c, String id) throws Exception {
        JSONObject p = new ProfileStore(c).find(id);
        startContent(c, id, p.getString("content"));
    }
    static void restore(Context c) throws Exception {
        String id = c.getSharedPreferences("settings", 0).getString("runningId", "");
        new ProfileStore(c).find(id);
        ensureLegacySnapshot(c);
        String content = new String(activeFile(c).readFully(), StandardCharsets.UTF_8);
        startContent(c, id, content);
    }
    private static void startContent(Context c, String id, String content) throws Exception {
        AtomicFile file = activeFile(c);
        FileOutputStream out = file.startWrite();
        String status;
        try {
            out.write(content.getBytes(StandardCharsets.UTF_8));
            status = RootController.start(c, content);
            file.finishWrite(out);
        } catch (Exception e) { file.failWrite(out); throw e; }
        c.getSharedPreferences("settings", 0).edit().putBoolean("enabled", true)
            .putString("runningId", id).putString("runningVersion", RootController.stagedVersion).apply();
        cache(c, status);
    }
    static void stop(Context c) throws Exception {
        RootController.stop();
        c.getSharedPreferences("settings", 0).edit().putBoolean("enabled", false).apply();
        cache(c, "已停止");
    }
    static void cache(Context c, String status) {
        String phase = status.contains("异常：") ? "error" : status.contains("进程运行中") ? "running" : (status.contains("等待 frpc") || status.contains("正在恢复")) ? "retrying" : "stopped";
        c.getSharedPreferences("settings", 0).edit().putString("phase", phase).putString("status", status.split("\n")[0]).apply();
    }
    static JSONObject snapshot(Context c) throws Exception {
        ProfileStore store = new ProfileStore(c);
        SharedPreferences p = c.getSharedPreferences("settings", 0);
        return new JSONObject().put("profiles", store.list()).put("selectedId", store.selectedId())
            .put("runningId", p.getString("runningId", "")).put("enabled", p.getBoolean("enabled", false))
            .put("phase", p.getString("phase", "stopped")).put("status", p.getString("status", "尚未启动"))
            .put("themeMode", p.getString("themeMode", "system")).put("themeColor", p.getString("themeColor", "teal"))
            .put("systemBoot", p.getBoolean("systemBoot", false)).put("legacyCleanupPending", p.getBoolean("legacyCleanupPending", false))
            .put("kernelVersion", KernelUpdater.version(c)).put("runningVersion", p.getString("runningVersion", ""));
    }
}
