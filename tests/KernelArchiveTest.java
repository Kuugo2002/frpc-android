package dev.kuugo.frpc;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.GZIPOutputStream;

public final class KernelArchiveTest {
    private static File archive(Path dir, String[] names, byte[][] contents) throws Exception {
        File archive = dir.resolve(UUID.randomUUID() + ".tar.gz").toFile();
        try (OutputStream out = new GZIPOutputStream(new FileOutputStream(archive))) {
            for (int i = 0; i < names.length; i++) {
                byte[] h = new byte[512];
                byte[] name = names[i].getBytes(StandardCharsets.UTF_8);
                System.arraycopy(name, 0, h, 0, name.length);
                byte[] size = String.format("%011o", contents[i].length).getBytes(StandardCharsets.US_ASCII);
                System.arraycopy(size, 0, h, 124, size.length);
                h[156] = '0'; out.write(h); out.write(contents[i]);
                out.write(new byte[(512 - contents[i].length % 512) % 512]);
            }
            out.write(new byte[1024]);
        }
        return archive;
    }
    interface Checked { void run() throws Exception; }
    private static void rejects(String name, Checked job) throws Exception {
        try { job.run(); } catch (Exception expected) { System.out.println("PASS: " + name); return; }
        throw new AssertionError("Did not reject " + name);
    }
    public static void main(String[] args) throws Exception {
        Path dir = Files.createTempDirectory("frpc-archive-test");
        try {
            byte[] elf = new byte[64];
            elf[0] = 0x7f; elf[1] = 'E'; elf[2] = 'L'; elf[3] = 'F'; elf[4] = 2; elf[5] = 1; elf[18] = (byte)183;
            String entry = "frp_0.71.1_android_arm64/frpc";
            File candidate = dir.resolve("candidate").toFile();
            File valid = archive(dir, new String[]{entry}, new byte[][]{elf});
            KernelUpdater.extract(valid, candidate);
            if (!Arrays.equals(elf, Files.readAllBytes(candidate.toPath()))) throw new AssertionError("extraction mismatch");
            System.out.println("PASS: valid ARM64 archive extracts exactly");
            File duplicate = archive(dir, new String[]{entry, entry}, new byte[][]{elf, elf});
            rejects("duplicate executable", () -> KernelUpdater.extract(duplicate, candidate));
            File wrongElf = archive(dir, new String[]{entry}, new byte[][]{new byte[64]});
            rejects("wrong executable architecture", () -> KernelUpdater.extract(wrongElf, candidate));
            File traversal = archive(dir, new String[]{"../../escaped", entry}, new byte[][]{elf, elf});
            KernelUpdater.extract(traversal, candidate);
            if (Files.exists(dir.getParent().resolve("escaped"))) throw new AssertionError("tar traversal");
            System.out.println("PASS: arbitrary tar paths are not materialized");
            File truncated = dir.resolve("truncated.gz").toFile();
            Files.write(truncated.toPath(), Arrays.copyOf(Files.readAllBytes(valid.toPath()), 20));
            rejects("truncated archive", () -> KernelUpdater.extract(truncated, candidate));
            rejects("non-version input", () -> KernelUpdater.validateVersion("../../other"));
            rejects("shell-shaped version input", () -> KernelUpdater.validateVersion("0.71.1;id"));
            if (args.length > 0) {
                KernelUpdater.extract(new File(args[0]), candidate);
                if (!KernelUpdater.digest(candidate).equals("ed49662d0fb8a5ac0a6f532fa4eed599fdb93c7691cbd02e327c7be81f7bcb6f"))
                    throw new AssertionError("official binary mismatch");
                System.out.println("PASS: official frpc archive matches bundled kernel");
            }
        } finally {
            try (java.util.stream.Stream<Path> stream = Files.walk(dir)) {
                stream.sorted(Comparator.reverseOrder()).forEach(p -> { try { Files.delete(p); } catch (IOException e) { throw new UncheckedIOException(e); } });
            }
        }
    }
}
