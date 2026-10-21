/* SPDX-License-Identifier: GPL-2.0-or-later */
package org.sotc.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.chaquo.python.PyException;
import com.chaquo.python.Python;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Imports the user's extracted game and starts the native Android runtime. */
public final class MainActivity extends Activity {
    private static final int PICK_GAME = 1;
    private static final int PICK_MODULES = 2;
    private static final String GAME_ID = "CUSA08809";
    private static final String[] MODULES = {"libSceNgs2.sprx", "libSceUlt.sprx"};
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextView gameStatus;
    private TextView moduleStatus;
    private TextView activityStatus;
    private Button importGameButton;
    private Button importModulesButton;
    private Button launchGameButton;
    private Button runtimeLogButton;
    private File dataRoot;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        File external = getExternalFilesDir("SotC");
        dataRoot = external != null ? external : new File(getFilesDir(), "SotC");
        setContentView(createScreen());
        refreshStatus();
    }

    @Override
    protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (runtimeLogButton != null) refreshStatus();
    }

    private View createScreen() {
        int pad = dp(22);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(pad, dp(28), pad, pad);
        content.setBackground(getDrawable(R.drawable.launcher_bg));

        TextView title = new TextView(this);
        title.setText("Shadow of the Colossus");
        title.setTextSize(25);
        title.setTextColor(0xfff3eee2);
        title.setGravity(Gravity.CENTER_VERTICAL);
        content.addView(title, matchWrap());

        TextView subtitle = text("Android port launcher", 15, 0xffb8b9bb);
        subtitle.setPadding(0, dp(5), 0, dp(22));
        content.addView(subtitle, matchWrap());

        content.addView(section("Game files"), matchWrap());
        content.addView(text("Extract your own PS4 PKG with a PS4 PKG Extractor app first, then select the resulting CUSA08809 EU 1.01 folder here. This launcher imports the extracted folder; game data is not part of the APK.", 14, 0xffc6c7c9), matchWrap());
        gameStatus = text("Game: checking", 14, 0xffe6d8b5);
        gameStatus.setPadding(0, dp(12), 0, dp(10));
        content.addView(gameStatus, matchWrap());
        importGameButton = button("Import game folder");
        content.addView(importGameButton, matchWrap());
        importGameButton.setOnClickListener(view -> chooseGameFolder());

        content.addView(section("Sound modules (optional)"), params(0, dp(24), 0, 0));
        content.addView(text("Choose both decrypted modules from your own console. Without them, the port currently has no sound modules.", 14, 0xffc6c7c9), matchWrap());
        moduleStatus = text("Sound modules: not imported", 14, 0xffe6d8b5);
        moduleStatus.setPadding(0, dp(12), 0, dp(10));
        content.addView(moduleStatus, matchWrap());
        importModulesButton = button("Import sound modules");
        content.addView(importModulesButton, matchWrap());
        importModulesButton.setOnClickListener(view -> chooseSoundModules());

        content.addView(section("Runtime"), params(0, dp(24), 0, 0));
        content.addView(text("The launcher prepares the imported game image, then starts the ARM64 runtime.", 14, 0xffc6c7c9), matchWrap());
        launchGameButton = button("Prepare and launch game");
        launchGameButton.setEnabled(false);
        content.addView(launchGameButton, matchWrap());
        launchGameButton.setOnClickListener(view -> prepareAndLaunch());
        activityStatus = text("Ready", 13, 0xff9fa3a8);
        activityStatus.setPadding(0, dp(18), 0, 0);
        content.addView(activityStatus, matchWrap());
        runtimeLogButton = button("View runtime log");
        content.addView(runtimeLogButton, matchWrap());
        runtimeLogButton.setEnabled(false);
        runtimeLogButton.setOnClickListener(view -> showRuntimeLog());

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(content);
        return scroll;
    }

    private void chooseGameFolder() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(intent, PICK_GAME);
    }

    private void chooseSoundModules() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(intent, PICK_MODULES);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent result) {
        super.onActivityResult(requestCode, resultCode, result);
        if (resultCode != RESULT_OK || result == null) return;
        if (requestCode == PICK_GAME && result.getData() != null) {
            Uri tree = result.getData();
            persistReadPermission(tree, result.getFlags());
            beginImport("Importing game files…");
            worker.execute(() -> importGame(tree));
        } else if (requestCode == PICK_MODULES) {
            List<Uri> uris = new ArrayList<>();
            if (result.getClipData() != null) {
                for (int i = 0; i < result.getClipData().getItemCount(); i++) {
                    uris.add(result.getClipData().getItemAt(i).getUri());
                }
            } else if (result.getData() != null) {
                uris.add(result.getData());
            }
            for (Uri uri : uris) persistReadPermission(uri, result.getFlags());
            beginImport("Importing sound modules…");
            worker.execute(() -> importModules(uris));
        }
    }

    private void importGame(Uri tree) {
        File staging = new File(dataRoot, "game.importing");
        File destination = new File(dataRoot, "game");
        File previous = new File(dataRoot, "game.previous");
        try {
            File parent = staging.getParentFile();
            if (!parent.isDirectory() && !parent.mkdirs()) throw new Exception("Cannot create app data folder");
            deleteTree(staging);
            String rootId = DocumentsContract.getTreeDocumentId(tree);
            MapChildren rootChildren = children(tree, rootId);
            if (!rootChildren.names.contains("eboot.bin") || !rootChildren.names.contains("sce_sys")
                    || !rootChildren.names.contains("sce_module")) {
                throw new Exception("Select the extracted game folder; it must contain eboot.bin, sce_sys, and sce_module");
            }
            requireReadableFile(tree, rootChildren, "eboot.bin");
            String sysId = rootChildren.idsByName.get("sce_sys");
            MapChildren sysChildren = children(tree, sysId);
            String sfoId = sysChildren.idsByName.get("param.sfo");
            if (sfoId == null) throw new Exception("sce_sys/param.sfo is missing");
            Uri sfo = DocumentsContract.buildDocumentUriUsingTree(tree, sfoId);
            byte[] sfoBytes;
            try (InputStream in = getContentResolver().openInputStream(sfo)) {
                if (in == null) throw new Exception("Cannot read param.sfo");
                sfoBytes = readAll(in, 1024 * 1024);
            }
            String moduleId = rootChildren.idsByName.get("sce_module");
            MapChildren moduleChildren = children(tree, moduleId);
            requireReadableFile(tree, moduleChildren, "libc.prx");
            requireReadableFile(tree, moduleChildren, "libSceFios2.prx");
            Sfo info = parseSfo(sfoBytes);
            if (!GAME_ID.equals(info.values.get("TITLE_ID"))) {
                throw new Exception("Wrong game: expected CUSA08809, found " + info.values.getOrDefault("TITLE_ID", "unknown"));
            }
            String version = info.values.getOrDefault("APP_VER", "unknown");
            if (!("01.01".equals(version) || "1.01".equals(version))) {
                throw new Exception("Expected EU game version 01.01; param.sfo reports " + version);
            }
            long[] fileCount = {0};
            Uri root = DocumentsContract.buildDocumentUriUsingTree(tree, rootId);
            copyDirectory(tree, root, staging, 0, new HashSet<>(), fileCount);
            File stagedEboot = new File(staging, "eboot.bin");
            if (!stagedEboot.isFile() || stagedEboot.length() == 0) throw new Exception("Imported eboot.bin is missing or empty");
            File prior = new File(dataRoot, "game.previous");
            deleteTree(prior);
            if (destination.exists() && !destination.renameTo(prior)) throw new Exception("Cannot replace the previous game import");
            if (!staging.renameTo(destination)) {
                if (prior.exists()) prior.renameTo(destination);
                throw new Exception("Cannot finalize game import");
            }
            deleteTree(prior);
            finishImport("Imported " + GAME_ID + " EU " + version + " (" + fileCount[0] + " files).");
        } catch (Exception error) {
            deleteTree(staging);
            finishImport("Game import failed: " + message(error));
        }
    }

    private void prepareAndLaunch() {
        File game = new File(dataRoot, "game");
        if (!new File(game, "eboot.bin").isFile()) {
            activityStatus.setText("Import the extracted CUSA08809 game folder first.");
            return;
        }
        beginImport("Preparing game image…");
        worker.execute(() -> {
            File runtime = new File(dataRoot, "runtime");
            try {
                if (!runtime.isDirectory() && !runtime.mkdirs()) throw new Exception("Cannot create runtime folder");
                if (!Python.isStarted()) Python.start(new com.chaquo.python.android.AndroidPlatform(getApplicationContext()));
                String result = Python.getInstance().getModule("android_prepare").callAttr("prepare_game",
                        game.getAbsolutePath(), new File(dataRoot, "sys_modules").getAbsolutePath(),
                        runtime.getAbsolutePath()).toString();
                main.post(() -> {
                    importGameButton.setEnabled(true);
                    importModulesButton.setEnabled(true);
                    launchGameButton.setEnabled(true);
                    activityStatus.setText(result);
                    Intent intent = new Intent(this, GameActivity.class);
                    intent.putExtra(GameActivity.EXTRA_GAME_DIR, game.getAbsolutePath());
                    intent.putExtra(GameActivity.EXTRA_RUNTIME_DIR, runtime.getAbsolutePath());
                    intent.putExtra(GameActivity.EXTRA_USER_DIR, new File(dataRoot, "user").getAbsolutePath());
                    startActivity(intent);
                });
            } catch (Exception error) {
                String detail = error instanceof PyException ? error.getMessage() : message(error);
                finishImport("Game preparation failed: " + detail);
            }
        });
    }

    private void importModules(List<Uri> uris) {
        if (uris.isEmpty()) {
            finishImport("No sound-module files were selected.");
            return;
        }
        File target = new File(dataRoot, "sys_modules");
        File staging = new File(dataRoot, "sys_modules.importing");
        File previous = new File(dataRoot, "sys_modules.previous");
        try {
            if (!dataRoot.isDirectory() && !dataRoot.mkdirs()) throw new Exception("Cannot create app data folder");
            deleteTree(staging);
            if (!staging.mkdirs()) throw new Exception("Cannot create module staging folder");
            Set<String> copied = new HashSet<>();
            for (Uri uri : uris) {
                String name = displayName(uri);
                String canonical = null;
                for (String expected : MODULES) if (expected.equalsIgnoreCase(name)) canonical = expected;
                if (canonical == null) continue;
                File output = new File(staging, canonical);
                try (InputStream in = getContentResolver().openInputStream(uri);
                     FileOutputStream out = new FileOutputStream(output)) {
                    if (in == null) throw new Exception("Cannot read " + canonical);
                    copy(in, out);
                }
                if (output.length() == 0) throw new Exception(canonical + " is empty");
                copied.add(canonical);
            }
            if (copied.isEmpty()) throw new Exception("Select libSceNgs2.sprx and/or libSceUlt.sprx");
            if (target.exists()) {
                for (String name : MODULES) {
                    File current = new File(target, name);
                    if (!copied.contains(name) && current.isFile()) copyFile(current, new File(staging, name));
                }
            }
            deleteTree(previous);
            if (target.exists() && !target.renameTo(previous)) throw new Exception("Cannot preserve current sound modules");
            if (!staging.renameTo(target)) {
                if (previous.exists()) previous.renameTo(target);
                throw new Exception("Cannot finalize module import");
            }
            deleteTree(previous);
            finishImport("Imported " + copied.size() + " sound module(s).");
        } catch (Exception error) {
            deleteTree(staging);
            finishImport("Sound-module import failed: " + message(error));
        }
    }

    private void copyDirectory(Uri tree, Uri source, File destination, int depth, Set<String> visited,
                               long[] fileCount) throws Exception {
        if (depth > 80) throw new Exception("Game folder nesting is too deep");
        String documentId = DocumentsContract.getDocumentId(source);
        if (!visited.add(documentId)) throw new Exception("Storage provider returned a directory cycle");
        if (!destination.isDirectory() && !destination.mkdirs()) throw new Exception("Cannot create " + destination.getName());
        Uri childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId);
        String[] columns = {DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE};
        try (Cursor cursor = getContentResolver().query(childrenUri, columns, null, null, null)) {
            if (cursor == null) throw new Exception("Storage provider did not list the selected folder");
            while (cursor.moveToNext()) {
                String childId = cursor.getString(0);
                String name = safeName(cursor.getString(1));
                String mime = cursor.getString(2);
                Uri child = DocumentsContract.buildDocumentUriUsingTree(tree, childId);
                File output = new File(destination, name);
                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) {
                    copyDirectory(tree, child, output, depth + 1, visited, fileCount);
                } else {
                    try (InputStream in = getContentResolver().openInputStream(child);
                         FileOutputStream out = new FileOutputStream(output)) {
                        if (in == null) throw new Exception("Cannot read game file " + name);
                        copy(in, out);
                    }
                    fileCount[0]++;
                    if (fileCount[0] % 32 == 0) {
                        long count = fileCount[0];
                        main.post(() -> activityStatus.setText("Importing game files… " + count + " files"));
                    }
                }
            }
        }
    }

    private MapChildren children(Uri tree, String parentId) throws Exception {
        Uri uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId);
        String[] columns = {DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME};
        MapChildren result = new MapChildren();
        try (Cursor cursor = getContentResolver().query(uri, columns, null, null, null)) {
            if (cursor == null) throw new Exception("Cannot inspect selected game folder");
            while (cursor.moveToNext()) {
                String name = cursor.getString(1);
                result.names.add(name.toLowerCase(java.util.Locale.ROOT));
                result.idsByName.put(name.toLowerCase(java.util.Locale.ROOT), cursor.getString(0));
            }
        }
        return result;
    }

    private void requireReadableFile(Uri tree, MapChildren directory, String name) throws Exception {
        String id = directory.idsByName.get(name.toLowerCase(java.util.Locale.ROOT));
        if (id == null) throw new Exception("Required game file is missing: " + name);
        Uri file = DocumentsContract.buildDocumentUriUsingTree(tree, id);
        try (InputStream in = getContentResolver().openInputStream(file)) {
            if (in == null || in.read() < 0) throw new Exception("Required game file is empty or unreadable: " + name);
        } catch (java.io.IOException error) {
            throw new Exception("Cannot read required game file " + name + ": " + error.getMessage(), error);
        }
    }

    private void refreshStatus() {
        File game = new File(dataRoot, "game");
        gameStatus.setText(game.isDirectory() && new File(game, "eboot.bin").isFile()
                ? "Game: imported (CUSA08809 EU 01.01)" : "Game: not imported");
        launchGameButton.setEnabled(game.isDirectory() && new File(game, "eboot.bin").isFile());
        runtimeLogButton.setEnabled(new File(new File(dataRoot, "user"), "last_run.log").isFile());
        File modules = new File(dataRoot, "sys_modules");
        int count = 0;
        for (String name : MODULES) if (new File(modules, name).isFile()) count++;
        moduleStatus.setText("Sound modules: " + count + " of 2 imported");
    }

    private void showRuntimeLog() {
        File logFile = new File(new File(dataRoot, "user"), "last_run.log");
        try (RandomAccessFile file = new RandomAccessFile(logFile, "r")) {
            long length = file.length();
            int count = (int) Math.min(length, 1024 * 1024);
            file.seek(length - count);
            byte[] bytes = new byte[count];
            file.readFully(bytes);
            String prefix = length > count ? "Showing the last 1 MiB of the log.\n\n" : "";
            TextView contents = text(prefix + new String(bytes, StandardCharsets.UTF_8), 11, 0xffe6d8b5);
            ScrollView scroll = new ScrollView(this);
            scroll.setPadding(dp(12), dp(8), dp(12), dp(8));
            scroll.setBackground(getDrawable(R.drawable.log_bg));
            scroll.addView(contents);
            new AlertDialog.Builder(this).setTitle("Runtime log").setView(scroll)
                    .setPositiveButton("Close", null).show();
        } catch (Exception error) {
            activityStatus.setText("Cannot read runtime log: " + message(error));
        }
    }

    private void beginImport(String message) {
        importGameButton.setEnabled(false);
        importModulesButton.setEnabled(false);
        launchGameButton.setEnabled(false);
        activityStatus.setText(message);
    }

    private void finishImport(String message) {
        main.post(() -> {
            importGameButton.setEnabled(true);
            importModulesButton.setEnabled(true);
            launchGameButton.setEnabled(new File(new File(dataRoot, "game"), "eboot.bin").isFile());
            activityStatus.setText(message);
            refreshStatus();
        });
    }

    private void persistReadPermission(Uri uri, int flags) {
        try {
            getContentResolver().takePersistableUriPermission(uri, flags & Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (SecurityException ignored) {
            // Some document providers grant a temporary read permission only.
        }
    }

    private String displayName(Uri uri) throws Exception {
        String[] columns = {DocumentsContract.Document.COLUMN_DISPLAY_NAME};
        try (Cursor cursor = getContentResolver().query(uri, columns, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) return cursor.getString(0);
        }
        throw new Exception("Cannot read selected file name");
    }

    private static Sfo parseSfo(byte[] bytes) throws Exception {
        ByteBuffer data = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        if (bytes.length < 20 || data.getInt(0) != 0x46535000) throw new Exception("param.sfo has an invalid PSF header");
        long keyTable = Integer.toUnsignedLong(data.getInt(8));
        long valueTable = Integer.toUnsignedLong(data.getInt(12));
        long count = Integer.toUnsignedLong(data.getInt(16));
        if (count > 4096 || 20L + count * 16 > bytes.length) throw new Exception("param.sfo table is invalid");
        Sfo result = new Sfo();
        for (int i = 0; i < count; i++) {
            int row = 20 + i * 16;
            int keyOffset = Short.toUnsignedInt(data.getShort(row));
            int format = Short.toUnsignedInt(data.getShort(row + 2));
            long size = Integer.toUnsignedLong(data.getInt(row + 4));
            long offset = Integer.toUnsignedLong(data.getInt(row + 12));
            long keyStart = keyTable + keyOffset;
            long valueStart = valueTable + offset;
            if (keyStart >= bytes.length || valueStart + size > bytes.length || size > 1024 * 1024) {
                throw new Exception("param.sfo entry is out of range");
            }
            int keyEnd = (int) keyStart;
            while (keyEnd < bytes.length && bytes[keyEnd] != 0) keyEnd++;
            if (keyEnd == bytes.length) throw new Exception("param.sfo key is unterminated");
            String key = new String(bytes, (int) keyStart, keyEnd - (int) keyStart, StandardCharsets.UTF_8);
            if (format == 0x0404 && size >= 4) result.values.put(key, Integer.toString(data.getInt((int) valueStart)));
            else result.values.put(key, new String(bytes, (int) valueStart, (int) size, StandardCharsets.UTF_8).replace("\u0000", "").trim());
        }
        return result;
    }

    private static byte[] readAll(InputStream in, int limit) throws Exception {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = in.read(buffer)) >= 0) {
            if (out.size() + read > limit) throw new Exception("param.sfo is unexpectedly large");
            out.write(buffer, 0, read);
        }
        return out.toByteArray();
    }

    private static void copy(InputStream in, FileOutputStream out) throws Exception {
        byte[] buffer = new byte[1024 * 1024];
        int read;
        while ((read = in.read(buffer)) >= 0) out.write(buffer, 0, read);
        out.getFD().sync();
    }

    private static void copyFile(File source, File destination) throws Exception {
        try (InputStream in = new FileInputStream(source); FileOutputStream out = new FileOutputStream(destination)) {
            copy(in, out);
        }
    }

    private static String safeName(String name) throws Exception {
        if (name == null || name.isEmpty() || name.equals(".") || name.equals("..") || name.contains("/") || name.contains("\\")) {
            throw new Exception("Storage provider returned an invalid file name");
        }
        return name;
    }

    private static void deleteTree(File file) {
        if (!file.exists()) return;
        File[] children = file.listFiles();
        if (children != null) for (File child : children) deleteTree(child);
        file.delete();
    }

    private TextView section(String value) {
        TextView view = text(value, 18, 0xfff3eee2);
        view.setPadding(0, dp(8), 0, dp(8));
        return view;
    }

    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setLineSpacing(dp(3), 1f);
        return view;
    }

    private Button button(String value) {
        Button button = new Button(this);
        button.setText(value);
        button.setAllCaps(false);
        return button;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(-1, -2);
    }

    private LinearLayout.LayoutParams params(int left, int top, int right, int bottom) {
        LinearLayout.LayoutParams result = new LinearLayout.LayoutParams(-1, -2);
        result.setMargins(dp(left), dp(top), dp(right), dp(bottom));
        return result;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private static String message(Exception error) {
        return error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
    }

    private static final class MapChildren {
        final Set<String> names = new HashSet<>();
        final java.util.Map<String, String> idsByName = new java.util.HashMap<>();
    }

    private static final class Sfo {
        final java.util.Map<String, String> values = new java.util.HashMap<>();
    }
}
