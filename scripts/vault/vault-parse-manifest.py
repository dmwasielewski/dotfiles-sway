#!/usr/bin/env python3
"""Parse a vault manifest.toml into TSV lines the shell can consume.

Output per [[secret]]: action<TAB>source<TAB>k=v<TAB>k=v...
Trailing k=v pairs are sorted by key so output is deterministic for tests.
Values must not contain tabs or newlines (secrets are single-line keys/tokens).
"""
import sys
import tomllib


def main(path: str) -> int:
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    for s in data.get("secret", []):
        action = s.get("action", "")
        source = s.get("source", "")
        rest = {k: v for k, v in s.items() if k not in ("action", "source")}
        cols = [action, source] + [f"{k}={rest[k]}" for k in sorted(rest)]
        for c in cols:
            if "\t" in str(c) or "\n" in str(c):
                print(f"manifest: tab/newline in value: {c!r}", file=sys.stderr)
                return 2
        print("\t".join(str(c) for c in cols))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: vault-parse-manifest.py manifest.toml", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
