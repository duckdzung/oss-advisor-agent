# Scoring engine tests

Dependency-free engine; tests use pytest (dev-only).

```bash
cd .claude/skills/oss-advisor/scripts
python3 -m pytest tests/ -v
```

`score.py` itself imports only the Python 3 stdlib. Fixtures in `tests/fixtures/` are
hand-authored `facts.json` documents matching `assets/facts.schema.json`.
