#!/usr/bin/env python3
"""OSS Advisor scoring engine — pure function of (facts, weights) -> result.

Reads a canonical facts.json (see assets/facts.schema.json), normalizes each
sub-signal to 0-100, aggregates to criterion + overall scores, applies hard-fail
overrides and soft flags, and emits result.schema.json. Stdlib only.
"""
import argparse
import json
import math
import os
import sys


def _clamp(x, lo=0.0, hi=100.0):
    return max(lo, min(hi, x))


def recency_decay(x, good, bad):
    """100 at/below `good`, 0 at/above `bad`, linear between."""
    if x <= good:
        return 100.0
    if x >= bad:
        return 0.0
    return _clamp(100.0 * (bad - x) / (bad - good))


def inverse_decay(x, good, bad):
    """Lower is better; identical shape to recency_decay."""
    return recency_decay(x, good, bad)


def log_scale(x, lo, hi):
    """0 at/below `lo`, 100 at/above `hi`, log10-linear between."""
    if x <= lo:
        return 0.0
    if x >= hi:
        return 100.0
    return _clamp(100.0 * (math.log10(x) - math.log10(lo)) / (math.log10(hi) - math.log10(lo)))


def bool_score(b):
    return 100.0 if bool(b) else 0.0


PERMISSIVE = {"MIT", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "ISC", "0BSD", "Unlicense"}
WEAK_COPYLEFT_PREFIX = ("LGPL", "MPL-2.0", "EPL-2.0", "CDDL")
STRONG_COPYLEFT_PREFIX = ("GPL", "AGPL")


def _license_permissiveness(spdx):
    if not spdx:
        return None
    if spdx in PERMISSIVE:
        return 100.0
    if spdx.startswith(WEAK_COPYLEFT_PREFIX):
        return 70.0
    if spdx.startswith(STRONG_COPYLEFT_PREFIX):
        return 30.0
    return None


# Each entry: signal_key -> function(value) -> normalized float OR None to exclude.
# Some signals need osv_queried; those are handled specially in normalize_signal.
def _norm_releases(x):
    return log_scale(x, 0.5, 12)


def _norm_active_maintainers(x):
    if x >= 3:
        return 100.0
    return {2: 70.0, 1: 40.0, 0: 0.0}.get(int(x), 0.0)


def _norm_bus_factor(x):
    if x >= 3:
        return 100.0
    return {2: 65.0, 1: 30.0, 0: 0.0}.get(int(x), 0.0)


def _norm_open_cves(x):
    if x >= 3:
        return 0.0
    return {0: 100.0, 1: 60.0, 2: 40.0}.get(int(x), 0.0)


def _norm_breaking(x):
    if x >= 3:
        return 0.0
    return {0: 100.0, 1: 70.0, 2: 40.0}.get(int(x), 0.0)


def _norm_major_churn(x):
    if x <= 0.5:
        return 100.0
    if x <= 1:
        return 80.0
    if x <= 2:
        return 50.0
    return 20.0


SIMPLE_NORMALIZERS = {
    "health.last_commit_days": lambda v: recency_decay(v, 30, 730),
    "health.releases_per_year": _norm_releases,
    "health.active_maintainers": _norm_active_maintainers,
    "health.bus_factor": _norm_bus_factor,
    "adoption.stars": lambda v: log_scale(v, 50, 50000),
    "adoption.forks": lambda v: log_scale(v, 10, 10000),
    "adoption.downloads_recent": lambda v: log_scale(v, 1000, 10000000),
    "adoption.dependents": lambda v: log_scale(v, 5, 50000),
    "security.scorecard": lambda v: _clamp(v * 10),
    "security.has_security_md": bool_score,
    "security.patch_latency_days": lambda v: inverse_decay(v, 7, 180),
    "stability.semver_compliant": bool_score,
    "stability.breaking_changes_per_year": _norm_breaking,
    "stability.major_version_churn": _norm_major_churn,
    "stability.has_migration_guides": bool_score,
    "compatibility.runtime_constraint_ok": bool_score,
    "compatibility.transitive_conflict_risk": lambda v: _clamp((1 - max(0.0, min(1.0, v))) * 100),
}

# Signals that score even when value is null, IF OSV was queried (clean assumption).
SECURITY_CLEAN_IF_QUERIED = {"security.max_cvss", "security.open_cves"}

