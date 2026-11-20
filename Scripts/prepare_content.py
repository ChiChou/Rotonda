#!/usr/bin/env python3
"""Build local SQLite artifacts from the data text sources."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=os.environ.get("PATENTE_DATA"),
                        help="Content source directory (default: bundled data; or set PATENTE_DATA)")
    args = parser.parse_args()
    if args.source:
        source = Path(args.source).resolve()
    else:
        source = ROOT / "data"
    if source is None or not (source / "scripts/build_database.py").is_file():
        parser.error("data sources not found; pass --source or set PATENTE_DATA")
    def run(*command):
        subprocess.run([sys.executable, *map(str, command)], check=True)
    with tempfile.TemporaryDirectory(prefix="rotonda-source-") as tmp:
        tmp = Path(tmp)
        run(source / "scripts/build_ab_database.py", "--output", tmp / "ab")
        run(source / "scripts/build_database.py", "--output", tmp / "upstream.db")
        run(ROOT / "Scripts/import_bank_data.py", "--source", source,
            "--source-db", tmp / "upstream.db", "--legacy", tmp / "ab/quiz.db")
        # Keep the validated input for tests and explicit content rebuilds.
        (ROOT / "data/app/quiz.db").write_bytes((tmp / "ab/quiz.db").read_bytes())
    run(ROOT / "Scripts/build_content_db.py")


if __name__ == "__main__":
    main()
