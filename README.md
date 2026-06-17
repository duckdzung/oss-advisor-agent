# oss-advisor-agent

OSS Advisor chatbot — đánh giá thư viện open-source qua giao diện Chainlit.  
Stack: **FastAPI + Chainlit + LangChain**, deployed trên GreenNode AgentBase.

## Architecture

```
Container (port 8080)
├── FastAPI
│   ├── GET /health          → AgentBase health check
│   └── /*                   → Chainlit chat UI
└── LangChain ReAct Agent
    ├── evaluate_package     → UC1: score một package
    ├── discover_and_compare → UC2: so sánh nhiều candidates
    └── audit_manifest       → UC4: audit toàn bộ manifest
```

## Prerequisites

- Python 3.11+
- `bash`, `curl`, `jq` (cho oss-advisor scripts)
- GreenNode IAM Service Account

## Local Setup

```bash
cd oss-advisor-agent
python3.11 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# Điền LLM_API_KEY, LLM_BASE_URL, LLM_MODEL vào .env
```

Chạy local:
```bash
python main.py
# Mở http://localhost:8080 để dùng UI Chainlit
# Health check: curl http://localhost:8080/health
```

## Build & Run Docker

Build context phải là thư mục `su-ba-gent/` (parent). Scripts và assets được include từ source code:

```bash
# Từ su-ba-gent/
docker build -f oss-advisor-agent/Dockerfile -t oss-advisor-agent .
docker run -p 8080:8080 --env-file oss-advisor-agent/.env oss-advisor-agent
```

Mở http://localhost:8080 để dùng chatbot.

## Deploy to AgentBase

```bash
/agentbase-deploy
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `LLM_API_KEY` | Yes | API key cho LLM provider |
| `LLM_BASE_URL` | Yes | Base URL của LLM API (OpenAI-compatible) |
| `LLM_MODEL` | Yes | Model name (e.g. `gemini-2.5-flash`, `gpt-4o`, `qwen/qwen3-5-27b`) |
| `OSS_ADVISOR_DIR` | No | Path đến thư mục oss-advisor (default: `/app`) |
| `GREENNODE_CLIENT_ID` | No | GreenNode IAM client ID |
| `GREENNODE_CLIENT_SECRET` | No | GreenNode IAM client secret |
