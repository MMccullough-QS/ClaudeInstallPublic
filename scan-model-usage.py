# scan-model-usage.py
# Scans the Claude workspace for hardcoded model strings.
# Reports file:line, current model, and whether a newer version is available.
#
# Usage:
#   py scan-model-usage.py
#   py scan-model-usage.py --workspace "C:\Users\Name\Claude"
#
# Run after check-model-updates.py reports new models are available.

import json
import os
import re
import sys
from pathlib import Path

# Known model patterns (newest listed first within each tier)
# WHY: ordered newest-first so we can flag files using older models
MODEL_TIERS = {
    "opus":   ["claude-opus-4-6",   "claude-opus-4-5",   "claude-3-opus-20240229"],
    "sonnet": ["claude-sonnet-4-6", "claude-sonnet-4-5", "claude-3-5-sonnet-20241022",
               "claude-3-5-sonnet-20240620", "claude-3-sonnet-20240229"],
    "haiku":  ["claude-haiku-4-5-20251001", "claude-haiku-4-5", "claude-3-5-haiku-20241022",
               "claude-3-haiku-20240307"],
}

LATEST = {
    "opus":   "claude-opus-4-6",
    "sonnet": "claude-sonnet-4-6",
    "haiku":  "claude-haiku-4-5-20251001",
}

# Build flat pattern list with tier lookup
ALL_MODELS = {}
for tier, versions in MODEL_TIERS.items():
    for v in versions:
        ALL_MODELS[v] = tier

PATTERN = re.compile(
    r'(' + '|'.join(re.escape(m) for m in sorted(ALL_MODELS, key=len, reverse=True)) + r')'
)

SKIP_DIRS = {".git", "__pycache__", "node_modules", ".venv", "venv",
             "output", "archive", "ref", "memory-backup", "config-backup"}

SCAN_EXTS = {".py", ".ps1", ".md", ".json", ".txt", ".yaml", ".yml", ".sh", ".bat"}


def find_workspace():
    state_file = Path(os.environ["USERPROFILE"]) / ".claude" / "model-check-state.json"
    if state_file.exists():
        try:
            data = json.loads(state_file.read_text(encoding="utf-8"))
            ws = data.get("workspace")
            if ws and Path(ws).is_dir():
                return Path(ws)
        except Exception:
            pass
    # Fallback: use directory of this script
    return Path(__file__).parent


def scan_file(path: Path):
    """Return list of (line_number, line_text, model_id) matches."""
    hits = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return hits
    for i, line in enumerate(text.splitlines(), start=1):
        for match in PATTERN.finditer(line):
            hits.append((i, line.strip(), match.group(1)))
    return hits


def is_outdated(model_id):
    tier = ALL_MODELS.get(model_id)
    if not tier:
        return False
    return model_id != LATEST[tier]


def main():
    workspace = Path(sys.argv[1]) if len(sys.argv) > 1 else find_workspace()
    print(f"Scanning: {workspace}")
    print()

    results = {}   # model_id -> list of (file, line, line_text)
    total_files  = 0
    total_hits   = 0

    for root, dirs, files in os.walk(workspace):
        root_path = Path(root)
        # Prune skip dirs
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith('.')]
        # Skip if this is a subdirectory git repo root (separate project)
        if root_path != workspace and (root_path / ".git").exists():
            dirs.clear()
            continue

        for fname in files:
            fpath = root_path / fname
            if fpath.suffix.lower() not in SCAN_EXTS:
                continue
            hits = scan_file(fpath)
            if hits:
                total_files += 1
                total_hits  += len(hits)
                for line_num, line_text, model_id in hits:
                    rel = fpath.relative_to(workspace)
                    results.setdefault(model_id, []).append((str(rel), line_num, line_text))

    if not results:
        print("No hardcoded model strings found.")
    else:
        # Group: outdated first, then current
        outdated = {m: v for m, v in results.items() if is_outdated(m)}
        current  = {m: v for m, v in results.items() if not is_outdated(m)}

        if outdated:
            print("=== OUTDATED MODELS (upgrade candidates) ===")
            for model_id, occurrences in outdated.items():
                tier = ALL_MODELS.get(model_id, "?")
                latest = LATEST.get(tier, "?")
                print(f"\n  {model_id}  -->  {latest}  ({len(occurrences)} occurrence(s))")
                for rel, line_num, line_text in occurrences[:10]:
                    print(f"    {rel}:{line_num}")
                    print(f"      {line_text[:120]}")
                if len(occurrences) > 10:
                    print(f"    ... and {len(occurrences) - 10} more")

        if current:
            print("\n=== CURRENT MODELS (no upgrade needed) ===")
            for model_id, occurrences in current.items():
                print(f"\n  {model_id}  ({len(occurrences)} occurrence(s))")
                for rel, line_num, line_text in occurrences[:5]:
                    print(f"    {rel}:{line_num}")
                if len(occurrences) > 5:
                    print(f"    ... and {len(occurrences) - 5} more")

    print()
    print("--- CLAUDE SUMMARY ---")
    print(f"status:    {'WARN' if outdated else 'OK'}")
    print(f"scanned:   {total_files} files with model strings ({total_hits} total occurrences)")
    print(f"outdated:  {sum(len(v) for v in outdated.values())} occurrences across {len(outdated)} model(s)")
    print(f"current:   {sum(len(v) for v in current.values())} occurrences across {len(current)} model(s)")
    print(f"next:      {'Update highlighted files to use ' + ', '.join(LATEST.values()) if outdated else 'No action needed'}")
    print("--- END SUMMARY ---")


if __name__ == "__main__":
    main()
