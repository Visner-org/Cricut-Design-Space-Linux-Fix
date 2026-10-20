# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Fixes to run Cricut Design Space (Electron app) under Wine on Linux and cut over USB. No build system or tests: it's a handful of bash scripts, a udev rule, and a Wine source patch. `README.md` is the main deliverable: a step-by-step guide (Steps 1–6) where each step fixes one failure, plus a Troubleshooting table that points back to the steps. When behavior changes, update the README step, the "What's in this repo" table and the Troubleshooting table together.

Tested setup: Nobara 44, WineHQ `wine-staging` 11.17, Design Space 10.7.106, Explore Air 2 (USB `20d3:0022`, `/dev/ttyACM0`). Also tested (install, sign-in, connect; no cutting) on Ubuntu 26.04, CachyOS and Bazzite 44 with Wine 11.20 and Design Space 10.8.81, in libvirt VMs. On Bazzite Wine runs in a distrobox with `wine`/`wineserver` exported to `~/.local/bin`; `install-launcher.sh` detects that and makes the menu entry run the launcher inside the box. Verifying anything for real needs the user's physical cutter/printer: ask them to test rather than claiming it works.

## How the pieces fit

- All scripts default to the prefix `~/Games/cricut` (`WINEPREFIX` overrides) and the app path `drive_c/users/$USER/AppData/Local/Programs/Cricut Design Space`. Keep that convention in new scripts.
- `scripts/cricut-design-space` is the only supported way to start the app: Electron crashes with `EBADF` without real stdio, so it redirects to `$WINEPREFIX/cricut-design-space.log`. It's also the `cricut://` login handler (`install-launcher.sh` registers it).
- `scripts/cricut-registry.sh` fakes the Windows registry entries for a USB serial device (`Enum\USB\VID_20D3&PID_…\<serial>`, `PortName=COM3`) because Design Space finds the cutter by USB vendor ID, not by scanning COM ports. Needs the machine plugged in (reads the serial).
- `patches/` changes three Wine DLLs, used only by Design Space's helper exes:
  - `propsys` + `windows.devices.enumeration`: keep `plugins/device-common/CricutDevice.exe` from exiting with code 5.
  - `gdiplus`: Print Then Cut (`plugins/system-printer/CricutSystemPrinter.exe`) printed transparency as black.
  - Two versions of the same patch, kept in sync: `wine-cricut.patch` (Wine 11.17) and `wine-11.0-cricut.patch` (11.0 stable, built but not run with Design Space). They're `git format-patch` style, applied with `patch -p1` in the Wine source tree.
- `scripts/install-patched-dlls.sh` takes a Wine build folder (`dlls/<name>/{i386,x86_64}-windows/`) or the unpacked prebuilt release zip (`x86/`, `x64/`), saves copies in `$WINEPREFIX/patched-dlls`, blanks the "Wine builtin DLL" marker at offset 0x40 so Wine won't swap in its stock copy, puts `propsys.dll` next to the helpers and the other two in `system32`/`syswow64` (originals kept as `.orig`; `gdiplus` is a known DLL so it must live there), and sets `native,builtin` overrides per helper exe. With no argument it reinstalls the saved copies; needed after every Design Space version change, since that replaces the plugin folders.
- Design Space updates/downgrades itself to the version Cricut assigns the account. The README's optional update lock is `chattr +i` on `AppData/Local/app-desktop-design-updater`.

## Building the patched DLLs

Full command list is in README Step 4. In short: matching Wine source + llvm-mingw, apply the patch, configure with nearly everything `--without-*`, then build only the three DLLs:

```bash
make -j"$(nproc)" dlls/propsys/all dlls/windows.devices.enumeration/all dlls/gdiplus/all
```

Close Design Space and run `wineserver -k` before installing DLLs.

## Conventions

- Scripts: `#!/bin/bash`, SPDX `GPL-3.0-or-later` header with `Copyright (C) 2026 visner`, short comments explaining the Wine/Windows reason behind each step. Patches are LGPL-2.1-or-later (Wine's license).
- README style: plain, short sentences; say what was tested and on which version, and mark untested things as untested. It states it was made by AI; keep that.
- Remotes: `origin` fetches from the user's Gitea and pushes to both Gitea and GitHub (`Visner-org/Cricut-Design-Space-Linux-Fix`, where the prebuilt DLL zip is a GitHub release). Push only when asked.
