import importlib.util
import os

import pytest

_HERE = os.path.dirname(__file__)
_SCORE_PATH = os.path.join(_HERE, "..", "score.py")
_spec = importlib.util.spec_from_file_location("score", _SCORE_PATH)
score = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(score)


def test_recency_decay_boundaries():
    assert score.recency_decay(10, 30, 730) == 100.0
    assert score.recency_decay(30, 30, 730) == 100.0
    assert score.recency_decay(730, 30, 730) == 0.0
    assert score.recency_decay(1000, 30, 730) == 0.0
    # midpoint between 30 and 730 -> 50
    assert round(score.recency_decay(380, 30, 730), 1) == 50.0


def test_log_scale_boundaries():
    assert score.log_scale(10, 50, 50000) == 0.0     # below lo
    assert score.log_scale(50, 50, 50000) == 0.0
    assert score.log_scale(50000, 50, 50000) == 100.0
    assert score.log_scale(100000, 50, 50000) == 100.0
    mid = score.log_scale(1581, 50, 50000)            # ~geometric midpoint
    assert 48.0 <= mid <= 52.0


def test_inverse_decay_lower_is_better():
    assert score.inverse_decay(3, 7, 180) == 100.0
    assert score.inverse_decay(180, 7, 180) == 0.0


def test_bool_score():
    assert score.bool_score(True) == 100.0
    assert score.bool_score(False) == 0.0


def _sig(value, source="test"):
    return {"value": value, "source": source, "citations": []}


def test_normalize_weights():
    norm = score.normalize_weights({"a": 2, "b": 2})
    assert abs(sum(norm.values()) - 1.0) < 1e-9
    assert norm == {"a": 0.5, "b": 0.5}
    with pytest.raises(ValueError):
        score.normalize_weights({"a": 0})


def test_normalize_signal_known_keys():
    assert score.normalize_signal("health.last_commit_days", _sig(10), osv_queried=False) == 100.0
    assert score.normalize_signal("security.max_cvss", _sig(7.5), osv_queried=True) == 25.0
    assert score.normalize_signal("licensing.license", _sig("Apache-2.0"), osv_queried=False) == 100.0
    assert score.normalize_signal("licensing.license", _sig("GPL-3.0-only"), osv_queried=False) == 30.0
    # unknown license -> None (excluded)
    assert score.normalize_signal("licensing.license", _sig("WEIRD-1.0"), osv_queried=False) is None


def test_security_clean_when_osv_queried():
    # null max_cvss but OSV was queried -> treat as clean (100)
    assert score.normalize_signal("security.max_cvss", _sig(None), osv_queried=True) == 100.0
    # null max_cvss and OSV NOT queried -> excluded
    assert score.normalize_signal("security.max_cvss", _sig(None), osv_queried=False) is None


def test_criterion_score_weighted_mean_of_available():
    signals = {
        "health.last_commit_days": _sig(10),    # -> 100, weight .35
        "health.bus_factor": _sig(1),            # -> 30,  weight .25
        # releases_per_year and active_maintainers missing -> excluded
    }
    result = score.score_criterion("health", signals, osv_queried=False)
    # available weights .35 and .25 renormalize: (100*.35 + 30*.25)/(.60) = 70.83
    assert round(result["score"], 2) == 70.83
    assert round(result["coverage"], 2) == 0.50  # 2 of 4 signals present
    assert len(result["signals"]) == 2


def test_overall_profile_weighted_excludes_empty_criteria():
    criteria = {
        "health": {"score": 80.0, "coverage": 1.0, "signals": []},
        "security": {"score": 60.0, "coverage": 1.0, "signals": []},
        "adoption": {"score": None, "coverage": 0.0, "signals": []},  # excluded
    }
    weights = {"health": 0.5, "security": 0.25, "adoption": 0.25}
    overall = score.compute_overall(criteria, weights)
    # (80*0.5 + 60*0.25) / (0.5 + 0.25) = 73.33
    assert round(overall, 2) == 73.33