CRITERIA = {
    "health": {"last_commit_days": 0.35, "releases_per_year": 0.20,
               "active_maintainers": 0.20, "bus_factor": 0.25},
    "adoption": {"stars": 0.25, "forks": 0.15, "downloads_recent": 0.35, "dependents": 0.25},
    "security": {"max_cvss": 0.30, "open_cves": 0.20, "scorecard": 0.25,
                 "has_security_md": 0.10, "patch_latency_days": 0.15},
    "stability": {"semver_compliant": 0.35, "breaking_changes_per_year": 0.30,
                  "major_version_churn": 0.15, "has_migration_guides": 0.20},
    "compatibility": {"runtime_constraint_ok": 0.50, "transitive_conflict_risk": 0.50},
    "licensing": {"permissiveness": 0.55, "policy_compliant": 0.45},
}


def normalize_signal(key, sig, osv_queried):
    """Return a normalized 0-100 float, or None if the signal is missing/excluded."""
    value = sig.get("value") if isinstance(sig, dict) else None

    if key == "security.max_cvss":
        if value is None:
            return 100.0 if osv_queried else None
        return _clamp(100.0 - value * 10)
    if key == "security.open_cves":
        if value is None:
            return 100.0 if osv_queried else None
        return _norm_open_cves(value)
    if key == "licensing.license":
        return _license_permissiveness(value)
    if key == "licensing.policy_compliant":
        return None if value is None else bool_score(value)

    if value is None:
        return None
    fn = SIMPLE_NORMALIZERS.get(key)
    return fn(value) if fn else None


def score_criterion(name, signals, osv_queried):
    """Aggregate one criterion. `signals` is facts['signals'] (full dict)."""
    weights = CRITERIA[name]
    total = len(weights)
    scored = []         # (normalized, weight)
    out_signals = []
    available_weight = 0.0
    acc = 0.0

    for sub, w in weights.items():
        # Map synthetic 'licensing.permissiveness' to the 'licensing.license' fact.
        fact_key = "licensing.license" if (name == "licensing" and sub == "permissiveness") else "%s.%s" % (name, sub)
        sig = signals.get(fact_key)
        norm = None
        raw_value = None
        citations = []
        present = False
        if sig is not None:
            present = True
            raw_value = sig.get("value")
            citations = sig.get("citations", [])
            norm = normalize_signal(fact_key, sig, osv_queried)
        elif fact_key in SECURITY_CLEAN_IF_QUERIED and osv_queried:
            # OSV queried, no advisory record present at all -> clean
            present = True
            norm = 100.0

        if norm is not None:
            acc += norm * w
            available_weight += w
            scored.append((norm, w))
        if present:
            out_signals.append({"name": sub, "value": raw_value, "normalized": norm, "citations": citations})

    crit_score = (acc / available_weight) if available_weight > 0 else None
    coverage = len(scored) / total if total else 0.0
    return {"score": crit_score, "coverage": coverage, "signals": out_signals}


def compute_overall(criteria, weights):
    acc = 0.0
    wsum = 0.0
    for name, w in weights.items():
        c = criteria.get(name)
        if c and c["score"] is not None:
            acc += c["score"] * w
            wsum += w
    return (acc / wsum) if wsum > 0 else None


def compute_confidence(criteria, weights, osv_queried, degraded):
    if not osv_queried:
        return "low"
    acc = 0.0
    wsum = 0.0
    for name, w in weights.items():
        c = criteria.get(name)
        if c:
            acc += c["coverage"] * w
            wsum += w
    weighted_coverage = (acc / wsum) if wsum > 0 else 0.0
    if weighted_coverage < 0.40:
        return "low"
    if weighted_coverage >= 0.75 and not degraded:
        return "high"
    return "medium"


def _val(signals, key):
    sig = signals.get(key)
    return sig.get("value") if isinstance(sig, dict) else None


