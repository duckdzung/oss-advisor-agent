import json
import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv
from langchain.agents import create_agent
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI

load_dotenv()

# Resolve oss-advisor directory: env var → current directory (standalone)
_default_dir = Path(__file__).parent
OSS_ADVISOR_DIR = Path(os.environ.get("OSS_ADVISOR_DIR", str(_default_dir))).resolve()
SCRIPTS_DIR = OSS_ADVISOR_DIR / "scripts"


def _run_bash(script_name: str, args: list[str], stdin: str | None = None) -> str:
    """Run an oss-advisor bash script, return stdout."""
    cmd = ["bash", str(SCRIPTS_DIR / script_name)] + args
    result = subprocess.run(
        cmd,
        input=stdin,
        capture_output=True,
        text=True,
        timeout=120,
        env={**os.environ, "OSS_ADVISOR_DIR": str(OSS_ADVISOR_DIR)},
    )
    if result.returncode != 0 and not result.stdout.strip():
        raise RuntimeError(result.stderr.strip() or f"{script_name} failed (exit {result.returncode})")
    return result.stdout


def _run_python(script_name: str, args: list[str], stdin: str | None = None) -> str:
    """Run an oss-advisor Python script, return stdout."""
    cmd = [sys.executable, str(SCRIPTS_DIR / script_name)] + args
    result = subprocess.run(
        cmd,
        input=stdin,
        capture_output=True,
        text=True,
        timeout=30,
        env={**os.environ, "OSS_ADVISOR_DIR": str(OSS_ADVISOR_DIR)},
    )
    if result.returncode != 0 and not result.stdout.strip():
        raise RuntimeError(result.stderr.strip() or f"{script_name} failed (exit {result.returncode})")
    return result.stdout


def _score_and_render(facts_json: str, profile: str) -> tuple[str, dict]:
    """Run score.py + render.py on a facts JSON string. Returns (table, result_dict)."""
    score_args = ["--facts", "-", "--profile", profile,
                  "--assets-dir", str(OSS_ADVISOR_DIR / "assets")]
    result_json = _run_python("score.py", score_args, stdin=facts_json)
    table = _run_python("render.py", [], stdin=result_json)
    result = json.loads(result_json)
    return table, result


