import importlib.util, os, io, json
import pytest

_HERE = os.path.dirname(__file__)
_spec = importlib.util.spec_from_file_location("render", os.path.join(_HERE, "..", "render.py"))
render = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(render)

def _load(name):
    with open(os.path.join(_HERE, "fixtures", name)) as fh:
        return json.load(fh)

def test_render_single_contains_name_and_verdict():
    out = render.render(_load("result.single.json"))
    assert "com.zaxxer:HikariCP" in out
    assert "ADOPT" in out.upper()
    assert "89" in out                      # overall score shown
    assert "Health" in out and "Overall" in out  # header columns

def test_render_array_ranks_by_overall_desc():
    out = render.render(_load("result.array.json"))
    # higher overall package should appear before the lower one
    assert out.index("HikariCP") < out.index("commons-dbcp")
    assert "AVOID" in out.upper()
    assert "Abandoned" in out               # risk surfaced

def test_render_footer_has_confidence_and_profile():
    out = render.render(_load("result.single.json"))
    assert "confidence" in out.lower()
    assert "balanced" in out

def test_main_missing_file_exits():
    with pytest.raises(SystemExit):
        render.main(["--results", "/no/such/file.json"])

def test_render_empty_returns_header():
    out = render.render([])
    assert isinstance(out, str)
    assert "Health" in out and "Overall" in out
