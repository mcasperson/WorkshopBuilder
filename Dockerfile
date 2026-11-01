FROM python:3.11-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends supervisor \
    && rm -rf /var/lib/apt/lists/*

# OctopusCopilot source and Python dependencies
WORKDIR /app/OctopusCopilot
COPY OctopusCopilot/ .
RUN python -m venv /app/venv \
    && /app/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /app/venv/bin/pip install --no-cache-dir -r requirements.txt

# Prebuilt Go binaries
COPY bin/octoaispacebuilder /usr/local/bin/octoaispacebuilder
COPY bin/fakeapps /usr/local/bin/fakeapps

COPY docker/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/octoaispacebuilder /usr/local/bin/fakeapps

ENV PATH="/app/venv/bin:$PATH" \
    APPLICATION_SPACEBUILDER_URL="http://localhost:8080" \
    MOCKARGO_API_URL="http://localhost:8085" \
    FUNCTIONS_SERVICE="anthropic_functions" \
    ANTHROPIC_MODEL="claude-sonnet-5-5" \
    PROJECT_GEN_SERVICE="anthropic_project"

# Arguments passed to "docker run <image> ..." are forwarded to main.py
ENTRYPOINT ["/entrypoint.sh"]
CMD []
