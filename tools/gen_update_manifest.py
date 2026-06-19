#!/usr/bin/env python3
"""
Generates the AstraClient updater manifest (the JSON the update server returns to
modules/updater/updater.lua).

Checksums are CRC32 as 8-char lowercase hex (e.g. "0a1b2c3d"), which is exactly what the
client compares against:
  - data files: ResourceManager::filesChecksums() reads each data.zip entry's CRC via
    dec_to_hex (std::setw(8)<<std::setfill('0')<<std::hex).
  - binary: ResourceManager::selfChecksum() = g_crypt.crc32(exeBytes, false) = same format.

File keys mirror the client VFS paths: leading "/", backslashes normalized to "/".

Usage:
  # from a packaged data.zip (recommended -- CRCs come straight from the zip entries):
  python gen_update_manifest.py data.zip --url https://updates.koliseuot.com/files/ \
      --binary AstraClient_dx_x64.exe --binary-name AstraClient_dx_x64-123.exe -o update.json

  # from a directory tree instead of a zip (computes CRC32 of each file):
  python gen_update_manifest.py ./release_data --dir --url https://.../files/ -o update.json

The update server should return this JSON (verbatim) to the client's POST. Publish the
files referenced under <url> so the client can download <url> + <file path>.
"""
import argparse
import json
import os
import sys
import zipfile
import zlib


def crc_hex(crc: int) -> str:
    return format(crc & 0xFFFFFFFF, "08x")


def crc_of_file(path: str) -> str:
    crc = 0
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            crc = zlib.crc32(chunk, crc)
    return crc_hex(crc)


def vfs_key(name: str) -> str:
    name = name.replace("\\", "/")
    return name if name.startswith("/") else "/" + name


def files_from_zip(zip_path: str) -> dict:
    files = {}
    with zipfile.ZipFile(zip_path) as z:
        for info in z.infolist():
            if info.is_dir() or info.file_size == 0:
                continue
            files[vfs_key(info.filename)] = crc_hex(info.CRC)
    return files


def files_from_dir(root: str) -> dict:
    files = {}
    root = os.path.abspath(root)
    for dirpath, _dirs, names in os.walk(root):
        for n in names:
            full = os.path.join(dirpath, n)
            rel = os.path.relpath(full, root)
            files[vfs_key(rel)] = crc_of_file(full)
    return files


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate the AstraClient updater manifest.")
    ap.add_argument("source", help="data.zip (default) or a directory tree (with --dir)")
    ap.add_argument("--dir", action="store_true", help="treat source as a directory, not a zip")
    ap.add_argument("--url", required=True, help="base download URL (client fetches <url> + <file>)")
    ap.add_argument("--binary", help="path to the client exe to publish as a binary update")
    ap.add_argument("--binary-name", help="filename the client downloads the binary as "
                                          "(default: basename of --binary)")
    ap.add_argument("--keep-files", action="store_true",
                    help="set keepFiles=true (client won't prune local files outside the manifest)")
    ap.add_argument("-o", "--output", default="update.json", help="output JSON (default update.json)")
    args = ap.parse_args()

    if not os.path.exists(args.source):
        print(f"error: source not found: {args.source}", file=sys.stderr)
        return 1

    files = files_from_dir(args.source) if args.dir else files_from_zip(args.source)

    manifest = {"url": args.url, "files": files}
    if args.keep_files:
        manifest["keepFiles"] = True
    if args.binary:
        bname = args.binary_name or os.path.basename(args.binary)
        manifest["binary"] = {"file": bname, "checksum": crc_of_file(args.binary)}

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print(f"wrote {args.output}: {len(files)} files"
          + (" + binary" if args.binary else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
