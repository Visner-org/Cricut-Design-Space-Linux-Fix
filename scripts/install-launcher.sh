#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 visner
#
# Install the launcher and menu entry, register the cricut:// login handler,
# and remove the shortcuts the installer made through Wine (they crash with EBADF).
set -e
export WINEPREFIX="${WINEPREFIX:-$HOME/Games/cricut}"
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"

mkdir -p "$BIN" "$APPS" "${XDG_CONFIG_HOME:-$HOME/.config}"
install -m 755 "$(dirname "$0")/cricut-design-space" "$BIN/cricut-design-space"
# Bake in the prefix so a non-default WINEPREFIX keeps working from the menu
sed -i "s|^export WINEPREFIX=.*|export WINEPREFIX=\"$WINEPREFIX\" WINEDEBUG=-all WINEDLLOVERRIDES=\"winemenubuilder.exe=d\"|" "$BIN/cricut-design-space"

cat > "$APPS/cricut-design-space.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Cricut Design Space
Comment=Cricut Design Space (Wine)
Exec=$BIN/cricut-design-space %u
Icon=applications-graphics
Categories=Graphics;
MimeType=x-scheme-handler/cricut;
StartupWMClass=cricut design space.exe
DESKTOP

rm -f "$DESKTOP_DIR/Cricut Design Space.desktop" "$DESKTOP_DIR/Cricut Design Space.lnk" \
      "$APPS/wine/Programs/Cricut Design Space.desktop"
# Wine's file associations for this prefix (.reg, .chm, .vbs, ...)
grep -l -F "$WINEPREFIX" "$APPS"/wine-extension-*.desktop 2>/dev/null | xargs -r rm

update-desktop-database "$APPS" 2>/dev/null || true
xdg-mime default cricut-design-space.desktop x-scheme-handler/cricut
echo "Launcher installed: $BIN/cricut-design-space"
