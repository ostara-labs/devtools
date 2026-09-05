#!/usr/bin/env python3
"""Docs-drift check — a towncrier-style gate for "docs live with code".

Reads ``docs/DOC_MAP.yml``: rules map code-path globs to doc files that
must ship together with the code. Two failure modes:

- **MISSING** — none of a rule's mapped docs exist in the tree. Create
  one. Editing the map itself does NOT satisfy this mode; the only ways
  out are creating the file or the deliberate bypass label.
- **DRIFT** — the mapped docs exist but none was changed by this PR.
  Update one. Editing ``docs/DOC_MAP.yml`` in the same PR counts as a
  legitimate re-scoping and satisfies this mode.

Deliberate bypass: the ``no-docs`` label (``--bypassed``, set by the
workflow when the PR carries it) — the bypass is loud, never silent.
``--warn`` reports without failing (rollout mode). ``--audit`` checks
every rule's docs for existence regardless of the diff (coverage audit).

Usage:
  check-docs-drift.py --base origin/main [--map docs/DOC_MAP.yml]
                      [--warn] [--bypassed] [--audit]

Exit codes: 0 when clean, bypassed, or in warn mode; 1 on findings.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import subprocess
import sys

MAP_PATH = "docs/DOC_MAP.yml"


def changed_files(base: str) -> list[str]:
    """Files changed between the merge-base of base and HEAD."""
    out = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]


def matches(path: str, patterns: list[str]) -> bool:
    """fnmatch-style glob; ``*`` crosses ``/`` so ``dir/**`` hits the tree."""
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def findings_for(rules: list[dict], exempt: list[str], changed: list[str], map_edited: bool) -> list[str]:
    """Return human-readable findings for the changed-file set."""
    findings: list[str] = []
    code_changed = [f for f in changed if not matches(f, exempt)]
    for rule in rules:
        paths = rule.get("paths") or []
        docs = rule.get("docs") or []
        if not paths or not docs:
            print(f"[docs-drift] malformed rule skipped (needs paths and docs): {rule}")
            continue
        hit = sorted({f for f in code_changed if matches(f, paths)})
        if not hit:
            continue
        name = rule.get("name") or paths[0]
        if all(not os.path.exists(doc) for doc in docs):
            findings.append(
                f"[MISSING] rule '{name}': none of the mapped docs exist.\n"
                f"  matched code:\n    - " + "\n    - ".join(hit) + "\n"
                + "  create at least one of:\n    - " + "\n    - ".join(docs)
                + "\n  (a new file created in this PR satisfies the rule;\n"
                "   editing the DOC_MAP itself does not)"
            )
            continue
        if not any(doc in changed for doc in docs):
            if map_edited:
                continue  # legitimate re-scoping satisfies DRIFT
            findings.append(
                f"[DRIFT] rule '{name}': the docs exist but none changed.\n"
                f"  matched code:\n    - " + "\n    - ".join(hit) + "\n"
                + "  update or create one of:\n    - " + "\n    - ".join(docs)
            )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", required=True, help="merge-base ref, e.g. origin/main")
    parser.add_argument("--map", default=MAP_PATH, help="path to the DOC_MAP file")
    parser.add_argument("--warn", action="store_true", help="report findings without failing (rollout)")
    parser.add_argument("--bypassed", action="store_true", help="bypass label present on the PR")
    parser.add_argument("--audit", action="store_true", help="check all rules' docs exist, ignore the diff")
    args = parser.parse_args()

    if not os.path.exists(args.map):
        print(f"[docs-drift] no map at '{args.map}'; nothing to enforce")
        return 0

    import yaml  # deferred: only needed when a map exists

    with open(args.map, encoding="utf-8") as handle:
        doc_map = yaml.safe_load(handle) or {}
    rules = doc_map.get("rules") or []
    exempt = doc_map.get("exempt") or []

    if args.audit:
        missing = [doc for rule in rules for doc in (rule.get("docs") or []) if not os.path.exists(doc)]
        if missing:
            print("[docs-drift] AUDIT: mapped docs that do not exist:")
            for doc in sorted(set(missing)):
                print(f"  - {doc}")
            return 0 if args.warn else 1
        print("[docs-drift] AUDIT: all mapped docs exist.")
        return 0

    changed = changed_files(args.base)
    map_edited = MAP_PATH in changed
    if map_edited:
        print("[docs-drift] DOC_MAP.yml edited in this PR (re-scoping satisfies DRIFT, not MISSING).")

    findings = findings_for(rules, exempt, changed, map_edited)
    if not findings:
        print("[docs-drift] ok: no mapped code changed without its docs.")
        return 0

    prefix = "[docs-drift][warn] " if args.warn else "[docs-drift] "
    if args.bypassed:
        print(f"{prefix}BYPASSED via the 'no-docs' label — {len(findings)} finding(s):")
        for finding in findings:
            print(f"  {finding}")
        return 0
    if args.warn:
        print(f"{prefix}{len(findings)} finding(s) (warn mode — not failing):")
        for finding in findings:
            print(f"  {finding}")
        return 0

    print(f"{prefix}{len(findings)} finding(s). Fix them, or add the 'no-docs' label:")
    for finding in findings:
        print(f"  {finding}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
