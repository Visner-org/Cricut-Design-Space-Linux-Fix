# Cricut Design Space on Linux (Wine)

Cricut Design Space 10.7 runs under Wine on Linux and cuts over USB. Sign-in, designing, connecting the machine, cutting and Print Then Cut all work on an Explore Air 2. No Windows VM needed.

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

## Tested setup

| Part | Version |
| --- | --- |
| Distro | Nobara Linux 44, KDE Plasma 6 (Wayland) |
| Wine | WineHQ `wine-staging` 11.17 |
| Design Space | 10.7.106 (Electron 43.2.0) |
| Machine | Cricut Explore Air 2, USB `20d3:0022` |
| Browser for login | Firefox (Flatpak) |
| Printer | Epson ET-4760 and a CUPS PDF printer |

Other Cricut machines should work the same way if they show up as a USB serial port (`/dev/ttyACM*`). There are two versions of the patch: one for Wine 11.17 (development) and one for 11.0 (the current stable release). The 11.0 one builds but hasn't been run with Design Space yet.

### Design Space versions

| Version | Result (2026-10-19) |
| --- | --- |
| 10.7.106 | Works: sign-in, USB connect and cutting, including after power cycles. Print Then Cut works: the page prints with its registration marks, the machine reads them, and the cut lands within a millimetre |
| 10.8.81 | Installs silently with `/S` from the full installer. Its device helpers are new builds but use the same Windows property names, so the patch should cover them. Cutting untested: the app downgraded itself to 10.7.106 within minutes (see below) |

**Design Space picks its own version.** `latest.json` lists the newest release, but the app follows the version Cricut assigns your account and will update or downgrade itself to match. Installing a newer version than your account's just gets reverted. Any version change, either way:

