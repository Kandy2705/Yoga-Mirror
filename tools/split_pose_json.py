#!/usr/bin/env python3
"""
Split a monolith pose JSON into meta + time chunks for lazy load.

Usage:
  python3 tools/split_pose_json.py assets/poses/tree_pose.json assets/poses/tree_pose
  python3 tools/split_pose_json.py assets/poses/tree_pose.json assets/poses/tree_pose --frames-per-chunk 60
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser(description="Split pose JSON into lazy chunks")
    ap.add_argument("src", type=Path, help="Monolith pose JSON")
    ap.add_argument(
        "out_dir",
        type=Path,
        help="Output dir (e.g. assets/poses/tree_pose)",
    )
    ap.add_argument(
        "--frames-per-chunk",
        type=int,
        default=60,
        help="Frames per chunk (~6s at 10fps). Default 60.",
    )
    ap.add_argument(
        "--asset-prefix",
        type=str,
        default=None,
        help="Flutter asset prefix for chunk paths (default: out_dir as posix)",
    )
    args = ap.parse_args()

    if not args.src.exists():
        print(f"Missing {args.src}", file=sys.stderr)
        return 1

    print(f"Reading {args.src} ...")
    data = json.loads(args.src.read_text(encoding="utf-8"))
    frames = data.get("frames") or []
    if not frames:
        print("No frames", file=sys.stderr)
        return 1

    frames = sorted(frames, key=lambda f: f.get("timestampMs", 0))
    n = len(frames)
    fpc = max(1, args.frames_per_chunk)
    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    # Clear old chunks
    for old in out_dir.glob("chunk_*.json"):
        old.unlink()

    asset_prefix = (args.asset_prefix or out_dir.as_posix()).rstrip("/")
    chunks_meta = []
    start_ts = int(frames[0]["timestampMs"])
    end_ts = int(frames[-1]["timestampMs"])

    for ci, i0 in enumerate(range(0, n, fpc)):
        part = frames[i0 : i0 + fpc]
        name = f"chunk_{ci:03d}.json"
        path = out_dir / name
        payload = {"frames": part}
        text = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        path.write_text(text, encoding="utf-8")
        c_start = int(part[0]["timestampMs"])
        c_end = int(part[-1]["timestampMs"])
        chunks_meta.append(
            {
                "index": ci,
                "asset": f"{asset_prefix}/{name}",
                "startTimestampMs": c_start,
                "endTimestampMs": c_end,
                "frameCount": len(part),
                "frameStartIndex": i0,
            }
        )
        print(f"  wrote {name}  frames={len(part)}  t={c_start}-{c_end}  {path.stat().st_size/1024:.1f}KB")

    meta = {
        "schemaVersion": "2.0-chunked",
        "sourceSchemaVersion": data.get("schemaVersion"),
        "frameCount": n,
        "startTimestampMs": start_ts,
        "endTimestampMs": end_ts,
        "durationMs": end_ts - start_ts,
        "framesPerChunk": fpc,
        "chunkCount": len(chunks_meta),
        "chunks": chunks_meta,
        "capture": data.get("capture"),
        "device": data.get("device"),
        "captureParams": data.get("captureParams"),
    }
    meta_path = out_dir / "meta.json"
    meta_path.write_text(
        json.dumps(meta, separators=(",", ":"), ensure_ascii=False),
        encoding="utf-8",
    )
    print(
        f"Done: {n} frames → {len(chunks_meta)} chunks + meta "
        f"({meta_path.stat().st_size}B meta). durationMs={end_ts - start_ts}"
    )
    print(f"Flutter default: {asset_prefix}/meta.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
