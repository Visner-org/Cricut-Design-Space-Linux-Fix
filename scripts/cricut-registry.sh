#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 visner
#
# Register the Cricut as a USB serial device (COM3) in the Wine prefix.
set -e
export WINEPREFIX="${WINEPREFIX:-$HOME/Games/cricut}" WINEDEBUG=-all
TTY=/dev/ttyACM0
eval "$(udevadm info -q property -n $TTY | grep -E '^ID_(VENDOR_ID|MODEL_ID|REVISION|SERIAL_SHORT)=')"
[ "$ID_VENDOR_ID" = 20d3 ] || { echo "$TTY is not a Cricut"; exit 1; }
VID=${ID_VENDOR_ID^^} PID=${ID_MODEL_ID^^} REV=${ID_REVISION} SER=$ID_SERIAL_SHORT
INST="USB\\VID_${VID}&PID_${PID}\\${SER}"
ENUM="HKLM\\System\\CurrentControlSet\\Enum\\$INST"

ln -sfn $TTY "$WINEPREFIX/dosdevices/com3"

wine reg add "$ENUM" /v DeviceDesc   /d "USB Serial Device" /f
wine reg add "$ENUM" /v FriendlyName /d "USB Serial Device (COM3)" /f
wine reg add "$ENUM" /v Mfg          /d "Provo Craft & Novelty Inc" /f
wine reg add "$ENUM" /v HardwareID   /t REG_MULTI_SZ /d "USB\\VID_${VID}&PID_${PID}&REV_${REV}\\0USB\\VID_${VID}&PID_${PID}" /f
wine reg add "$ENUM" /v CompatibleIDs /t REG_MULTI_SZ /d "USB\\Class_02&SubClass_02&Prot_01\\0USB\\Class_02&SubClass_02\\0USB\\Class_02" /f
wine reg add "$ENUM" /v Class        /d Ports /f
wine reg add "$ENUM" /v ClassGUID    /d "{4d36e978-e325-11ce-bfc1-08002be10318}" /f
wine reg add "$ENUM" /v Service      /d usbser /f
wine reg add "$ENUM" /v ConfigFlags  /t REG_DWORD /d 0 /f
wine reg add "$ENUM\\Device Parameters" /v PortName /d COM3 /f

# Device interfaces: USB device + COM port, marked as present (Linked=1)
for G in "{A5DCBF10-6530-11D2-901F-00C04FB951ED}" "{86E0D1E0-8089-11D0-9CE4-08003E301F73}"; do
    NAME="##?#USB#VID_${VID}&PID_${PID}#${SER}#$G"
    KEY="HKLM\\System\\CurrentControlSet\\Control\\DeviceClasses\\${G,,}\\$NAME"
    wine reg add "$KEY" /v DeviceInstance /d "$INST" /f
    wine reg add "$KEY\\#" /v SymbolicLink /d "\\\\?\\USB#VID_${VID}&PID_${PID}#${SER}#$G" /f
    wine reg add "$KEY\\#\\Control" /v Linked /t REG_DWORD /d 1 /f
done
echo "Registered $INST as COM3"
