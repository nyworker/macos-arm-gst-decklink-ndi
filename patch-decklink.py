#!/usr/bin/env python3
"""Patch libgstdecklink.dylib: raise write_vbi CEA-708 RAW size limit 46 -> 127.
Verified offsets for GStreamer 1.28.0 and 1.28.1 (arm64 macOS).
"""
import shutil, struct, subprocess, sys
from pathlib import Path

gst_ver = subprocess.check_output(
    ["brew", "list", "--versions", "gstreamer"], text=True
).split()[1]
src = Path(f"/opt/homebrew/Cellar/gstreamer/{gst_ver}/lib/gstreamer-1.0/libgstdecklink.dylib")
dst = Path(__file__).parent / "plugins" / "libgstdecklink.dylib"
dst.parent.mkdir(exist_ok=True)
shutil.copy2(src, dst)
dst.chmod(0o644)
subprocess.run(["codesign", "--remove-signature", str(dst)], check=True)

# CMP X9,#47 -> CMP X9,#127  and  CMP X26,#47 -> CMP X26,#127
patches = [
    (0xc000, bytes.fromhex("3fbd00f1"), bytes.fromhex("3ffd01f1")),
    (0xc024, bytes.fromhex("5fbf00f1"), bytes.fromhex("5fff01f1")),
]
with open(dst, "r+b") as f:
    for off, old, new in patches:
        f.seek(off)
        cur = f.read(4)
        if cur == new:
            print(f"  {hex(off)}: already patched")
        elif cur == old:
            f.seek(off)
            f.write(new)
            print(f"  {hex(off)}: patched")
        else:
            print(f"  {hex(off)}: UNEXPECTED bytes {cur.hex()} — wrong GStreamer version?", file=sys.stderr)

subprocess.run(["codesign", "--force", "--sign", "-", str(dst)], check=True)
print(f"Done. Set GST_PLUGIN_PATH={dst.parent} in your environment.")