def _verdict_summary(result: dict) -> str:
    verdict = result.get("verdict", "?")
    overall = result.get("overall")
    confidence = result.get("confidence", "?")
    risks = result.get("risks", [])
    lines = [f"Verdict: **{verdict.upper()}**  |  Overall: {overall}/100  |  Confidence: {confidence}"]
    for r in risks:
        lines.append(f"• {r}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# LangChain Tools
# ---------------------------------------------------------------------------

@tool
def evaluate_package(ecosystem: str, name: str, version: str = "", profile: str = "balanced") -> str:
    """Evaluate a single open-source package and return a scored report.

    Args:
        ecosystem: Package ecosystem — one of: npm, pypi, maven, go, cargo, nuget.
        name: Package name (e.g. "express", "requests", "com.zaxxer:HikariCP").
        version: Specific version string. Leave empty for latest.
        profile: Scoring profile — balanced (default), security-first, or adoption-first.

    Returns:
        Formatted table with scores per criterion plus adopt/caution/avoid verdict.
    """
    try:
        args = ["--ecosystem", ecosystem, "--name", name]
        if version:
            args += ["--version", version]
        facts_json = _run_bash("collect.sh", args)
        table, result = _score_and_render(facts_json, profile)
        return f"{table}\n{_verdict_summary(result)}"
    except Exception as exc:
        return f"Error evaluating {name}: {exc}"


@tool
def discover_and_compare(
    ecosystem: str,
    query: str,
    candidates: str,
    profile: str = "balanced",
) -> str:
    """Discover and compare candidate packages for a stated need.

    Call this when the user wants to find the best library for a task, or compare
    multiple options. Propose 3–6 candidate names yourself before calling this tool.

    Args:
        ecosystem: Package ecosystem — npm, pypi, maven, go, cargo, nuget.
        query: Short description of the need (e.g. "HTTP client", "SQL ORM").
        candidates: JSON array of candidate package names you propose from your knowledge,
                    e.g. '["requests","httpx","aiohttp"]'.
        profile: Scoring profile — balanced (default), security-first, adoption-first.

    Returns:
        Ranked comparison table with verdicts for each candidate.
    """
    try:
        discover_out = _run_bash(
            "discover.sh",
            ["--ecosystem", ecosystem, "--query", query, "--candidates", candidates],
        )
        pkgs = json.loads(discover_out)
        if not pkgs:
            return "No candidates found."

        results = []
        for pkg in pkgs:
            eco = pkg.get("ecosystem", ecosystem)
            nm = pkg.get("name", "")
            ver = pkg.get("version") or ""
            args = ["--ecosystem", eco, "--name", nm]
            if ver:
                args += ["--version", ver]
            try:
                facts_json = _run_bash("collect.sh", args)
                score_args = ["--facts", "-", "--profile", profile,
                              "--assets-dir", str(OSS_ADVISOR_DIR / "assets")]
                result_json = _run_python("score.py", score_args, stdin=facts_json)
                results.append(json.loads(result_json))
            except Exception as e:
                results.append({"coordinates": {"ecosystem": eco, "name": nm, "version": ver},
                                "overall": None, "verdict": "avoid", "risks": [str(e)],
                                "criteria": {}, "confidence": "low", "profile": profile})

        array_json = json.dumps(results)
        table = _run_python("render.py", [], stdin=array_json)
        return table
    except Exception as exc:
        return f"Error during discovery: {exc}"


@tool
def audit_manifest(file_path: str, profile: str = "balanced") -> str:
    """Audit all dependencies in a manifest file and return a risk-sorted report.

    Supports: package.json, requirements.txt, pom.xml.

    Args:
        file_path: Absolute or relative path to the manifest file.
        profile: Scoring profile — balanced (default), security-first, adoption-first.

    Returns:
        Risk-sorted table (avoid/caution at top) with verdict per dependency.
    """
    try:
        path = Path(file_path).expanduser().resolve()
        if not path.exists():
            return f"File not found: {file_path}"

        pkgs_json = _run_bash("audit.sh", ["--file", str(path)])
        pkgs = json.loads(pkgs_json)
        if not pkgs:
            return "No dependencies found in the manifest."

        results = []
        for pkg in pkgs:
            eco = pkg.get("ecosystem", "")
            nm = pkg.get("name", "")
            ver = pkg.get("version") or ""
            args = ["--ecosystem", eco, "--name", nm]
            if ver:
                args += ["--version", ver]
            try:
                facts_json = _run_bash("collect.sh", args)
                score_args = ["--facts", "-", "--profile", profile,
                              "--assets-dir", str(OSS_ADVISOR_DIR / "assets")]
                result_json = _run_python("score.py", score_args, stdin=facts_json)
                results.append(json.loads(result_json))
            except Exception as e:
                results.append({"coordinates": {"ecosystem": eco, "name": nm, "version": ver},
                                "overall": None, "verdict": "avoid", "risks": [str(e)],
                                "criteria": {}, "confidence": "low", "profile": profile})

        array_json = json.dumps(results)
        table = _run_python("render.py", [], stdin=array_json)

        avoid = sum(1 for r in results if r.get("verdict") == "avoid")
        caution = sum(1 for r in results if r.get("verdict") == "adopt-with-caution")
        adopt = sum(1 for r in results if r.get("verdict") == "adopt")
        summary = f"\nSummary: {adopt} adopt · {caution} caution · {avoid} avoid (out of {len(results)} packages)"
        return table + summary
    except Exception as exc:
        return f"Error auditing {file_path}: {exc}"


# ---------------------------------------------------------------------------
# Agent factory
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """You are OSS Advisor, an expert open-source dependency analyst.
You help engineers evaluate libraries before adoption, compare candidates, and audit manifests.

## Your capabilities
- **evaluate_package** — score a single named package across 6 criteria and return adopt/caution/avoid
- **discover_and_compare** — propose and compare candidate libraries for a stated need
- **audit_manifest** — parse a pom.xml / package.json / requirements.txt and score every dependency

## Rules
- Never invent data. Only report what the tools return.
- Always cite the verdict and confidence level.
- When ecosystem is ambiguous, ask the user before calling a tool.
- For discover_and_compare, always propose 3–6 candidate names from your own knowledge before calling the tool.
- Present results clearly: show the table, then narrate the top risks and your recommendation.
- Profile defaults to balanced; offer security-first or adoption-first when relevant.
"""


def build_agent():
    llm_model = os.environ.get("LLM_MODEL", "")
    llm_base_url = os.environ.get("LLM_BASE_URL", "")
    llm_api_key = os.environ.get("LLM_API_KEY", "")

    if not all([llm_model, llm_base_url, llm_api_key]):
        raise ValueError(
            "LLM_MODEL, LLM_BASE_URL, and LLM_API_KEY must be set. "
            "Run /agentbase-llm to get a GreenNode AIP key."
        )

    llm = ChatOpenAI(model=llm_model, base_url=llm_base_url, api_key=llm_api_key)
    return create_agent(llm, tools=[evaluate_package, discover_and_compare, audit_manifest],
                        system_prompt=SYSTEM_PROMPT)
