# SPDX-License-Identifier: GPL-2.0-or-later
"""Prepare the imported game image for the Android native loader."""
from pathlib import Path

from content_profile import prepare as prepare_content
from link_modules import DEFAULT_MODULES, SYS_MODULES, link
from prepare import prepare as prepare_eboot
from sotc_cpu import prepare as prepare_cpu
from sotc_modes import prepare as prepare_modes


def prepare_game(game_path, modules_path, output_path):
    game = Path(game_path)
    modules_dir = Path(modules_path)
    output = Path(output_path)
    output.mkdir(parents=True, exist_ok=True)

    required = (game / "eboot.bin", game / "sce_sys/param.sfo",
                game / "sce_module/libc.prx", game / "sce_module/libSceFios2.prx")
    missing = [str(path.name) for path in required if not path.is_file()]
    if missing:
        raise ValueError("Missing required game files: " + ", ".join(missing))

    prepare_eboot(game, output)
    linked_modules = list(DEFAULT_MODULES)
    if all((modules_dir / name).is_file() for name in SYS_MODULES):
        linked_modules.extend(str((modules_dir / name).resolve()) for name in SYS_MODULES)
    link(game, output, linked_modules)
    prepare_content(game, output)
    prepare_cpu(game, output)
    prepare_modes(game, output, cvars_text="doIndexBufferCulling=0 doSunShadowIndexBufferCulling=0")

    required_outputs = ("boot-linked.bin", "content.bin", "sotc-cpu.bin", "patches.bin")
    missing = [name for name in required_outputs if not (output / name).is_file()]
    if missing:
        raise RuntimeError("Game preparation did not create: " + ", ".join(missing))
    return "Prepared game image and runtime metadata."
