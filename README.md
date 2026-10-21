# Cricut Design Space on Linux (Wine)

Cricut Design Space 10.7 runs under Wine on Linux and cuts over USB. Sign-in, designing, connecting the machine, cutting and Print Then Cut all work on an Explore Air 2. No Windows VM needed. Tested on Nobara, Ubuntu 26.04, CachyOS and Bazzite.

> **Made by AI.** The investigation, every script, the Wine patch and this README were done by an AI assistant, Claude (Anthropic), working on my PC. I set the goal, ran the tests with my own machine, reported what I saw, and checked that it cuts. Read the scripts before running them, and treat the patch as untested beyond the setup below.

Out of the box it fails in several places. These are the fixes, in the order you hit them:

1. **Launches from the menu or browser crash** with `open EBADF`. The launcher sends the app's output to a file.
2. **Web login** needs a `cricut://` link handler on the Linux side.
3. **The cutter is invisible.** Wine doesn't register it as a USB serial device, so a few registry entries add what Windows would create.
4. **The device helper quits every 10–50 seconds.** Two gaps in Wine (`propsys` and `windows.devices.enumeration`) kill it. A short patch fixes both.
5. **The machine stops answering mid-connect.** Linux opens the port in terminal mode, which mangles the binary protocol. A udev rule switches it to raw mode.
6. **The Linux title bar hides the app's top bar.** One registry value fixes that.
7. **Print Then Cut pages print black** around the design, and the registration marks disappear. A gap in Wine's `gdiplus`; the same patch as item 4 fixes it.

Bluetooth was not tested and probably doesn't work: Wine's Bluetooth support for apps is mostly stubs.

## Quick start

