#!/usr/bin/env python3
"""Minify pose JSON: compact separators + round floats (default 4 decimals)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def round_num(x: float, nd: int = 4):
    r = round(x, nd)
    if abs(r - int(r)) < 1e-9 and abs(x) < 1e12:
        return int(r)
    return r


def walk(o, nd: int):
    if isinstance(o, dict):
        return {k: walk(v, nd) for k, v in o.items()}
    if isinstance(o, list):
        return [walk(v, nd) for v in o]
    if isinstance(o, float):
        return round_num(o, nd)
    return o


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--decimals", type=int, default=4)
    args = ap.parse_args()
    if not args.src.exists():
        print(f"Missing {args.src}", file=sys.stderr)
        return 1
    data = json.loads(args.src.read_text(encoding="utf-8"))
    out = walk(data, args.decimals)
    text = json.dumps(out, separators=(",", ":"), ensure_ascii=False)
    args.dst.parent.mkdir(parents=True, exist_ok=True)
    args.dst.write_text(text, encoding="utf-8")
    b, a = args.src.stat().st_size, args.dst.stat().st_size
    print(f"{b/1024/1024:.2f} MB → {a/1024/1024:.2f} MB ({100*a/b:.0f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