def decide_verdict(overall, signals, criteria, confidence):
    """Return (verdict, risks, flags). Hard-fails force 'avoid'."""
    risks = []
    flags = []

    # Hard-fails
    if _val(signals, "security.unpatched_critical") is True:
        risks.append("Unpatched critical vulnerability (CVSS >= 9, no fix available)")
        flags.append("hardfail:unpatched_critical")
    if _val(signals, "licensing.policy_compliant") is False:
        risks.append("License violates configured policy")
        flags.append("hardfail:license_policy")
    lcd = _val(signals, "health.last_commit_days")
    open_cves = _val(signals, "security.open_cves")
    if isinstance(lcd, (int, float)) and lcd > 730 and isinstance(open_cves, (int, float)) and open_cves > 0:
        risks.append("Abandoned (>2y no commits) with open vulnerabilities")
        flags.append("hardfail:abandoned_with_cves")

    if flags:  # any hard-fail
        return "avoid", risks, flags

    if overall is None:
        return "avoid", ["Insufficient data to score"], ["nodata"]
    if overall < 50:
        return "avoid", risks, flags

    # Soft flags
    if _val(signals, "health.bus_factor") == 1:
        risks.append("Single dominant maintainer (bus factor 1)")
        flags.append("soft:bus_factor")
    lic = _val(signals, "licensing.license")
    lvl = _license_permissiveness(lic)
    if lvl is not None and lvl <= 30.0:
        risks.append("Strong-copyleft license — review obligations")
        flags.append("soft:strong_copyleft")
    tcr = _val(signals, "compatibility.transitive_conflict_risk")
    if isinstance(tcr, (int, float)) and tcr >= 0.5:
        risks.append("Elevated transitive-dependency conflict risk")
        flags.append("soft:transitive_conflict")
    if confidence == "low":
        risks.append("Low data confidence — verify manually")
        flags.append("soft:low_confidence")

    if overall >= 75:
        verdict = "adopt-with-caution" if flags else "adopt"
    else:
        verdict = "adopt-with-caution"
    return verdict, risks, flags


def normalize_weights(weights):
    total = sum(weights.values())
    if total <= 0:
        raise ValueError("weights must sum to a positive number")
    return {k: v / total for k, v in weights.items()}


def score(facts, weights, profile_name="custom", generated_at=None):
    weights = normalize_weights(weights)
    signals = facts.get("signals", {})
    osv_queried = bool(_val(signals, "security.osv_queried"))
    degraded = facts.get("sources_degraded", [])

    criteria = {}
    for name in CRITERIA:
        criteria[name] = score_criterion(name, signals, osv_queried)

    overall = compute_overall(criteria, weights)
    confidence = compute_confidence(criteria, weights, osv_queried, degraded)
    verdict, risks, flags = decide_verdict(overall, signals, criteria, confidence)

    recommendation = _templated_recommendation(facts, verdict, overall, risks)

    return {
        "coordinates": facts.get("coordinates", {}),
        "criteria": criteria,
        "overall": round(overall, 1) if overall is not None else None,
        "confidence": confidence,
        "verdict": verdict,
        "risks": risks,
        "flags": flags,
        "recommendation": recommendation,
        "profile": profile_name,
        "generated_at": generated_at,
    }


def _templated_recommendation(facts, verdict, overall, risks):
    name = facts.get("coordinates", {}).get("name", "package")
    headline = {"adopt": "Safe to adopt", "adopt-with-caution": "Adopt with caution",
                "avoid": "Avoid"}[verdict]
    parts = ["%s: %s" % (name, headline)]
    if overall is not None:
        parts.append("(overall %.0f/100)" % overall)
    if risks:
        parts.append("Key risks: " + "; ".join(risks[:3]) + ".")
    return " ".join(parts)


def _load_weights(profile, weights_inline, assets_dir):
    if weights_inline:
        return json.loads(weights_inline), "custom"
    path = os.path.join(assets_dir, "weights.%s.json" % profile)
    if not os.path.exists(path):
        raise SystemExit("Unknown profile '%s' (no %s)" % (profile, path))
    with open(path) as fh:
        data = json.load(fh)
    return data["weights"], data.get("name", profile)


def main(argv=None):
    parser = argparse.ArgumentParser(description="OSS Advisor scoring engine")
    parser.add_argument("--facts", required=True, help="path to facts.json ('-' for stdin)")
    parser.add_argument("--profile", default="default", help="balanced/default | security-first | adoption-first")
    parser.add_argument("--weights", default=None, help="inline JSON weights object, overrides --profile")
    parser.add_argument("--assets-dir", default=os.path.join(os.path.dirname(__file__), "..", "assets"))
    parser.add_argument("--generated-at", default=None, help="ISO timestamp to embed (caller-supplied)")
    args = parser.parse_args(argv)

    try:
        if args.facts == "-":
            facts = json.load(sys.stdin)
        else:
            with open(args.facts) as fh:
                facts = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        raise SystemExit("error: %s" % e)

    profile_key = "default" if args.profile == "balanced" else args.profile
    weights, profile_name = _load_weights(profile_key, args.weights, args.assets_dir)
    result = score(facts, weights, profile_name=profile_name, generated_at=args.generated_at)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
