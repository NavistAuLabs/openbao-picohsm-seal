#!/usr/bin/env python3
"""Add pico-hsm VID/PID to /etc/libccid_Info.plist if not already present."""
import plistlib

path = "/etc/libccid_Info.plist"
with open(path, "rb") as f:
    p = plistlib.load(f)

if "0x2E8A" not in p["ifdVendorID"]:
    p["ifdVendorID"].append("0x2E8A")
    p["ifdProductID"].append("0x10FD")
    p["ifdFriendlyName"].append("Pico HSM")
    with open(path, "wb") as f:
        plistlib.dump(p, f)
    print("CHANGED")
else:
    print("OK")
