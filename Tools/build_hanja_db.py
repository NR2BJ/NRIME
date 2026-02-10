#!/usr/bin/env python3
"""
Build hanja.db from libhangul's hanja dictionary data.

Usage:
    python3 build_hanja_db.py [input_file] [output_file]

If no input file is specified, downloads from the libhangul repository.
Default output: ../NRIME/Resources/hanja.db
"""

import sqlite3
import sys
import os
import urllib.request
import tempfile

LIBHANGUL_HANJA_URL = "https://raw.githubusercontent.com/libhangul/libhangul/main/data/hanja/hanja.txt"

def download_hanja_txt():
    """Download hanja.txt from libhangul repository."""
    print("Downloading hanja.txt from libhangul...")
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt", mode="wb")
    urllib.request.urlretrieve(LIBHANGUL_HANJA_URL, tmp.name)
    print(f"Downloaded to {tmp.name}")
    return tmp.name

def parse_hanja_line(line):
    """Parse a line from hanja.txt. Format: hangul:hanja:meaning"""
    line = line.strip()
    if not line or line.startswith("#"):
        return None

    parts = line.split(":")
    if len(parts) < 3:
        return None

    hangul = parts[0].strip()
    hanja = parts[1].strip()
    meaning = parts[2].strip()

    if not hangul or not hanja:
        return None

    return (hangul, hanja, meaning)

def build_database(input_path, output_path):
    """Build SQLite database from hanja.txt."""
    # Remove existing database
    if os.path.exists(output_path):
        os.remove(output_path)

    conn = sqlite3.connect(output_path)
    cursor = conn.cursor()

    # Create table
    cursor.execute("""
        CREATE TABLE hanja (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hangul TEXT NOT NULL,
            hanja TEXT NOT NULL,
            meaning TEXT DEFAULT '',
            frequency INTEGER DEFAULT 0
        )
    """)

    # Create index
    cursor.execute("CREATE INDEX idx_hanja_hangul ON hanja(hangul)")

    # Parse and insert data
    count = 0
    with open(input_path, "r", encoding="utf-8") as f:
        for line in f:
            entry = parse_hanja_line(line)
            if entry:
                cursor.execute(
                    "INSERT INTO hanja (hangul, hanja, meaning, frequency) VALUES (?, ?, ?, 0)",
                    entry
                )
                count += 1

    conn.commit()
    conn.close()

    file_size = os.path.getsize(output_path)
    print(f"Database created: {output_path}")
    print(f"  Entries: {count}")
    print(f"  Size: {file_size / 1024:.1f} KB")

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_output = os.path.join(script_dir, "..", "NRIME", "Resources", "hanja.db")

    input_path = sys.argv[1] if len(sys.argv) > 1 else None
    output_path = sys.argv[2] if len(sys.argv) > 2 else default_output

    if input_path is None:
        input_path = download_hanja_txt()
        should_cleanup = True
    else:
        should_cleanup = False

    try:
        build_database(input_path, output_path)
    finally:
        if should_cleanup and os.path.exists(input_path):
            os.remove(input_path)

if __name__ == "__main__":
    main()
