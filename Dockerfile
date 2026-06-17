# Build context must be su-ba-gent/ (parent of this directory).
# Build command (from su-ba-gent/):
#   docker build -f oss-advisor-agent/Dockerfile -t oss-advisor-agent .
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl jq \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY oss-advisor-agent/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy agent application files
COPY oss-advisor-agent/main.py .
COPY oss-advisor-agent/agent.py .
COPY oss-advisor-agent/chainlit_app.py .
COPY oss-advisor-agent/scripts /app/scripts
COPY oss-advisor-agent/assets /app/assets
COPY oss-advisor-agent/docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV OSS_ADVISOR_DIR=/app
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "main.py"]
