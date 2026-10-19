#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 visner
#
# Download the current full Design Space installer for Windows from Cricut's
# update server and check its SHA-512 hash. Usage: download-installer.sh [folder]
set -e
DEST="${1:-$PWD}"
BASE="https://software.cricut.com/prod/win32-x64"
MANIFEST="$(curl -fsSL "$BASE/latest.json")"
read -r FILE HASH < <(python3 -c 'import json,sys; m=json.loads(sys.argv[1]); print(m["latestInstallFile"], m["latestUpdateFileHash"] if m["latestUpdateFile"]==m["latestInstallFile"] else "")' "$MANIFEST")
case "$FILE" in CricutDesignSpace-Install-v*.exe) ;; *) echo "Unexpected file name in manifest: $FILE"; exit 1;; esac

mkdir -p "$DEST"
echo "Downloading $FILE"
curl -fL --progress-bar -C - -o "$DEST/$FILE" "$BASE/$FILE"
if [ -n "$HASH" ]; then
    echo "$HASH  $DEST/$FILE" | sha512sum -c --quiet - && echo "SHA-512 OK"
else
    echo "No hash in the manifest for this file; skipped the check"
fi
echo "$DEST/$FILE"
