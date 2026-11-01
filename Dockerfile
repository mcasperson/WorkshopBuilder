# syntax=docker/dockerfile:1

# Build OctoAISpaceBuilder
FROM golang:1.25 AS spacebuilder
WORKDIR /src
ADD https://github.com/mcasperson/OctoAISpaceBuilder.git .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/octoaispacebuilder cmd/web/main.go

# Build the fakeapps server from octopus-argocd-gateway
FROM golang:1.26 AS fakeapps
WORKDIR /src
ADD https://github.com/OctopusDeploy/octopus-argocd-gateway.git#mattc/mockedargo2 .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/fakeapps ./cmd/fakeapps

# Install Azurite (requires Node.js 22+)
FROM node:22-bookworm-slim AS azurite
ARG AZURITE_VERSION=3.37.0
RUN npm install --prefix /opt/azurite --omit=dev azurite@${AZURITE_VERSION}

FROM python:3.11-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends supervisor libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# OctopusCopilot source and Python dependencies
WORKDIR /app/OctopusCopilot
ADD https://github.com/mcasperson/OctopusCopilot.git .
RUN python -m venv /app/venv \
    && /app/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /app/venv/bin/pip install --no-cache-dir -r requirements.txt

COPY --from=spacebuilder /out/octoaispacebuilder /usr/local/bin/octoaispacebuilder
COPY --from=fakeapps /out/fakeapps /usr/local/bin/fakeapps
COPY --from=azurite /usr/local/bin/node /usr/local/bin/node
COPY --from=azurite /opt/azurite /opt/azurite

COPY docker/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PATH="/app/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    APPLICATION_SPACEBUILDER_URL="http://localhost:8080" \
    MOCKARGO_API_URL="http://localhost:8085" \
    FUNCTIONS_SERVICE="anthropic_functions" \
    ANTHROPIC_MODEL="claude-sonnet-5-5" \
    PROJECT_GEN_SERVICE="anthropic_project" \
    AzureWebJobsStorage="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;QueueEndpoint=http://127.0.0.1:10001/devstoreaccount1;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;"

# Arguments passed to "docker run <image> ..." are forwarded to main.py
ENTRYPOINT ["/entrypoint.sh"]
CMD []