- replaces the plugin folders, which removes the patched `propsys.dll` (re-run `scripts/install-patched-dlls.sh`; the patched `gdiplus` lives in the prefix's system folder and stays)
- drops a raw `Cricut Design Space.lnk` on your desktop (`scripts/install-launcher.sh` removes it)

To stay on a version that works, see [Optional: stop automatic updates](#optional-stop-automatic-updates).

## What's in this repo

| File | What it does |
| --- | --- |
| `scripts/download-installer.sh` | Downloads and verifies the current Design Space installer (Step 1) |
| `scripts/cricut-design-space` | Launcher (Step 2) |
| `scripts/install-launcher.sh` | Installs the launcher, menu entry and `cricut://` handler; removes Wine's shortcuts (Step 2) |
| `scripts/cricut-registry.sh` | Registers the cutter as a USB serial device on COM3 (Step 3) |
| `patches/wine-cricut.patch` | Wine patch for `propsys`, `windows.devices.enumeration` and `gdiplus`, for Wine 11.17 (Step 4) |
| `patches/wine-11.0-cricut.patch` | The same patch for Wine 11.0 stable (Step 4) |
| `scripts/install-patched-dlls.sh` | Installs the patched DLLs for Design Space's helpers only (Step 4) |
| `udev/99-cricut-raw.rules` | Puts the cutter's serial port in raw mode (Step 5) |

All scripts use the prefix `~/Games/cricut`. Set `WINEPREFIX` to use another one.

## Step 1: Install Design Space in its own prefix

Use a fresh 64-bit prefix. No winetricks or extra runtimes are needed, and no Windows PC: `scripts/download-installer.sh` reads Cricut's public update manifest (`software.cricut.com/prod/win32-x64/latest.json`), downloads the current full installer (about 360 MB) and checks its SHA-512 hash.

```bash
./scripts/download-installer.sh ~/Downloads
export WINEPREFIX="$HOME/Games/cricut"
wineboot -i
wine ~/Downloads/CricutDesignSpace-Install-v*.exe /S
```

`/S` installs silently, per user, to `drive_c/users/$USER/AppData/Local/Programs/Cricut Design Space`. The small web installer from design.cricut.com works the same way. Don't start Design Space from the shortcuts the installer makes; Step 2 replaces them.

## Step 2: Launcher, menu entry and web login

```bash
./scripts/install-launcher.sh
```

This installs `~/.local/bin/cricut-design-space` and a **Cricut Design Space** menu entry, and registers it as the handler for `cricut://` links.

Always start Design Space through this launcher. Electron's main process crashes under Wine with "A JavaScript error occurred in the main process … open EBADF … process.getStderr" when it has no real stdout/stderr, which is the case whenever it starts from a menu, desktop icon or browser link. The launcher sends output to `~/Games/cricut/cricut-design-space.log`. It also sets `winemenubuilder.exe=d` so Design Space updates don't recreate Wine's shortcuts.

The script removes the shortcuts the installer created through Wine (desktop icon or `.lnk` file, Wine menu entry, and this prefix's `wine-extension-*.desktop` file associations), since those call `wine` directly and hit the crash.

Sign-in opens in your browser, which then hands a `cricut://?code=…` link back to the app. When the browser asks to open the link, allow it. A second copy of the app starts, passes the code to the open window and exits. This works from a Flatpak browser too.

## Step 3: Make Design Space see the cutter

On Linux the Explore Air 2 is a plain USB serial port: the `cdc_acm` driver creates `/dev/ttyACM0`. Your user must be in the `dialout` group to open it (`id -nG`; if it's missing, `sudo usermod -aG dialout $USER`, then log out and back in).

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

### Prebuilt DLLs (Wine 11.17 only)

On Wine 11.17 you can skip the build: download `cricut-wine-11.17-patched-dlls.zip` from the [latest release](https://github.com/Visner-org/Cricut-Design-Space-Linux-Fix/releases/latest), unpack it, and pass its folder to the install script (see Install below) instead of a build folder. For any other Wine version, build them from source.

### Build

Use the Wine source that matches `wine --version`, and the matching patch: `wine-cricut.patch` for 11.17, `wine-11.0-cricut.patch` for 11.0. On 11.0, swap `11.x/wine-11.17` for `11.0/wine-11.0` in the download URL and `wine-11.17` for `wine-11.0` in the commands below. You need `gcc`, `make`, `flex`, `bison` and `patch`; the Windows cross-compiler comes from [llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases), so no sudo is needed. After the downloads, configuring and building take under a minute and about 1.3 GB of disk.

```bash
REPO="$PWD"    # run from this repo's folder
mkdir -p ~/cricut-wine && cd ~/cricut-wine
curl -LO https://dl.winehq.org/wine/source/11.x/wine-11.17.tar.xz
curl -LO https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz
tar xf wine-11.17.tar.xz
tar xf llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz
export PATH="$PWD/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64/bin:$PATH"
(cd wine-11.17 && patch -p1 < "$REPO/patches/wine-cricut.patch")

mkdir build && cd build
../wine-11.17/configure --enable-archs=i386,x86_64 --disable-tests \
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

## Optional: stop automatic updates

Design Space needs the internet to sign in, open saved projects and upload images, so don't block it entirely. Block only its updates: every update or downgrade is downloaded to one folder, `AppData/Local/app-desktop-design-updater`, as `installer.exe`. Lock that folder and no update can land.

```bash
U="$HOME/Games/cricut/drive_c/users/$USER/AppData/Local/app-desktop-design-updater"
mkdir -p "$U" ~/Games/cricut/installers
# Keep a cached installer, if there is one: it's usually the version you're running
[ -f "$U/installer.exe" ] && mv "$U/installer.exe" ~/Games/cricut/installers/
echo "Locked so Design Space can't download updates. Undo: sudo chattr -i on this folder." > "$U/LOCKED.txt"
sudo chattr +i "$U"
```

A plain `chmod` isn't enough: Wine clears the read-only flag on files you own before deleting them. The immutable flag (`chattr +i`, root only) stops Wine from writing, deleting or changing the folder. The `LOCKED.txt` inside keeps it from being an empty folder.

If Cricut ever makes an update mandatory, Design Space may refuse to run. Undo the lock with `sudo chattr -i "$U"`, let it update, then run `scripts/install-patched-dlls.sh` again.

## Print Then Cut: start from Blank Canvas

This one isn't a Wine problem: it happens on Windows too. Every Design Space project has a type, picked when you create it (Blank Canvas, or a product or project canvas such as cards or iron-on). Design Space asks Cricut's servers which operations that type allows. If Print Then Cut isn't on the list, any printed image in the project is blocked with:

> **Operations not supported.** The Print Then Cut operation is not supported in this project.

Plain shapes in a solid color still work in those projects, which makes it look like a problem with the image. It isn't: the same image works in a new **Blank Canvas** project. Use Blank Canvas for Print Then Cut, not a specific project type. The type is shown at the top left of the canvas.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "A JavaScript error occurred in the main process … open EBADF" | Started without the launcher (desktop icon, Wine menu entry, browser) | Step 2 |
| Browser sign-in finishes but the app never logs in | No `cricut://` handler, or the browser blocked it | Step 2; allow the browser to open the link |
| Design Space never finds the machine | Missing registry entries, or the port belongs to something else (a VM, another app) | Step 3, then restart Design Space; check `/dev/ttyACM0` exists and you're in `dialout` |
| "USB Connection Failed" right away | The device helper keeps quitting (log shows `NativePluginDeviceCommonService … Exit Code 5`) | Step 4 |
| Connect worked before, fails after Design Space changed version | Design Space updates (or downgrades) itself to the version Cricut assigns your account, which replaces the plugin folders and removes the patched `propsys.dll` | `scripts/install-patched-dlls.sh` |
| Spinner never stops, or works once and not after a power cycle | Port is in terminal mode | Step 5 |
| App's top toolbar is hidden | Linux title bar on top of the app's own | Step 6 |
| "The Print Then Cut operation is not supported in this project" on an image | The project's type doesn't allow printing (a Design Space setting, not Wine) | Start from **Blank Canvas**; see [Print Then Cut](#print-then-cut-start-from-blank-canvas) |
| Design Space won't start, asks for an update you can't install | Updates are locked ([Optional: stop automatic updates](#optional-stop-automatic-updates)) and Cricut made one mandatory | `sudo chattr -i` the updater folder, let it update, run `scripts/install-patched-dlls.sh` |
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