The short version for Wine 11.17 or 11.20. Steps 1–6 below explain each command; if something goes wrong, see [Troubleshooting](#troubleshooting).

1. Install Wine Staging 11.17 or 11.20 ([commands for each distro](#before-you-start-install-wine)). Check with `wine --version`.
2. Let your user open the cutter's port, then log out and back in:
   `sudo usermod -aG dialout $USER` (on Arch and CachyOS: `uucp` instead of `dialout`).
3. From the [releases](https://github.com/Visner-org/Cricut-Design-Space-Linux-Fix/releases), download the DLL zip that matches your Wine version and unpack it in `~/Downloads`. On another Wine version, build the DLLs yourself ([Step 4](#step-4-patch-three-wine-dlls)).
4. Get this repo and run these from its folder:

   ```bash
   # Step 1: install Design Space
   ./scripts/download-installer.sh ~/Downloads
   export WINEPREFIX="$HOME/Games/cricut"
   mkdir -p ~/Games
   WINEDLLOVERRIDES="mscoree,mshtml=" wine wineboot -i
   wine ~/Downloads/CricutDesignSpace-Install-v*.exe /S

   # Step 2: launcher, menu entry and web login
   ./scripts/install-launcher.sh

   # Step 4: patched DLLs (use the folder you unpacked)
   wineserver -k
   ./scripts/install-patched-dlls.sh ~/Downloads/cricut-wine-11.20-patched-dlls

   # Step 5: serial port in raw mode
   sudo cp udev/99-cricut-raw.rules /etc/udev/rules.d/
   sudo udevadm control --reload

   # Step 6: hide the Linux title bar
   wine reg add 'HKCU\Software\Wine\X11 Driver' /v Decorated /d N /f
   ```

5. Plug in the cutter and switch it on (off and on again if it was already on). Then:

   ```bash
   # Step 3: let Design Space find the cutter
   ./scripts/cricut-registry.sh
   ```

6. Start **Cricut Design Space** from your app menu and sign in. When the browser asks to open the `cricut://` link, allow it.

When Design Space changes version by itself, run `./scripts/install-patched-dlls.sh` again (no folder needed). Don't block its updates ([why](#updates-let-them-happen)). For Print Then Cut, start projects from [Blank Canvas](#print-then-cut-start-from-blank-canvas).

The rest of this README is the detailed version.

## Tested setup

| Part | Version |
| --- | --- |
| Distro | Nobara Linux 44, KDE Plasma 6 (Wayland) |
| Wine | WineHQ `wine-staging` 11.17 |
| Design Space | 10.7.106 (Electron 43.2.0) |
| Machine | Cricut Explore Air 2, USB `20d3:0022` |
| Browser for login | Firefox (Flatpak) |
| Printer | Epson ET-4760 and a CUPS PDF printer |

Other Cricut machines should work the same way if they show up as a USB serial port (`/dev/ttyACM*`). There are two versions of the patch: one for Wine development releases (made on 11.17, also tested on 11.20) and one for 11.0 (the current stable release). The 11.0 one builds but hasn't been run with Design Space yet.

### Other distros

Tested 2026-10-20 in virtual machines with the Explore Air 2 passed through over USB, Design Space 10.8.81:

| Distro | Wine | Result |
| --- | --- | --- |
| Ubuntu 26.04 LTS (GNOME) | WineHQ `winehq-staging` 11.20 | Installs, signs in (Snap Firefox), connects |
| CachyOS (KDE) | `wine-staging` 11.20 | Installs, signs in, connects |
| Bazzite 44 (KDE) | WineHQ `winehq-staging` 11.20 in a distrobox | Installs, signs in (Flatpak Firefox), connects |

Cutting and Print Then Cut were tested on Nobara only. How to get Wine on each: [Before you start: install Wine](#before-you-start-install-wine).

### Design Space versions

| Version | Result (2026-10-19) |
| --- | --- |
| 10.7.106 | Works: sign-in, USB connect and cutting, including after power cycles. Print Then Cut works: the page prints with its registration marks, the machine reads them, and the cut lands within a millimetre |
| 10.8.81 | Installs silently with `/S` from the full installer. Its device helpers are new builds but use the same Windows property names, so the patch should cover them. Cutting untested: the app downgraded itself to 10.7.106 within minutes (see below) |

**Design Space picks its own version.** `latest.json` lists the newest release, but the app follows the version Cricut assigns your account and will update or downgrade itself to match. Installing a newer version than your account's just gets reverted. Any version change, either way:

- replaces the plugin folders, which removes the patched `propsys.dll` (re-run `scripts/install-patched-dlls.sh`; the patched `gdiplus` lives in the prefix's system folder and stays)
- drops a raw `Cricut Design Space.lnk` on your desktop (`scripts/install-launcher.sh` removes it)

Blocking updates doesn't help: see [Updates: let them happen](#updates-let-them-happen).

## What's in this repo

| File | What it does |
| --- | --- |
| `scripts/download-installer.sh` | Downloads and verifies the current Design Space installer (Step 1) |
| `scripts/cricut-design-space` | Launcher (Step 2) |
| `scripts/install-launcher.sh` | Installs the launcher, menu entry and `cricut://` handler; removes Wine's shortcuts (Step 2) |
| `scripts/cricut-registry.sh` | Registers the cutter as a USB serial device on COM3 (Step 3) |
| `patches/wine-cricut.patch` | Wine patch for `propsys`, `windows.devices.enumeration` and `gdiplus`, for Wine development releases (11.17, 11.20) (Step 4) |
| `patches/wine-11.0-cricut.patch` | The same patch for Wine 11.0 stable (Step 4) |
| `scripts/install-patched-dlls.sh` | Installs the patched DLLs for Design Space's helpers only (Step 4) |
| `udev/99-cricut-raw.rules` | Puts the cutter's serial port in raw mode (Step 5) |

All scripts use the prefix `~/Games/cricut`. Set `WINEPREFIX` to use another one.

## Before you start: install Wine

Use Wine Staging, version 11.17 or newer (11.20 tested). Step 4 builds three DLLs from the same Wine version, so note which one you get (`wine --version`).

**Fedora and Nobara**: WineHQ's packages.

```bash
sudo dnf config-manager addrepo --from-repofile=https://dl.winehq.org/wine-builds/fedora/44/winehq.repo
sudo dnf install winehq-staging
```

**Ubuntu 26.04**: WineHQ's packages. WineHQ's own instructions fail on 26.04 because apt won't read their key file as downloaded; converting it with `gpg --dearmor` fixes that.

```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
wget -qO- https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key
sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/resolute/winehq-resolute.sources
sudo apt update && sudo apt install --install-recommends winehq-staging
```

**CachyOS** (and probably Arch): the distro's package. CachyOS also has `wine-cachyos`, which is older (10.0 based) and untested here.

```bash
sudo pacman -S wine-staging
```

**Bazzite** (and other immutable Fedora-based distros): Bazzite has no Wine and discourages adding packages to the system, so install it in a [distrobox](https://distrobox.it/) and export the `wine` and `wineserver` commands to the host. The scripts then run unchanged.

```bash
distrobox create -n cricut -i registry.fedoraproject.org/fedora-toolbox:44
distrobox enter cricut
# inside the box:
sudo dnf config-manager addrepo --from-repofile=https://dl.winehq.org/wine-builds/fedora/44/winehq.repo
sudo dnf install winehq-staging xdg-utils
distrobox-export --bin /opt/wine-staging/bin/wine --export-path ~/.local/bin
distrobox-export --bin /opt/wine-staging/bin/wineserver --export-path ~/.local/bin
exit
```

The box shares your home folder, so the prefix, scripts and Design Space's files are the same inside and out. Wine in the box can open the cutter's port as long as your user is in `dialout` on the host (Step 3).

## Step 1: Install Design Space in its own prefix

Use a fresh 64-bit prefix. No winetricks or extra runtimes are needed, and no Windows PC: `scripts/download-installer.sh` reads Cricut's public update manifest (`software.cricut.com/prod/win32-x64/latest.json`), downloads the current full installer (about 360 MB) and checks its SHA-512 hash.

```bash
./scripts/download-installer.sh ~/Downloads
export WINEPREFIX="$HOME/Games/cricut"
mkdir -p ~/Games
WINEDLLOVERRIDES="mscoree,mshtml=" wine wineboot -i
wine ~/Downloads/CricutDesignSpace-Install-v*.exe /S
```

Wine won't create the prefix if `~/Games` doesn't exist. The `WINEDLLOVERRIDES` line skips Wine's prompts to install Mono and Gecko: Design Space doesn't need either, and while the Mono prompt waits for a click, the installer fails (`could not load kernel32.dll`).

`/S` installs silently, per user, to `drive_c/users/$USER/AppData/Local/Programs/Cricut Design Space`. The small web installer from design.cricut.com works the same way. Don't start Design Space from the shortcuts the installer makes; Step 2 replaces them.

## Step 2: Launcher, menu entry and web login

```bash
./scripts/install-launcher.sh
```

This installs `~/.local/bin/cricut-design-space` and a **Cricut Design Space** menu entry, and registers it as the handler for `cricut://` links.

Always start Design Space through this launcher. Electron's main process crashes under Wine with "A JavaScript error occurred in the main process … open EBADF … process.getStderr" when it has no real stdout/stderr, which is the case whenever it starts from a menu, desktop icon or browser link. The launcher sends output to `~/Games/cricut/cricut-design-space.log`. It also sets `winemenubuilder.exe=d` so Design Space updates don't recreate Wine's shortcuts.

The script removes the shortcuts the installer created through Wine (desktop icon or `.lnk` file, Wine menu entry, and this prefix's `wine-extension-*.desktop` file associations), since those call `wine` directly and hit the crash. Wine writes them a few seconds after the installer exits, so the script waits for that first.

If `wine` is a distrobox export (Bazzite), the menu entry runs the launcher inside the box. Run through the exported `wine` instead, Wine would get its output through a pipe from the container rather than a file, and crash with the same EBADF error.

Sign-in opens in your browser, which then hands a `cricut://?code=…` link back to the app. When the browser asks to open the link, allow it. A second copy of the app starts, passes the code to the open window and exits. This works from a Flatpak browser too.

## Step 3: Make Design Space see the cutter

On Linux the Explore Air 2 is a plain USB serial port: the `cdc_acm` driver creates `/dev/ttyACM0`. Your user must be in the `dialout` group to open it (`id -nG`; if it's missing, `sudo usermod -aG dialout $USER`, then log out and back in). On Arch and CachyOS the group is `uucp` instead: `sudo usermod -aG uucp $USER`.

Design Space doesn't scan COM ports. It asks Windows for a USB device with Cricut's vendor ID (`20D3`), then reads that device's `PortName`. Wine doesn't register the Cricut that way, so the search comes back empty and the app never tries the port.

With the machine **on and plugged in** (the script reads its serial number from the device):

```bash
./scripts/cricut-registry.sh
```

It maps COM3 to `/dev/ttyACM0` and adds the registry entries Windows would create: the device under `Enum\USB\VID_20D3&PID_…\<serial>` with `PortName=COM3`, plus the USB-device and COM-port interfaces marked as present. Restart Design Space afterwards, since it searches for USB devices only at startup. Without Step 4, connecting then fails with "USB Connection Failed".

## Step 4: Patch three Wine DLLs

Design Space hands the connection to a helper, `plugins/device-common/CricutDevice.exe`. At startup it sets up Bluetooth discovery through the WinRT `DeviceWatcher` API, and two gaps in Wine kill it with exit code 5 before it reaches USB:

- **`propsys`** doesn't know the property names `System.Devices.Aep.SignalStrength`, `IsPresent`, `CanPair` and `System.DeviceInterface.Bluetooth.VendorId`/`ProductId`. The keys already exist in Wine's headers; they're just missing from the lookup table.
- **`windows.devices.enumeration`**: `DeviceWatcher.add_Removed`, `remove_Updated` and `remove_Removed` return `E_NOTIMPL`. The patch stores those handlers like `add_Added` does.

Print Then Cut hits a third gap. Design Space's printer helper, `plugins/system-printer/CricutSystemPrinter.exe`, gets the page as a PNG with a transparent background and draws it at its exact size with GDI+:

- **`gdiplus`** sends an unscaled image with transparency to a printer as a plain copy, so transparent pixels print as black. The page comes out black around the design and the registration marks vanish into it. Scaled images were already blended onto white; the patch sends unscaled ones the same way.

You only rebuild these three DLLs, not all of Wine, and they're used by Design Space's helpers alone. Your system Wine stays untouched.

### Prebuilt DLLs (Wine 11.17 and 11.20)

On Wine 11.17 or 11.20 you can skip the build: download `cricut-wine-11.17-patched-dlls.zip` or `cricut-wine-11.20-patched-dlls.zip` from the [releases](https://github.com/Visner-org/Cricut-Design-Space-Linux-Fix/releases), unpack it, and pass its folder to the install script (see Install below) instead of a build folder. For any other Wine version, build them from source.

### Build

Use the Wine source that matches `wine --version`, and the matching patch: `wine-cricut.patch` for development releases (11.17, 11.20), `wine-11.0-cricut.patch` for 11.0. Set `V` below to your version. On 11.0, also swap `11.x` for `11.0` in the download URL and use `wine-11.0-cricut.patch`.

You need `gcc`, `make`, `flex`, `bison` and `patch`:

| Distro | Command |
| --- | --- |
| Fedora, Nobara | `sudo dnf install gcc make flex bison patch` |
| Ubuntu | `sudo apt install gcc make flex bison patch` |
| CachyOS, Arch | `sudo pacman -S --needed gcc make flex bison patch` |
| Bazzite | inside the box: `sudo dnf install gcc make flex bison patch`, then run the build there (`distrobox enter cricut`) |

The Windows cross-compiler comes from [llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases), so no sudo is needed for the build itself. After the downloads, configuring and building take under a minute and about 1.3 GB of disk.

```bash
REPO="$PWD"    # run from this repo's folder
V=11.20        # your Wine version (wine --version)
mkdir -p ~/cricut-wine && cd ~/cricut-wine
curl -LO https://dl.winehq.org/wine/source/11.x/wine-$V.tar.xz
curl -LO https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz
tar xf wine-$V.tar.xz
tar xf llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz
export PATH="$PWD/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64/bin:$PATH"
(cd wine-$V && patch -p1 < "$REPO/patches/wine-cricut.patch")

mkdir build && cd build
../wine-$V/configure --enable-archs=i386,x86_64 --disable-tests \
  --without-x --without-wayland --without-freetype --without-fontconfig \
  --without-vulkan --without-opengl --without-gstreamer --without-ffmpeg \
  --without-pulse --without-alsa --without-oss --without-coreaudio \
  --without-cups --without-dbus --without-gnutls --without-krb5 \
  --without-netapi --without-sane --without-usb --without-v4l2 \
  --without-udev --without-sdl --without-pcap --without-pcsclite \
  --without-capi --without-gphoto --without-inotify --without-xinerama
make -j"$(nproc)" dlls/propsys/all dlls/windows.devices.enumeration/all dlls/gdiplus/all
```

### Install

Close Design Space first; overwriting DLLs it has loaded can crash it.

```bash
wineserver -k
"$REPO/scripts/install-patched-dlls.sh" ~/cricut-wine/build   # first time (or the unpacked prebuilt folder)
"$REPO/scripts/install-patched-dlls.sh"                       # after a Design Space update
```

Two Wine details shape this script. `WINEDLLPATH` can't override a built-in DLL, because Wine searches its own DLL folder first. And Wine swaps any file tagged "Wine builtin DLL" for its stock copy, so the script blanks that tag. It then puts `propsys.dll` next to the helpers, puts `windows.devices.enumeration.dll` and `gdiplus.dll` in the prefix's `system32`/`syswow64` (keeping the originals as `.orig`), and sets `native,builtin` overrides for `CricutDevice.exe`, `CricutDeviceIO.exe` and `CricutSystemPrinter.exe` only. `gdiplus` has to go in the system folder: it's one of Wine's "known DLLs", which are always loaded from there and stay mapped until `wineserver` stops, so restart Design Space after installing.

The DLLs are saved in `~/Games/cricut/patched-dlls`, so after the first run you can delete `~/cricut-wine`. After a **Wine** update, rebuild from the matching Wine source and pass the new build folder.

## Step 5: Put the serial port in raw mode

Linux opens a new serial port in terminal mode: it rewrites carriage returns and newlines (`icrnl`, `onlcr`), treats some bytes as pause/resume (`ixon`), and buffers input until a newline (`icanon`). Cricut's protocol is binary, and Design Space never changes the port settings, because the Windows driver has no such layer. The machine answers the first few commands, then goes quiet and the connect spinner never ends.

This udev rule sets raw mode every time a Cricut port appears, which covers power cycles and replugging. It matches only USB vendor `20d3`:

```bash
sudo cp udev/99-cricut-raw.rules /etc/udev/rules.d/
sudo udevadm control --reload
```

Then switch the machine off and on. To check it, `stty -F /dev/ttyACM0 -a` should show `-icanon -icrnl -ixon`. To fix it for one session without the rule: `stty -F /dev/ttyACM0 raw -echo -echoe -echok -echoctl -echoke -hupcl`.

## Step 6: Hide the Linux title bar

Design Space draws its own title bar with Windows-style buttons. The window manager adds a second one over it, which hides part of the app's top toolbar. Turn off window decorations for this prefix:

```bash
WINEPREFIX="$HOME/Games/cricut" wine reg add 'HKCU\Software\Wine\X11 Driver' /v Decorated /d N /f
```

It applies the next time Design Space starts. Move the window with the app's own title bar, or with your desktop's shortcuts (Alt+drag on KDE).

## Updates: let them happen

Don't try to block Design Space updates. It checks with Cricut when it starts and runs the version Cricut assigns your account. Reports say it won't start on an older one, so blocking updates can't keep you on a version. It only stops the app from getting the version it needs. After each version change, run `scripts/install-patched-dlls.sh` again.

## Print Then Cut: start from Blank Canvas

This one isn't a Wine problem: it happens on Windows too. Every Design Space project has a type, picked when you create it (Blank Canvas, or a product or project canvas such as cards or iron-on). Design Space asks Cricut's servers which operations that type allows. If Print Then Cut isn't on the list, any printed image in the project is blocked with:

> **Operations not supported.** The Print Then Cut operation is not supported in this project.

Plain shapes in a solid color still work in those projects, which makes it look like a problem with the image. It isn't: the same image works in a new **Blank Canvas** project. Use Blank Canvas for Print Then Cut, not a specific project type. The type is shown at the top left of the canvas.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `apt update` on Ubuntu: "The key(s) in the keyring … winehq-archive.key are ignored as the file has an unsupported filetype" | apt on 26.04 won't read WineHQ's key as downloaded | Convert it with `gpg --dearmor` ([Before you start](#before-you-start-install-wine)) |
| `wine: chdir to …/Games/cricut : No such file or directory` | `~/Games` doesn't exist | `mkdir -p ~/Games` (Step 1) |
| "Wine Mono Installer" pops up, or the installer fails with `could not load kernel32.dll` | Wine is asking to install Mono; the installer ran before the prefix was ready | Start over with a fresh prefix and the `WINEDLLOVERRIDES` line from Step 1 |
| "A JavaScript error occurred in the main process … open EBADF" | Started without the launcher (desktop icon, Wine menu entry, browser) | Step 2 |
| The same EBADF error on Bazzite, from the menu | The menu entry runs the exported `wine` outside the box | Run `scripts/install-launcher.sh` again after exporting `wine` ([Before you start](#before-you-start-install-wine)) |
| `usermod: group 'dialout' does not exist` | Arch and CachyOS use `uucp` for serial ports | `sudo usermod -aG uucp $USER` (Step 3) |
| Sign-in opens the page as text in an editor | No default web browser is set | Set one in your desktop's settings |
| Browser sign-in finishes but the app never logs in | No `cricut://` handler, or the browser blocked it | Step 2; allow the browser to open the link |
| Design Space never finds the machine | Missing registry entries, or the port belongs to something else (a VM, another app) | Step 3, then restart Design Space; check `/dev/ttyACM0` exists and you're in `dialout` |
| "USB Connection Failed" right away | The device helper keeps quitting (log shows `NativePluginDeviceCommonService … Exit Code 5`) | Step 4 |
| Connect worked before, fails after Design Space changed version | Design Space updates (or downgrades) itself to the version Cricut assigns your account, which replaces the plugin folders and removes the patched `propsys.dll` | `scripts/install-patched-dlls.sh` |
| Spinner never stops, or works once and not after a power cycle | Port is in terminal mode | Step 5 |
| App's top toolbar is hidden | Linux title bar on top of the app's own | Step 6 |
| "The Print Then Cut operation is not supported in this project" on an image | The project's type doesn't allow printing (a Design Space setting, not Wine) | Start from **Blank Canvas**; see [Print Then Cut](#print-then-cut-start-from-blank-canvas) |
| Print Then Cut page prints black around the design, no registration marks | Wine's `gdiplus` (Step 4) | Rebuild with the current patch, run `scripts/install-patched-dlls.sh <build folder>`, restart Design Space |

To see what the helper does, start Design Space from a terminal with serial and file logging and search the log for `COM3`:

```bash
cd "$HOME/Games/cricut/drive_c/users/$USER/AppData/Local/Programs/Cricut Design Space"
WINEPREFIX="$HOME/Games/cricut" WINEDEBUG=-all,+comm,+file,err+all wine "Cricut Design Space.exe" </dev/null >/tmp/cds-trace.log 2>&1
```

The log gets large (hundreds of MB) within minutes, so use it for one test. It can contain your login code, so check it before sharing.

## Upstream status

None of this is in Wine yet. The patch fills gaps in Wine rather than adding Cricut-specific hacks (the `gdiplus` fix helps any program that prints images with transparency), so it's a good candidate for upstream; once Wine includes it, Step 4 goes away. Steps 3 and 5 would need Wine changes too: registering USB serial devices with a COM port, and putting serial ports in raw mode on open.

Open questions:

- Bluetooth connection is untested. Wine's `BluetoothAdapter.GetRadioAsync` is still a stub.
- Only the Explore Air 2 was tested. Reports from other machines (Maker, Joy, Explore 3) are welcome.

## License

The scripts and udev rule are licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE) for the full text.

The patches in `patches/` modify Wine, which is licensed under the GNU Lesser General Public License v2.1 or later. They're under the same license. See [patches/COPYING.LIB](patches/COPYING.LIB).

This project is not affiliated with or endorsed by Cricut, Inc. Cricut, Cricut Design Space and Explore Air are trademarks of Cricut, Inc. No Cricut software is included; you download Design Space from Cricut yourself.
