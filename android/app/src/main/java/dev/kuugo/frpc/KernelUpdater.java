package dev.kuugo.frpc;

import android.content.Context;
import org.json.*;
import javax.net.ssl.HttpsURLConnection;
import java.net.URL;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.*;
import java.util.zip.GZIPInputStream;

final class KernelUpdater {
    static final String BUNDLED = "0.71.1";
    static final ExecutorService NETWORK = Executors.newSingleThreadExecutor();
    private static File directory(Context c) throws IOException {
        File d = new File(c.getFilesDir(), "kernels");
        if (!d.exists() && !d.mkdirs()) throw new IOException("无法创建内核目录");
        return d;
    }
    static String version(Context c) { return c.getSharedPreferences("settings", 0).getString("kernelVersion", BUNDLED); }
    static File installed(Context c) throws Exception {
        String version = version(c);
        if (!version.matches("[0-9]+\\.[0-9]+\\.[0-9]+")) throw new IOException("内核版本记录无效");
        File f = new File(directory(c), "frpc-" + version);
        if (!f.exists()) {
            if (!BUNDLED.equals(version)) throw new IOException("已安装的内核丢失，请重新下载");
            RootController.copyAsset(c, "frpc", f);
        }
        return f;
    }
    private static HttpsURLConnection connection(String url) throws IOException {
        if (!url.startsWith("https://")) throw new IOException("更新仅支持 HTTPS");
        HttpsURLConnection c = (HttpsURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(20000); c.setReadTimeout(30000);
        c.setRequestProperty("User-Agent", "Frpc-Android/2.0");
        c.setRequestProperty("Accept", "application/vnd.github+json");
        int status = c.getResponseCode();
        if (status != 200) { c.disconnect(); throw new IOException("下载请求失败 (HTTP " + status + ")，请检查网络或稍后重试"); }
        return c;
    }
    private static byte[] get(String url, int limit) throws IOException {
        HttpsURLConnection c = connection(url);
        try (InputStream in = c.getInputStream(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            copy(in, out, limit);
            return out.toByteArray();
        } finally { c.disconnect(); }
    }
    static JSONObject check() throws Exception {
        JSONObject r = new JSONObject(new String(get("https://api.github.com/repos/fatedier/frp/releases/latest", 2 * 1024 * 1024), StandardCharsets.UTF_8));
        String v = r.getString("tag_name").replaceFirst("^v", "");
        validateVersion(v);
        JSONArray assets = r.getJSONArray("assets");
        boolean found = false, checksum = false;
        for (int i = 0; i < assets.length(); i++) {
            String name = assets.getJSONObject(i).getString("name");
            if (name.equals("frp_" + v + "_android_arm64.tar.gz")) found = true;
            if (name.equals("frp_sha256_checksums.txt")) checksum = true;
        }
        if (!found || !checksum) throw new IOException("最新版本暂无可校验的 Android ARM64 内核");
        return new JSONObject().put("version", v).put("notes", r.optString("body", ""));
    }
    static void validateVersion(String v) throws IOException {
        if (v == null || !v.matches("[0-9]+\\.[0-9]+\\.[0-9]+")) throw new IOException("不支持的内核版本");
    }
    static String digest(File f) throws Exception {
        MessageDigest d = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(f)) {
            byte[] b = new byte[8192]; int n;
            while ((n = in.read(b)) != -1) d.update(b, 0, n);
        }
        StringBuilder s = new StringBuilder();
        for (byte b : d.digest()) s.append(String.format(Locale.ROOT, "%02x", b & 255));
        return s.toString();
    }
    static void install(Context c, String version) throws Exception {
        validateVersion(version);
        String name = "frp_" + version + "_android_arm64.tar.gz";
        String base = "https://github.com/fatedier/frp/releases/download/v" + version + "/";
        String checks = new String(get(base + "frp_sha256_checksums.txt", 262144), StandardCharsets.UTF_8);
        String expected = "";
        for (String line : checks.split("\\r?\\n")) {
            String[] parts = line.trim().split("\\s+");
            if (parts.length == 2 && parts[1].replaceFirst("^\\*", "").equals(name)) expected = parts[0];
        }
        if (!expected.matches("[a-fA-F0-9]{64}")) throw new IOException("官方 SHA256 清单中没有此内核");
        File archive = new File(directory(c), "download.tar.gz");
        File candidate = new File(directory(c), "candidate.tmp");
        try {
            HttpsURLConnection connection = connection(base + name);
            try (InputStream in = connection.getInputStream(); OutputStream out = new FileOutputStream(archive)) { copy(in, out, 100 * 1024 * 1024); }
            finally { connection.disconnect(); }
            if (!digest(archive).equalsIgnoreCase(expected)) throw new IOException("SHA256 校验失败，已保留原内核");
            extract(archive, candidate);
            // Only switch the installed pointer after extraction and ELF validation.
            File target = new File(directory(c), "frpc-" + version);
            Files.move(candidate.toPath(), target.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            if (!c.getSharedPreferences("settings", 0).edit().putString("kernelVersion", version).commit())
                throw new IOException("无法保存更新信息");
        } finally { archive.delete(); candidate.delete(); }
    }
    private static void copy(InputStream in, OutputStream out, long limit) throws IOException {
        byte[] b = new byte[8192]; int n; long total = 0;
        while ((n = in.read(b)) != -1) {
            total += n;
            if (total > limit) throw new IOException("下载内容超过大小限制");
            out.write(b, 0, n);
        }
    }
    private static void fully(InputStream in, byte[] bytes) throws IOException {
        int offset = 0;
        while (offset < bytes.length) { int n = in.read(bytes, offset, bytes.length - offset); if (n < 0) throw new EOFException("内核归档不完整"); offset += n; }
    }
    static void extract(File archive, File candidate) throws Exception {
        boolean found = false; long unpacked = 0;
        try (InputStream in = new GZIPInputStream(new FileInputStream(archive))) {
            byte[] header = new byte[512];
            while (true) {
                fully(in, header);
                if (header[0] == 0) break;
                String name = new String(header, 0, 100, StandardCharsets.UTF_8).split("\u0000", 2)[0];
                String sizeText = new String(header, 124, 12, StandardCharsets.US_ASCII).replace("\u0000", "").trim();
                long size = Long.parseLong(sizeText, 8);
                if (size < 0 || size > 100 * 1024 * 1024L || (unpacked += size) > 200 * 1024 * 1024L) throw new IOException("内核归档异常");
                boolean wanted = name.matches("frp_[0-9]+\\.[0-9]+\\.[0-9]+_android_arm64/frpc") && (header[156] == 0 || header[156] == '0');
                if (wanted && found) throw new IOException("归档包含重复内核");
                // Do not materialize arbitrary tar paths, directories or symlinks.
                try (OutputStream out = wanted ? new FileOutputStream(candidate) : new OutputStream() { public void write(int b) {} public void write(byte[] b, int o, int n) {} }) {
                    byte[] b = new byte[8192]; long remaining = size;
                    while (remaining > 0) {
                        int n = in.read(b, 0, (int)Math.min(b.length, remaining));
                        if (n < 0) throw new EOFException("内核归档不完整");
                        out.write(b, 0, n); remaining -= n;
                    }
                }
                if (wanted) found = true;
                long padding = (512 - size % 512) % 512;
                while (padding-- > 0) if (in.read() < 0) throw new EOFException("内核归档不完整");
            }
        }
        if (!found) throw new IOException("归档中未找到 Android ARM64 frpc");
        byte[] elf = new byte[20];
        try (InputStream in = new FileInputStream(candidate)) { fully(in, elf); }
        if (elf[0] != 0x7f || elf[1] != 'E' || elf[2] != 'L' || elf[3] != 'F' || elf[4] != 2 || elf[5] != 1 || (elf[18] & 255) != 183 || elf[19] != 0)
            throw new IOException("内核不是有效的 Android ARM64 ELF");
    }
}
