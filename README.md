# oss-advisor-agent

OSS Advisor is a chatbot that helps teams evaluate and choose open-source libraries with more confidence instead of relying on gut feel.  
Main stack: **FastAPI + Chainlit + LangChain**, deployed on GreenNode AgentBase.

## Purpose

This agent helps teams:

- decide whether a package is safe to adopt
- compare multiple libraries in the same category
- consider replacing custom code with a maintained library

## Use cases

- `Evaluate a named package`: asks questions like “Is fastify safe to add for our new API gateway?”
- `Discover and compare candidates`: asks questions like “What is the best Python HTTP client library for async microservices?”
- `Assess replacing raw code with a library`: asks questions like “Is there a maintained library for this retry-with-exponential-backoff utility?”

The agent scores packages across signals such as health, security, adoption, compatibility, and licensing, then returns a clear verdict like `adopt`, `adopt-with-caution`, or `avoid`.

## Architecture

```text
Container (port 8080)
├── FastAPI
│   ├── GET /health   -> health check
│   └── /*            -> Chainlit chat UI
└── LangChain ReAct Agent
    ├── evaluate_package
    ├── discover_and_compare
    └── audit_manifest
```

## Requirements

- Python 3.11+
- `bash`, `curl`, `jq`
- GreenNode IAM Service Account

## Run locally

```bash
cd oss-advisor-agent
python3.11 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# fill in LLM_API_KEY, LLM_BASE_URL, LLM_MODEL

python main.py
```

Open `http://localhost:8080` to use the UI, or check health with:

```bash
curl http://localhost:8080/health
```

## Run with Docker

The build context must be the root `su-ba-gent/` directory:

```bash
docker build -f oss-advisor-agent/Dockerfile -t oss-advisor-agent .
docker run -p 8080:8080 --env-file oss-advisor-agent/.env oss-advisor-agent
```

After the container starts, open `http://localhost:8080`.

## Deploy to AgentBase

```bash
/agentbase-deploy
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `LLM_API_KEY` | Yes | API key for the LLM provider |
| `LLM_BASE_URL` | Yes | Base URL for the LLM API, OpenAI-compatible |
| `LLM_MODEL` | Yes | Model name, for example `gemini-2.5-flash`, `gpt-4o`, `qwen/qwen3-5-27b` |
| `OSS_ADVISOR_DIR` | No | Path to the oss-advisor directory, default `/app` |
| `GREENNODE_CLIENT_ID` | No | GreenNode IAM client ID |
| `GREENNODE_CLIENT_SECRET` | No | GreenNode IAM client secret |
