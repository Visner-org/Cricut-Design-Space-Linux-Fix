#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 visner
#
# Install patched propsys + windows.devices.enumeration for Design Space's device helpers only.
# Re-run after a Design Space update (it replaces the plugin folders) or a Wine update.
set -e
export WINEPREFIX="${WINEPREFIX:-$HOME/Games/cricut}" WINEDEBUG=-all
P="$WINEPREFIX/drive_c/users/$USER/AppData/Local/Programs/Cricut Design Space/resources/plugins"
W="$WINEPREFIX/drive_c/windows"
OUT="$WINEPREFIX/patched-dlls"

# With a build folder: save fresh copies in the prefix. Without one: reuse the saved copies.
if [ -n "$1" ]; then
    mkdir -p "$OUT/x86" "$OUT/x64"
    for dll in propsys windows.devices.enumeration; do
        cp "$1/dlls/$dll/i386-windows/$dll.dll"   "$OUT/x86/"
        cp "$1/dlls/$dll/x86_64-windows/$dll.dll" "$OUT/x64/"
    done
fi
[ -f "$OUT/x86/propsys.dll" ] || { echo "No patched DLLs yet: pass the build folder"; exit 1; }

# Blank Wine's builtin marker so the loader uses these copies instead of the stock builtins
for f in "$OUT"/x86/*.dll "$OUT"/x64/*.dll; do
    python3 - "$f" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read())
if b[0x40:0x50] == b"Wine builtin DLL":
    b[0x40:0x50] = b"Patched for CDS "; open(p, 'wb').write(b)
PY
done

# propsys: loaded from the helper's own folder (CricutDevice.exe is 32-bit, CricutDeviceIO.exe 64-bit)
cp "$OUT/x86/propsys.dll" "$P/device-common/"
cp "$OUT/x86/propsys.dll" "$P/device-common-next/"
cp "$OUT/x64/propsys.dll" "$P/cricut-device-io/"

# windows.devices.enumeration: WinRT loads it by full system path
for pair in "syswow64:x86" "system32:x64"; do
    dir=${pair%%:*}; arch=${pair##*:}
    [ -f "$W/$dir/windows.devices.enumeration.dll.orig" ] || cp "$W/$dir/windows.devices.enumeration.dll" "$W/$dir/windows.devices.enumeration.dll.orig"
    cp "$OUT/$arch/windows.devices.enumeration.dll" "$W/$dir/"
done

# Prefer these copies for the helpers only; everything else keeps Wine's builtins
for exe in CricutDevice.exe CricutDeviceIO.exe; do
    for dll in propsys windows.devices.enumeration; do
        wine reg add "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" /v "$dll" /d native,builtin /f >/dev/null
    done
done
echo "Patched DLLs installed."
