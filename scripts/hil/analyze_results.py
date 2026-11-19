#!/usr/bin/env python3
"""analyze_results.py - aggregate HIL result JSONs into markdown + JSON.

Exit codes:
  0  all gate results passed (green)
  1  at least one failure/error (or unreadable evidence)
  2  no failures, but at least one blocked gate (not green, not red)

Blocked is not a failure, but it prevents a green gate.  An empty input set is
also exit 2: absence of evidence is never evidence of health.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hil_common as hc


def expand_inputs(patterns):
    paths = []
    for pattern in patterns:
        if os.path.isdir(pattern):
            hits = sorted(
                os.path.join(root, name)
                for root, _dirs, files in os.walk(pattern)
                for name in files
                if name.lower().endswith(".json")
            )
        elif any(ch in pattern for ch in "*?["):
            hits = sorted(glob.glob(pattern))
        else:
            hits = [pattern]
        for hit in hits:
            absolute = os.path.abspath(hit)
            if os.path.isfile(absolute) and absolute not in paths:
                paths.append(absolute)
    return paths


def case_counts(cases):
    counts = {status: 0 for status in hc.STATUSES}
    for case in cases or []:
        status = case.get("status")
        if status in counts:
            counts[status] += 1
    return counts


def load_documents(paths):
    results, invalid, skipped = [], [], []
    for path in paths:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError) as exc:
            invalid.append({"file": path, "error": str(exc)[:200]})
            continue
        if not isinstance(doc, dict) or doc.get("kind") not in hc.KINDS:
            skipped.append(
                {
                    "file": path,
                    "kind": doc.get("kind") if isinstance(doc, dict) else None,
                    "reason": "not a gate result",
                }
            )
            continue
        results.append({"file": path, "doc": doc})
    return results, invalid, skipped


def build_markdown(summary):
    lines = []
    lines.append("# Pulsr USB HIL summary")
    lines.append("")
    verdict = summary["verdict"]
    lines.append("- Verdict: **%s**" % verdict)
    lines.append("- Gate green: %s" % ("yes" if summary["green"] else "no"))
    lines.append("- Generated: %s" % summary["generatedAt"])
    lines.append("- Build: %s" % summary["build"])
    counts = summary["counts"]
    lines.append(
        "- Results: %d (pass %d, fail %d, blocked %d, error %d)"
        % (counts["results"], counts["pass"], counts["fail"], counts["blocked"], counts["error"])
    )
    if summary["reason"]:
        lines.append("- Reason: %s" % summary["reason"])
    lines.append("")
    lines.append("## Results")
    lines.append("")
    if summary["results"]:
        lines.append("| File | Kind | Status | Reason | Cases |")
        lines.append("| :--- | :--- | :--- | :--- | :--- |")
        for item in summary["results"]:
            lines.append(
                "| %s | %s | %s | %s | %d |"
                % (
                    item["file"],
                    item["kind"],
                    item["status"],
                    item["reason"] or "-",
                    item["caseCount"],
                )
            )
    else:
        lines.append("_No gate result files found._")
    lines.append("")

    if summary["failures"]:
        lines.append("## Failures")
        lines.append("")
        lines.append("| File | Kind | Case | Reason | Detail |")
        lines.append("| :--- | :--- | :--- | :--- | :--- |")
        for item in summary["failures"]:
            lines.append(
                "| %s | %s | %s | %s | %s |"
                % (item["file"], item["kind"], item.get("case") or "-",
                   item.get("reason") or "-", (item.get("detail") or "-").replace("|", "\\|"))
            )
        lines.append("")

    if summary["blocked"]:
        lines.append("## Blocked (hardware gates not met)")
        lines.append("")
        lines.append("| File | Kind | Reason | Detail |")
        lines.append("| :--- | :--- | :--- | :--- |")
        for item in summary["blocked"]:
            lines.append(
                "| %s | %s | %s | %s |"
                % (item["file"], item["kind"], item.get("reason") or "-",
                   (item.get("detail") or "-").replace("|", "\\|"))
            )
        lines.append("")
        lines.append("_Blocked is not a pass: no device evidence was produced for these gates._")
        lines.append("")

    if summary["invalid"]:
        lines.append("## Unreadable evidence")
        lines.append("")
        for item in summary["invalid"]:
            lines.append("- `%s`: %s" % (item["file"], item["error"]))
        lines.append("")

    if summary["skipped"]:
        lines.append("## Skipped inputs")
        lines.append("")
        for item in summary["skipped"]:
            lines.append("- `%s` (kind=%s): %s" % (item["file"], item["kind"], item["reason"]))
        lines.append("")

    lines.append("## Case detail (non-pass)")
    lines.append("")
    rows = 0
    for case in summary["caseDetails"]:
        lines.append(
            "- `%s` / `%s`: %s (%s)"
            % (case["kind"], case.get("id"), case.get("status"), case.get("reason") or "-")
        )
        rows += 1
    if rows == 0:
        lines.append("- _No non-pass cases recorded._")
    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="analyze_results.py", description="Aggregate HIL result JSONs into a markdown + JSON summary."
    )
    parser.add_argument("inputs", nargs="+", help="result JSON paths, directories or globs")
    parser.add_argument("--out", default=os.path.join(hc.repo_root(), "scratch", "hil", "summary.md"),
                        help="markdown output path (default: %(default)s)")
    parser.add_argument("--json-out", default=None,
                        help="summary JSON path (default: <out stem>.json)")
    parser.add_argument("--build", default=None, help="override build label in the summary")
    args = parser.parse_args(argv)

    json_out = args.json_out or os.path.splitext(os.path.abspath(args.out))[0] + ".json"
    paths = expand_inputs(args.inputs)
    results, invalid, skipped = load_documents(paths)

    failures, blocked_entries, case_details = [], [], []
    counts = {status: 0 for status in hc.STATUSES}
    counts["results"] = len(results)
    for item in results:
        doc = item["doc"]
        status = doc.get("status")
        if status in counts:
            counts[status] += 1
        per_case = case_counts(doc.get("cases"))
        item["caseCount"] = len(doc.get("cases") or [])
        item["caseCounts"] = per_case
        item["kind"] = doc.get("kind")
        item["status"] = status
        item["reason"] = doc.get("reason")
        item["cases"] = doc.get("cases") or []
        item["build"] = doc.get("build")
        item["generatedAt"] = doc.get("generatedAt")
        item["blockers"] = doc.get("blockers") or []
        for case in item["cases"]:
            if case.get("status") == "pass":
                continue
            case_details.append(
                {
                    "kind": item["kind"],
                    "id": case.get("id"),
                    "status": case.get("status"),
                    "reason": case.get("reason") or case.get("detail"),
                }
            )

        failing_cases = [case for case in item["cases"] if case.get("status") in ("fail", "error")]
        for case in failing_cases:
            failures.append(
                {
                    "file": os.path.basename(item["file"]),
                    "kind": item["kind"],
                    "case": case.get("id"),
                    "reason": case.get("reason") or case.get("detail"),
                    "detail": case.get("detail"),
                }
            )
        if status in ("fail", "error") and not failing_cases:
            detail = None
            if item["blockers"]:
                detail = item["blockers"][0].get("detail")
            failures.append(
                {
                    "file": os.path.basename(item["file"]),
                    "kind": item["kind"],
                    "case": None,
                    "reason": item["reason"] or status,
                    "detail": detail,
                }
            )

        if status == "blocked":
            for entry in item["blockers"] or [{"reason": doc.get("reason")}]:
                blocked_entries.append(
                    {
                        "file": os.path.basename(item["file"]),
                        "kind": item["kind"],
                        "reason": entry.get("reason"),
                        "detail": entry.get("detail"),
                    }
                )

    builds = [item["build"] for item in results if item.get("build") and item["build"] != "unknown"]
    build = args.build or (builds[0] if builds else hc.git_short_sha())

    if failures or invalid:
        green, verdict, reason, exit_code = False, "RED", "one or more hardware gates failed", hc.EXIT_FAIL
    elif blocked_entries or not results:
        green = False
        verdict = "BLOCKED"
        reason = "no hardware evidence" if not results else "one or more gates blocked"
        exit_code = hc.EXIT_BLOCKED_GATE
    else:
        green, verdict, reason, exit_code = True, "GREEN", None, hc.EXIT_OK

    summary = {
        "schemaVersion": hc.SCHEMA_VERSION,
        "kind": "summary",
        "generatedAt": hc.iso_now(),
        "build": build,
        "verdict": verdict,
        "green": green,
        "reason": reason,
        "counts": counts,
        "results": [
            {
                "file": os.path.basename(item["file"]),
                "path": item["file"],
                "kind": item["kind"],
                "status": item["status"],
                "reason": item["reason"],
                "build": item["build"],
                "generatedAt": item["generatedAt"],
                "caseCount": item["caseCount"],
                "caseCounts": item["caseCounts"],
            }
            for item in results
        ],
        "failures": failures,
        "blocked": blocked_entries,
        "caseDetails": case_details,
        "invalid": invalid,
        "skipped": skipped,
    }

    hc.ensure_parent(args.out)
    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(build_markdown(summary))
    hc.ensure_parent(json_out)
    with open(json_out, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(summary, fh, indent=2, ensure_ascii=True)
        fh.write("\n")

    print(
        "summary: %s (results=%d pass=%d fail=%d blocked=%d error=%d) -> %s"
        % (verdict, counts["results"], counts["pass"], counts["fail"], counts["blocked"],
           counts["error"], args.out)
    )
    if invalid:
        print("warning: %d unreadable result file(s)" % len(invalid), file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(hc.run_main(main))