def test_confidence_levels():
    weights = {"health": 0.5, "security": 0.5}
    high = {"health": {"score": 9, "coverage": 1.0, "signals": []},
            "security": {"score": 9, "coverage": 0.8, "signals": []}}
    assert score.compute_confidence(high, weights, osv_queried=True, degraded=[]) == "high"
    # osv not queried forces low
    assert score.compute_confidence(high, weights, osv_queried=False, degraded=[]) == "low"
    low = {"health": {"score": 9, "coverage": 0.2, "signals": []},
           "security": {"score": 9, "coverage": 0.2, "signals": []}}
    assert score.compute_confidence(low, weights, osv_queried=True, degraded=[]) == "low"


def test_hard_fail_unpatched_critical_forces_avoid():
    signals = {"security.unpatched_critical": _sig(True)}
    verdict, risks, flags = score.decide_verdict(overall=90.0, signals=signals, criteria={}, confidence="high")
    assert verdict == "avoid"
    assert any("unpatched critical" in r.lower() for r in risks)


def test_hard_fail_license_policy_forces_avoid():
    signals = {"licensing.policy_compliant": _sig(False)}
    verdict, risks, flags = score.decide_verdict(overall=88.0, signals=signals, criteria={}, confidence="high")
    assert verdict == "avoid"
    assert any("policy" in r.lower() for r in risks)


def test_hard_fail_abandoned_with_cves():
    signals = {"health.last_commit_days": _sig(900), "security.open_cves": _sig(2)}
    verdict, risks, flags = score.decide_verdict(overall=70.0, signals=signals, criteria={}, confidence="medium")
    assert verdict == "avoid"
    assert any("abandoned" in r.lower() for r in risks)


def test_soft_flag_bus_factor_downgrades_adopt():
    signals = {"health.bus_factor": _sig(1)}
    verdict, risks, flags = score.decide_verdict(overall=85.0, signals=signals, criteria={}, confidence="high")
    assert verdict == "adopt-with-caution"
    assert any("bus factor" in r.lower() for r in risks)


def test_clean_high_score_adopts():
    verdict, risks, flags = score.decide_verdict(overall=85.0, signals={}, criteria={}, confidence="high")
    assert verdict == "adopt"
    assert risks == []


def test_low_overall_avoids():
    verdict, risks, flags = score.decide_verdict(overall=42.0, signals={}, criteria={}, confidence="medium")
    assert verdict == "avoid"


import json as _json

_FIX = os.path.join(_HERE, "fixtures")


def _load(name):
    with open(os.path.join(_FIX, name)) as fh:
        return _json.load(fh)


_BALANCED = {"health": 0.20, "adoption": 0.15, "security": 0.25,
             "stability": 0.15, "compatibility": 0.10, "licensing": 0.15}


def test_score_healthy_adopts():
    result = score.score(_load("facts.healthy.json"), _BALANCED, profile_name="balanced")
    assert result["verdict"] == "adopt"
    assert result["overall"] >= 75
    assert result["confidence"] == "high"
    assert set(result["criteria"].keys()) == {"health", "adoption", "security", "stability", "compatibility", "licensing"}
    # every emitted signal carries a normalized field (or None) and citations key
    for crit in result["criteria"].values():
        for s in crit["signals"]:
            assert "normalized" in s and "citations" in s


def test_score_risky_avoids_on_hardfail():
    result = score.score(_load("facts.risky.json"), _BALANCED, profile_name="balanced")
    assert result["verdict"] == "avoid"
    assert any("unpatched critical" in r.lower() for r in result["risks"])


def test_score_sparse_low_confidence():
    result = score.score(_load("facts.sparse.json"), _BALANCED, profile_name="balanced")
    assert result["confidence"] == "low"
    assert result["profile"] == "balanced"


def test_profile_switch_is_deterministic_and_reweighted():
    facts = _load("facts.healthy.json")
    sec_weights = {"health": 0.15, "adoption": 0.05, "security": 0.45,
                   "stability": 0.10, "compatibility": 0.10, "licensing": 0.15}
    r1 = score.score(facts, _BALANCED, profile_name="balanced")
    r2 = score.score(facts, _BALANCED, profile_name="balanced")
    assert r1 == r2  # deterministic
    r_sec = score.score(facts, sec_weights, profile_name="security-first")
    # same per-criterion scores (facts unchanged), only overall weighting differs
    assert r1["criteria"]["security"]["score"] == r_sec["criteria"]["security"]["score"]
    assert r1["overall"] != r_sec["overall"] or r1["criteria"]["security"]["score"] == r1["overall"]
