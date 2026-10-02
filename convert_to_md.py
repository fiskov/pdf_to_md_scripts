#!/usr/bin/env python3
"""Convert PDFs from input/ to LLM-friendly Markdown in markdown/ using pymupdf4llm."""
import sys
import time
from pathlib import Path

import pymupdf4llm

BASE = Path(__file__).resolve().parent
INPUT_DIR = BASE / "input"
OUTPUT_DIR = BASE / "markdown"


def convert(pdf_path: Path) -> Path:
    out_path = OUTPUT_DIR / (pdf_path.stem + ".md")
    start = time.perf_counter()
    md = pymupdf4llm.to_markdown(str(pdf_path))
    out_path.write_text(md, encoding="utf-8")
    pages = pymupdf4llm.pymupdf.open(pdf_path).page_count
    elapsed = time.perf_counter() - start
    print(f"[OK] {pdf_path.name}: {pages} pages -> {out_path.name} "
          f"({len(md) / 1024:.0f} KB, {elapsed:.1f}s)")
    return out_path


def main() -> int:
    pdfs = sorted(INPUT_DIR.glob("*.pdf")) + sorted(p for p in INPUT_DIR.glob("*.PDF") if p.suffix == ".PDF")
    # de-duplicate case-insensitively (e.g. .pdf vs .PDF on same stem not expected, just in case)
    seen, files = set(), []
    for p in pdfs:
        key = p.name.lower()
        if key not in seen:
            seen.add(key)
            files.append(p)

    if not files:
        print(f"No PDFs found in {INPUT_DIR}", file=sys.stderr)
        return 1

    OUTPUT_DIR.mkdir(exist_ok=True)
    failures = 0
    for pdf_path in files:
        try:
            convert(pdf_path)
        except Exception as exc:  # keep going on single-file failure
            failures += 1
            print(f"[FAIL] {pdf_path.name}: {exc}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
