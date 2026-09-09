#!/usr/bin/env python3

from pathlib import Path

BASE = Path("raw/idflakies-reverse-fixed/traces")

records = []

for protocol in ["clean", "reused"]:
    directory = BASE / protocol

    if not directory.exists():
        raise SystemExit(f"Missing trace directory: {directory}")

    for trace_file in directory.glob("trace-*.log"):
        for line in trace_file.read_text().splitlines():
            fields = {}

            for piece in line.split(","):
                if "=" in piece:
                    key, value = piece.split("=", 1)
                    fields[key] = value

            if "timestamp" not in fields:
                continue

            records.append({
                "protocol": protocol,
                "timestamp": int(fields["timestamp"]),
                "pid": fields.get("pid", "?"),
                "event": fields.get("event", "?"),
                "marker": fields.get("marker_exists", "?"),
            })

for protocol in ["clean", "reused"]:
    print()
    print("=" * 72)
    print(protocol.upper())
    print("=" * 72)

    rows = sorted(
        (r for r in records if r["protocol"] == protocol),
        key=lambda r: r["timestamp"],
    )

    for row in rows:
        print(
            f'{row["timestamp"]}  '
            f'pid={row["pid"]:<8} '
            f'{row["event"]:<28} '
            f'marker={row["marker"]}'
        )
