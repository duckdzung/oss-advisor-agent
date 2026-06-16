#!/usr/bin/env python3
"""Render OSS Advisor result JSON into an aligned CLI table. Stdlib only."""
import argparse
import json
import sys

CRIT_ORDER = ["health", "adoption", "security", "stability", "compatibility", "licensing"]
CRIT_HEAD = ["Health", "Adopt", "Sec", "Stab", "Compat", "Lic"]
VERDICT_LABEL = {"adopt": "ADOPT", "adopt-with-caution": "CAUTION", "avoid": "AVOID"}


def _cell(score):
    return "  - " if score is None else "%4.0f" % score


def _name(r):
    c = r.get("coordinates", {})
    n = c.get("name", "?")
    v = c.get("version")
    return "%s@%s" % (n, v) if v else n


def render(data):
    rows = data if isinstance(data, list) else [data]
    rows = sorted(rows, key=lambda r: (r.get("overall") is None, -(r.get("overall") or 0)))

    name_w = max([len("Package")] + [len(_name(r)) for r in rows])
    widths = [max(len(h), 4) for h in CRIT_HEAD]
    overall_w = 7
    verdict_w = 8
    header = (["Package".ljust(name_w)]
              + [h.rjust(widths[i]) for i, h in enumerate(CRIT_HEAD)]
              + ["Overall".rjust(overall_w), "Verdict".rjust(verdict_w)])
    sep = (["-" * name_w]
           + ["-" * widths[i] for i in range(len(CRIT_HEAD))]
           + ["-" * overall_w, "-" * verdict_w])
    lines = ["  ".join(header), "  ".join(sep)]

    for r in rows:
        crit = r.get("criteria", {})
        cells = [_name(r).ljust(name_w)]
        cells += [_cell((crit.get(k) or {}).get("score")).rjust(widths[i]) for i, k in enumerate(CRIT_ORDER)]
        ov = r.get("overall")
        cells.append((("%5.1f" % ov) if ov is not None else "   - ").rjust(overall_w))
        cells.append(VERDICT_LABEL.get(r.get("verdict", ""), "?").rjust(verdict_w))
        lines.append("  ".join(cells))

    # Per-package risks + recommendation
    detail = []
    for r in rows:
        risks = r.get("risks", [])
        if risks or r.get("recommendation"):
            detail.append("")
            detail.append("%s — %s" % (_name(r), VERDICT_LABEL.get(r.get("verdict", ""), "?")))
            if r.get("recommendation"):
                detail.append("  %s" % r["recommendation"])
            for risk in risks:
                detail.append("  • %s" % risk)

    # Footer (use first row's profile + a confidence summary)
    confidences = sorted({r.get("confidence", "?") for r in rows})
    profile = rows[0].get("profile", "?") if rows else "?"
    footer = ["", "profile: %s   confidence: %s" % (profile, ", ".join(confidences))]

    return "\n".join(lines + detail + footer) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description="Render OSS Advisor result JSON as a table")
    parser.add_argument("--results", default="-", help="path to result JSON ('-' for stdin)")
    args = parser.parse_args(argv)
    try:
        if args.results == "-":
            data = json.load(sys.stdin)
        else:
            with open(args.results) as fh:
                data = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        sys.exit("render: %s" % e)
    sys.stdout.write(render(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
