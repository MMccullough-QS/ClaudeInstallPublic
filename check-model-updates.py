# check-model-updates.py
# Checks for new Claude model releases and writes a notification to the Claude
# memory directory if a change is detected.
#
# Detection methods (in order):
#   1. Anthropic /v1/models API  (if ANTHROPIC_API_KEY env var is set)
#   2. npm registry -- latest @anthropic-ai/claude-code version (fallback)
#
# Run weekly via Task Scheduler. See setup-model-check-task.ps1 to register.
#
# Output: ~/.claude/model-update-notification.md (if new models/version found)
# State:  ~/.claude/model-check-state.json       (last-known versions)

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

CLAUDE_DIR    = Path(os.environ["USERPROFILE"]) / ".claude"
STATE_FILE    = CLAUDE_DIR / "model-check-state.json"
NOTIFY_FILE   = CLAUDE_DIR / "model-update-notification.md"

# Current known models as of 2026-10-28 -- Claude updates this list when
# new models are announced in a session (via the CLAUDE.md convention).
DEFAULT_KNOWN_MODELS = [
    "claude-opus-4-6",
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
]
DEFAULT_KNOWN_CC_VERSION = "1.0.0"  # placeholder; real version written on first run


def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {
        "known_models":     DEFAULT_KNOWN_MODELS,
        "cc_version":       DEFAULT_KNOWN_CC_VERSION,
        "last_checked":     None,
    }


def save_state(state):
    CLAUDE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


def check_via_api(api_key):
    """Query Anthropic /v1/models and return list of model IDs."""
    try:
        import urllib.request
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/models",
            headers={
                "x-api-key":         api_key,
                "anthropic-version": "2023-06-01",
            },
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        return [m["id"] for m in data.get("data", [])]
    except Exception as e:
        print(f"  API check failed: {e}", file=sys.stderr)
        return None


def check_via_npm():
    """Return latest @anthropic-ai/claude-code version from npm registry."""
    try:
        result = subprocess.run(
            ["npm", "show", "@anthropic-ai/claude-code", "version"],
            capture_output=True, text=True, timeout=15,
        )
        version = result.stdout.strip()
        return version if version else None
    except Exception as e:
        print(f"  npm check failed: {e}", file=sys.stderr)
        return None


def write_notification(new_models, new_cc_version, old_models, old_cc_version):
    lines = [
        "# Claude Model Update Notification",
        "",
        f"Detected: {datetime.now().strftime('%Y-%m-%d')}",
        "",
    ]

    if new_models:
        lines += [
            "## New Models Available",
            "",
        ]
        for m in new_models:
            lines.append(f"- `{m}`")
        lines.append("")

    if new_cc_version and new_cc_version != old_cc_version:
        lines += [
            "## Claude Code Updated",
            "",
            f"- Previous: `{old_cc_version}`",
            f"- Latest:   `{new_cc_version}`",
            "",
        ]

    lines += [
        "## Suggested Actions",
        "",
        "1. Review the model list above",
        "2. Run `scan-model-usage.py` to find hardcoded model strings in projects",
        "3. Update `~/.claude/CLAUDE.md` model references if needed",
        "4. Update `known_models` in `~/.claude/model-check-state.json` once reviewed",
        "",
        "_Claude will prompt you to scan projects at the start of the next session._",
    ]

    CLAUDE_DIR.mkdir(parents=True, exist_ok=True)
    NOTIFY_FILE.write_text("\n".join(lines), encoding="utf-8")
    print(f"  Notification written: {NOTIFY_FILE}")


def main():
    print(f"[check-model-updates] {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    state = load_state()

    new_models     = []
    new_cc_version = None
    api_key        = os.environ.get("ANTHROPIC_API_KEY", "")

    # --- Method 1: Anthropic API ---
    if api_key:
        print("  Checking Anthropic API...")
        api_models = check_via_api(api_key)
        if api_models is not None:
            known = set(state.get("known_models", []))
            new_models = [m for m in api_models if m not in known]
            if new_models:
                print(f"  New models via API: {new_models}")
            else:
                print(f"  No new models ({len(api_models)} known)")
    else:
        print("  ANTHROPIC_API_KEY not set -- skipping API check")

    # --- Method 2: npm version (fallback / supplement) ---
    print("  Checking Claude Code npm version...")
    npm_version = check_via_npm()
    if npm_version:
        old_cc = state.get("cc_version", DEFAULT_KNOWN_CC_VERSION)
        if npm_version != old_cc and old_cc != DEFAULT_KNOWN_CC_VERSION:
            new_cc_version = npm_version
            print(f"  Claude Code updated: {old_cc} -> {npm_version}")
        else:
            print(f"  Claude Code version unchanged: {npm_version}")
        state["cc_version"] = npm_version
    else:
        old_cc = state.get("cc_version", DEFAULT_KNOWN_CC_VERSION)

    # --- Write notification if anything changed ---
    if new_models or new_cc_version:
        write_notification(new_models, new_cc_version, state.get("known_models", []), old_cc)
        if new_models:
            state["known_models"] = list(set(state.get("known_models", [])) | set(new_models))
    else:
        print("  No updates detected.")
        # Clear stale notification if present
        if NOTIFY_FILE.exists():
            NOTIFY_FILE.unlink()
            print("  Cleared stale notification.")

    state["last_checked"] = datetime.now().isoformat()
    save_state(state)

    print("\n--- CLAUDE SUMMARY ---")
    print(f"status:    {'UPDATES FOUND' if (new_models or new_cc_version) else 'OK'}")
    print(f"new_models: {len(new_models)}  ({', '.join(new_models) if new_models else 'none'})")
    print(f"cc_version: {npm_version or 'unknown'}")
    print(f"notify:    {'yes -- ' + str(NOTIFY_FILE) if (new_models or new_cc_version) else 'no'}")
    print(f"next:      {'Review notification at session start' if (new_models or new_cc_version) else 'No action needed'}")
    print("--- END SUMMARY ---")


if __name__ == "__main__":
    main()
