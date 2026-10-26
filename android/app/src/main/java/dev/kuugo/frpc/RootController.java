package dev.kuugo.frpc;

import android.content.Context;
import android.os.Build;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.*;

final class RootController {
    static final ExecutorService WORK = Executors.newSingleThreadExecutor();
    static final String DIR = "/data/adb/frpc-android";
    private static final String LEGACY_BOOT = "/data/adb/service.d/90-frpc-android.sh";
    static volatile boolean authorized;
    static String stagedVersion = KernelUpdater.BUNDLED;
    static final String STOP = "rm -f " + DIR + "/enabled\n"
        + "if [ -f " + DIR + "/functions.sh ]; then\n. " + DIR + "/functions.sh\n"
        + "p=$(cat /dev/frpc-android.lock/pid 2>/dev/null)\n"
        + "if supervisor_alive \"$p\"; then kill \"$p\"; fi\n"
        + "i=0; while supervisor_alive \"$p\" && [ \"$i\" -lt 6 ]; do sleep 1; i=$((i+1)); done\n"
        + "if supervisor_alive \"$p\"; then echo '守护进程尚未退出，请稍后重试' >&2; exit 1; fi\n"
        + "c=$(cat " + DIR + "/child.pid 2>/dev/null)\n"
        + "if child_alive \"$c\"; then kill \"$c\"; sleep 1; if child_alive \"$c\"; then kill -9 \"$c\"; fi; fi\nfi\n";

    static String quote(String s) { return "'" + s.replace("'", "'\\''") + "'"; }

    static String run(String script) throws Exception {
        return run(script, 45);
    }
    static String run(String script, int timeoutSeconds) throws Exception {
        Process p = new ProcessBuilder("su", "-c", script).redirectErrorStream(true).start();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        Thread reader = new Thread(() -> {
            try (InputStream in = p.getInputStream()) {
                byte[] b = new byte[4096]; int n;
                while ((n = in.read(b)) != -1) {
                    if (output.size() < 262144) output.write(b, 0, n);
                }
            } catch (IOException ignored) { }
        }, "root-output");
        reader.start();
        if (!p.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
            p.destroyForcibly(); reader.join(1000);
            throw new IOException("Root 操作超时，请检查授权后重试");
        }
        reader.join(2000);
        String result = output.toString(StandardCharsets.UTF_8.name()).trim();
        if (p.exitValue() != 0) throw new IOException(result.isEmpty() ? "Root 操作失败，请在管理器中允许授权" : result);
        authorized = true;
        return result;
    }

    static File config(Context c) { return new File(c.getFilesDir(), "frpc.toml"); }
    static String readConfig(Context c) throws IOException {
        File f = config(c);
        if (!f.exists()) copyAsset(c, "default.toml", f);
        return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
    }
    static void save(Context c, String text) throws IOException {
        if (text.trim().isEmpty()) throw new IOException("配置不能为空");
        File temp = new File(c.getFilesDir(), "config.tmp");
        Files.write(temp.toPath(), text.getBytes(StandardCharsets.UTF_8));
        if (!temp.renameTo(config(c))) throw new IOException("保存配置失败");
    }
    static void copyAsset(Context c, String name, File target) throws IOException {
        try (InputStream in = c.getAssets().open(name); OutputStream out = new FileOutputStream(target)) {
            byte[] b = new byte[8192]; int n;
            while ((n = in.read(b)) != -1) out.write(b, 0, n);
        }
    }
    static void cleanupLegacyBoot(Context c) throws Exception {
        cleanupLegacyBoot(c, 45);
    }
    static void cleanupLegacyBoot(Context c, int timeoutSeconds) throws Exception {
        android.content.SharedPreferences prefs = c.getSharedPreferences("settings", 0);
        if (!prefs.getBoolean("legacyCleanupPending", false)) return;
        run("rm -f " + LEGACY_BOOT + " " + DIR + "/boot.sh\n", timeoutSeconds);
        prefs.edit().remove("boot").putBoolean("legacyCleanupPending", false).apply();
    }
    static void stage(Context c, String content) throws Exception {
        if (!java.util.Arrays.asList(Build.SUPPORTED_ABIS).contains("arm64-v8a"))
            throw new IOException("此版本内置 ARM64 frpc，需要支持 arm64-v8a 的手机");
        cleanupLegacyBoot(c);
        save(c, content);
        File kernel = KernelUpdater.installed(c);
        stagedVersion = kernel.getName().substring("frpc-".length());
        for (String name : new String[]{"supervisor.sh", "functions.sh"})
            copyAsset(c, name, new File(c.getFilesDir(), name));
        StringBuilder s = new StringBuilder("set -e\numask 077\nmkdir -p " + DIR + "\nchmod 700 " + DIR + "\n");
        // Avoid replacing a running executable; prepare the candidate beside it.
        for (String name : new String[]{"supervisor.sh", "functions.sh"}) {
            s.append("cp ").append(quote(new File(c.getFilesDir(), name).getAbsolutePath()))
                .append(' ').append(DIR).append('/').append(name).append(".new\n");
        }
        s.append("cp ").append(quote(kernel.getAbsolutePath())).append(' ').append(DIR).append("/frpc.new\n");
        s.append("cp ").append(quote(config(c).getAbsolutePath())).append(' ').append(DIR).append("/config.new.toml\n")
            .append("chmod 700 ").append(DIR).append("/frpc.new\n")
            .append(DIR).append("/frpc.new verify -c ").append(DIR).append("/config.new.toml\n");
        run(s.toString());
    }
    static String start(Context c, String content) throws Exception {
        stage(c, content); // Validate before stopping the existing tunnel.
        run("set -e\n" + STOP
            + "cd " + DIR + "\n"
            + "for f in frpc supervisor.sh functions.sh; do mv \"$f.new\" \"$f\"; done\n"
            + "mv config.new.toml frpc.toml\nchmod 700 frpc *.sh\nchmod 600 frpc.toml\n"
            + "touch enabled\nnohup /system/bin/sh " + DIR + "/supervisor.sh </dev/null >/dev/null 2>&1 &\n");
        Thread.sleep(800);
        try { return status(); }
        catch (Exception e) { return "异常：隧道已提交启动，但状态读取失败：" + e.getMessage(); }
    }
    static void stop() throws Exception { run(STOP + "echo '已停止隧道和自动拉起'\n"); }
    static String status() throws Exception {
        return run("if [ ! -f " + DIR + "/functions.sh ]; then echo '尚未启动'; exit 0; fi\n"
            + ". " + DIR + "/functions.sh\n"
            + "p=$(cat /dev/frpc-android.lock/pid 2>/dev/null)\n"
            + "c=$(cat " + DIR + "/child.pid 2>/dev/null)\n"
            + "if [ -f " + DIR + "/enabled ] && ! supervisor_alive \"$p\"; then echo '异常：守护进程已退出，请重新启动'; "
            + "elif child_alive \"$c\"; then echo \"frpc 进程运行中 · PID $c\"; "
            + "elif supervisor_alive \"$p\"; then echo '守护中 · 等待 frpc 重启'; "
            + "elif [ -f " + DIR + "/enabled ]; then echo '异常：守护进程已退出，请重新启动'; else echo '已停止'; fi\n"
            + "echo 'Root 仅用于后台进程守护'");
    }
    static String logs() throws Exception { return run("tail -n 120 " + DIR + "/frpc.log 2>/dev/null || true"); }
}
