/* SPDX-License-Identifier: GPL-2.0-or-later */
package org.sotc.android;

import org.libsdl.app.SDLActivity;

import java.io.File;
import java.util.ArrayList;

/** SDL owns the Android surface and invokes the native probe on its application thread. */
public final class GameActivity extends SDLActivity {
    static final String EXTRA_GAME_DIR = "org.sotc.android.GAME_DIR";
    static final String EXTRA_RUNTIME_DIR = "org.sotc.android.RUNTIME_DIR";
    static final String EXTRA_USER_DIR = "org.sotc.android.USER_DIR";

    @Override
    protected String getMainFunction() {
        return "sotc_main";
    }

    @Override
    protected String[] getArguments() {
        String game = getIntent().getStringExtra(EXTRA_GAME_DIR);
        String runtime = getIntent().getStringExtra(EXTRA_RUNTIME_DIR);
        String user = getIntent().getStringExtra(EXTRA_USER_DIR);
        if (game == null || runtime == null || user == null) return new String[0];

        ArrayList<String> args = new ArrayList<>();
        args.add(new File(runtime, "boot-linked.bin").getAbsolutePath());
        args.add("--content-profile");
        args.add(new File(runtime, "content.bin").getAbsolutePath());
        args.add("--sotc-cpu");
        args.add(new File(runtime, "sotc-cpu.bin").getAbsolutePath());
        args.add("--patches");
        args.add(new File(runtime, "patches.bin").getAbsolutePath());
        File commandLine = new File(runtime, "cmdline.bin");
        if (commandLine.isFile()) {
            args.add("--sotc-cmdline");
            args.add(commandLine.getAbsolutePath());
        }
        args.add("--app0");
        args.add(game);
        args.add("--user");
        args.add(user);
        args.add("--timeout");
        args.add("0");
        return args.toArray(new String[0]);
    }
}
