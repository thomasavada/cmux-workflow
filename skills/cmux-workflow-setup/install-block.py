#!/usr/bin/env python3
"""Insert or refresh the cmux-workflow compact-survival block in CLAUDE.md / AGENTS.md.

Idempotent: a second run replaces the marked section in place. --uninstall removes it.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

START = "<!-- cmux-workflow -->"
END = "<!-- /cmux-workflow -->"

# Canonical block. CLAUDE.md / AGENTS.md are the durable copy — do not restate
# cmux-orchestration §5.0 here. This file only has to survive compact and point back.
BLOCK = f"""{START}
## cmux-workflow

Compact (or a session that never auto-invoked the skill) drops `cmux-orchestration`.
The next move is almost always to do the work yourself, one file at a time. That is the bug.

Before any multi-file or splittable implementation:

1. **Read** `cmux-orchestration` this turn. Search `~/.claude/plugins`, `~/.codex/plugins`,
   `~/.grok/installed-plugins` for `skills/cmux-orchestration/SKILL.md` and open it. If you
   cannot quote §5.0's five dispatch steps, you have not read it this turn.
2. **Spawn lanes** for disjoint `owns`. Do not implement those slices in this chat.
3. **Arm the watcher in the same turn you dispatch** — `lane-watch.sh`, or
   `orca-lane-watch.sh` if the host is Orca. Not next turn. A lane nobody is watching
   becomes the user asking whether it is done.
4. If lanes might already exist: `lane-status.sh --all` (or `orca-lane-status.sh --all`)
   before opening more.

**On Orca, read `orca-orchestration` for the mechanics** — terminal creation, the probe,
and a completion signal that works there. `tui-idle` reports idle mid-turn, and codex's
`Worked for` footer is absent on short turns, so both lie. The when/how-to-brief rules
above are shared and are not repeated there.

A one-line fix, a question, or work that cannot be split stays in this chat. Everything else
is a lane. Refresh this block with `cmux-workflow-setup`.
{END}
"""


def _join(prefix: str, suffix: str) -> str:
    """Assemble prefix + BLOCK + suffix with at most one blank line at each seam."""
    parts: list[str] = []
    if prefix.strip():
        parts.append(prefix.rstrip())
    parts.append(BLOCK.strip("\n"))
    if suffix.strip():
        parts.append(suffix.strip("\n"))
    return "\n\n".join(parts) + "\n"


def splice(text: str, uninstall: bool) -> str | None:
    """Return new file contents, or None if the file should be deleted."""
    if START in text and END in text:
        before, rest = text.split(START, 1)
        _, after = rest.split(END, 1)
        if uninstall:
            leftover = (before.rstrip() + "\n" + after.lstrip("\n")).strip()
            return leftover + "\n" if leftover else None
        return _join(before, after)
    if uninstall:
        return text  # nothing to remove
    if not text.strip():
        return _join("", "")
    return _join(text, "")


def apply(path: Path, uninstall: bool, created: list[Path], updated: list[Path], removed: list[Path]) -> None:
    existed = path.exists()
    original = path.read_text(encoding="utf-8") if existed else ""
    new = splice(original, uninstall=uninstall)
    if new is None:
        if existed:
            path.unlink()
            removed.append(path)
        return
    if new == original:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new if new.endswith("\n") else new + "\n", encoding="utf-8")
    (created if not existed else updated).append(path)


def project_files(root: Path) -> list[Path]:
    return [root / "CLAUDE.md", root / "AGENTS.md"]


def global_files() -> list[Path]:
    home = Path.home()
    files = [home / ".claude" / "CLAUDE.md", home / ".grok" / "AGENTS.md"]
    if (home / ".codex").is_dir():
        files.append(home / ".codex" / "AGENTS.md")
    return files


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--project",
        nargs="?",
        const=".",
        default=None,
        metavar="DIR",
        help="project root (default: cwd when neither --project nor --global is passed)",
    )
    p.add_argument(
        "--global",
        dest="do_global",
        action="store_true",
        help="write user-global ~/.claude/CLAUDE.md and ~/.grok/AGENTS.md",
    )
    p.add_argument("--uninstall", action="store_true", help="remove the marked section")
    args = p.parse_args()

    # Default: project at cwd. --global can combine with --project.
    targets: list[Path] = []
    if args.project is not None or not args.do_global:
        root = Path(args.project or ".").resolve()
        if not root.is_dir():
            print(f"error: not a directory: {root}", file=sys.stderr)
            return 2
        targets.extend(project_files(root))
    if args.do_global:
        targets.extend(global_files())

    created: list[Path] = []
    updated: list[Path] = []
    removed: list[Path] = []
    unchanged: list[Path] = []
    for path in targets:
        existed = path.exists()
        before = path.read_text(encoding="utf-8") if existed else ""
        apply(path, args.uninstall, created, updated, removed)
        after_exists = path.exists()
        after = path.read_text(encoding="utf-8") if after_exists else ""
        if existed and after_exists and before == after:
            unchanged.append(path)
        elif args.uninstall and not existed:
            unchanged.append(path)

    verb = "removed from" if args.uninstall else "wired into"
    for label, group in (
        ("created", created),
        ("updated", updated),
        ("removed", removed),
        ("unchanged", unchanged),
    ):
        for path in group:
            print(f"{label}: {path}")
    if not (created or updated or removed):
        if args.uninstall:
            print("nothing to uninstall")
        else:
            print(f"already {verb} every target")
    return 0


if __name__ == "__main__":
    # Make sure a crash still reports a path the agent can see.
    try:
        sys.exit(main())
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        raise
