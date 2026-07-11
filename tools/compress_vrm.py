#!/usr/bin/env python3
"""
Compress a VRM (glTF binary) by resizing/re-encoding embedded textures
WITHOUT stripping the VRM extension, skins, or humanoid data.

Usage:
  python3 tools/compress_vrm.py assets/yoga_avatar.vrm assets/yoga_avatar.vrm
  python3 tools/compress_vrm.py in.vrm out.vrm --max-size 512
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError(f"Not a GLB: {path}")
    offset = 12
    json_chunk = None
    bin_chunk = b""
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<I4s", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_len]
        offset += chunk_len
        # chunks are padded to 4 bytes
        if chunk_type == b"JSON":
            json_chunk = json.loads(chunk.decode("utf-8"))
        elif chunk_type == b"BIN\x00":
            bin_chunk = chunk
    if json_chunk is None:
        raise ValueError("GLB missing JSON chunk")
    return json_chunk, bin_chunk


def write_glb(path: Path, gltf: dict, bin_blob: bytes) -> None:
    json_bytes = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )
    # pad JSON to 4-byte boundary with spaces
    json_pad = (4 - (len(json_bytes) % 4)) % 4
    json_bytes += b" " * json_pad

    bin_pad = (4 - (len(bin_blob) % 4)) % 4
    bin_blob_padded = bin_blob + (b"\x00" * bin_pad)

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_blob_padded)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(json_bytes), b"JSON")
    out += json_bytes
    out += struct.pack("<I4s", len(bin_blob_padded), b"BIN\x00")
    out += bin_blob_padded
    path.write_bytes(out)


def extract_view(bin_blob: bytes, view: dict, buffer_offset: int = 0) -> bytes:
    off = buffer_offset + view.get("byteOffset", 0)
    length = view["byteLength"]
    return bin_blob[off : off + length]


def compress_image(
    raw: bytes, max_size: int, mime: str | None
) -> tuple[bytes, str]:
    img = Image.open(BytesIO(raw))
    img.load()

    # Resize longest edge
    w, h = img.size
    scale = min(1.0, max_size / max(w, h))
    if scale < 1.0:
        nw = max(1, int(round(w * scale)))
        nh = max(1, int(round(h * scale)))
        img = img.resize((nw, nh), Image.Resampling.LANCZOS)

    has_alpha = img.mode in ("RGBA", "LA") or (
        img.mode == "P" and "transparency" in img.info
    )
    buf = BytesIO()

    # Keep alpha as PNG; opaque as JPEG (much smaller) when safe.
    if has_alpha:
        if img.mode not in ("RGBA", "RGB"):
            img = img.convert("RGBA")
        img.save(buf, format="PNG", optimize=True, compress_level=9)
        return buf.getvalue(), "image/png"

    if img.mode != "RGB":
        img = img.convert("RGB")
    img.save(buf, format="JPEG", quality=75, optimize=True)
    return buf.getvalue(), "image/jpeg"


def rebuild_bin(
    gltf: dict, old_bin: bytes, replacements: dict[int, bytes]
) -> bytes:
    """
    Rebuild BIN by walking bufferViews in order of appearance.
    replacements: bufferView index -> new bytes
    """
    views = gltf.get("bufferViews") or []
    # Collect unique ranges for non-replaced views from original buffer 0
    new_bin = bytearray()
    # map old view index -> (newOffset, newLength)
    for i, view in enumerate(views):
        if view.get("buffer", 0) != 0:
            continue
        if i in replacements:
            payload = replacements[i]
        else:
            payload = extract_view(old_bin, view)

        # 4-byte align
        pad = (4 - (len(new_bin) % 4)) % 4
        new_bin += b"\x00" * pad
        new_offset = len(new_bin)
        new_bin += payload
        view["byteOffset"] = new_offset
        view["byteLength"] = len(payload)

    buffers = gltf.setdefault("buffers", [{"byteLength": 0}])
    if not buffers:
        buffers.append({"byteLength": 0})
    buffers[0]["byteLength"] = len(new_bin)
    # strip uri if any — embedded only
    buffers[0].pop("uri", None)
    return bytes(new_bin)


def compress_vrm(src: Path, dst: Path, max_size: int) -> None:
    gltf, bin_blob = read_glb(src)
    images = gltf.get("images") or []
    views = gltf.get("bufferViews") or []

    if not images:
        print("No embedded images; copying as-is.")
        dst.write_bytes(src.read_bytes())
        return

    replacements: dict[int, bytes] = {}
    saved = 0

    for img_i, image in enumerate(images):
        bv_index = image.get("bufferView")
        if bv_index is None:
            continue
        if bv_index < 0 or bv_index >= len(views):
            continue
        view = views[bv_index]
        raw = extract_view(bin_blob, view)
        old_len = len(raw)
        try:
            new_bytes, mime = compress_image(raw, max_size, image.get("mimeType"))
        except Exception as e:
            print(f"  skip image[{img_i}]: {e}")
            continue
        image["mimeType"] = mime
        # clear uri if present
        image.pop("uri", None)
        replacements[bv_index] = new_bytes
        delta = old_len - len(new_bytes)
        saved += max(0, delta)
        print(
            f"  image[{img_i}] {old_len/1024:.1f}KB → {len(new_bytes)/1024:.1f}KB "
            f"({mime})"
        )

    new_bin = rebuild_bin(gltf, bin_blob, replacements)

    # Ensure VRM still listed
    used = gltf.setdefault("extensionsUsed", [])
    if "VRM" not in used and "extensions" in gltf and "VRM" in gltf["extensions"]:
        used.insert(0, "VRM")

    write_glb(dst, gltf, new_bin)
    before = src.stat().st_size
    after = dst.stat().st_size
    print(
        f"Done: {before/1024/1024:.2f} MB → {after/1024/1024:.2f} MB "
        f"({100 * after / before:.0f}%)  texture_saved≈{saved/1024/1024:.2f} MB"
    )
    print(f"  VRM extension present: {'VRM' in gltf.get('extensions', {})}")
    print(f"  skins: {len(gltf.get('skins') or [])}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Compress VRM textures, keep VRM data")
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--max-size", type=int, default=512, help="Max texture edge (px)")
    args = ap.parse_args()
    if not args.src.exists():
        print(f"Missing: {args.src}", file=sys.stderr)
        return 1
    args.dst.parent.mkdir(parents=True, exist_ok=True)
    # Write to temp if in-place
    if args.src.resolve() == args.dst.resolve():
        tmp = args.dst.with_suffix(".tmp.vrm")
        compress_vrm(args.src, tmp, args.max_size)
        tmp.replace(args.dst)
    else:
        compress_vrm(args.src, args.dst, args.max_size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
