package dev.kuugo.frpc;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.AtomicFile;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

final class ProfileStore {
    private final AtomicFile file;
    private final SharedPreferences settings;
    private JSONArray profiles;
    ProfileStore(Context c) throws Exception {
        settings = c.getSharedPreferences("settings", 0);
        if (settings.contains("boot")) settings.edit().putBoolean("legacyCleanupPending", true).apply();
        file = new AtomicFile(new File(c.getFilesDir(), "profiles.json"));
        if (file.getBaseFile().exists() || new File(file.getBaseFile().getPath() + ".bak").exists()) {
            profiles = new JSONArray(new String(file.readFully(), StandardCharsets.UTF_8));
        } else {
            profiles = new JSONArray();
            String id = UUID.randomUUID().toString();
            profiles.put(new JSONObject().put("id", id).put("name", "默认配置").put("content", RootController.readConfig(c)));
            write(profiles);
            SharedPreferences.Editor edit = settings.edit().putString("selectedId", id);
            if (settings.getBoolean("enabled", false)) edit.putString("runningId", id);
            if (settings.contains("boot")) edit.putBoolean("legacyCleanupPending", true);
            edit.apply();
        }
        if (settings.getBoolean("enabled", false) && !settings.contains("runningId"))
            settings.edit().putString("runningId", profiles.getJSONObject(0).getString("id")).apply();
        if (settings.getBoolean("enabled", false)) TunnelManager.ensureLegacySnapshot(c);
    }
    private void write(JSONArray value) throws IOException {
        FileOutputStream out = null;
        try {
            out = file.startWrite();
            out.write(value.toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(out);
        } catch (IOException e) { if (out != null) file.failWrite(out); throw e; }
    }
    JSONObject find(String id) throws Exception {
        for (int i = 0; i < profiles.length(); i++) {
            JSONObject p = profiles.getJSONObject(i);
            if (p.getString("id").equals(id)) return p;
        }
        throw new IOException("配置不存在，请重新选择");
    }
    String selectedId() throws Exception {
        String id = settings.getString("selectedId", "");
        try { return find(id).getString("id"); }
        catch (IOException e) { return profiles.getJSONObject(0).getString("id"); }
    }
    JSONArray list() throws Exception { return new JSONArray(profiles.toString()); }
    String save(String id, String name, String content) throws Exception {
        name = name.trim();
        if (name.isEmpty() || name.length() > 60) throw new IOException("配置名称需要 1–60 个字符");
        if (content.trim().isEmpty() || content.getBytes(StandardCharsets.UTF_8).length > 262144)
            throw new IOException("配置不能为空，且不能超过 256 KB");
        if (id == null || id.isEmpty()) id = UUID.randomUUID().toString(); else find(id);
        JSONArray next = new JSONArray(profiles.toString());
        JSONObject profile = new JSONObject().put("id", id).put("name", name).put("content", content);
        boolean replaced = false;
        for (int i = 0; i < next.length(); i++) {
            if (next.getJSONObject(i).getString("id").equals(id)) { next.put(i, profile); replaced = true; break; }
        }
        if (!replaced) next.put(profile);
        write(next); profiles = next;
        return id;
    }
    void select(String id) throws Exception { find(id); settings.edit().putString("selectedId", id).apply(); }
    void delete(String id) throws Exception {
        find(id);
        if (profiles.length() == 1) throw new IOException("请至少保留一个配置");
        if (settings.getBoolean("enabled", false) && id.equals(settings.getString("runningId", "")))
            throw new IOException("请先停止隧道，再删除正在运行的配置");
        JSONArray next = new JSONArray();
        for (int i = 0; i < profiles.length(); i++) {
            JSONObject p = profiles.getJSONObject(i);
            if (!id.equals(p.getString("id"))) next.put(p);
        }
        write(next); profiles = next;
        if (id.equals(settings.getString("selectedId", ""))) select(next.getJSONObject(0).getString("id"));
    }
}
