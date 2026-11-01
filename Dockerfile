# syntax=docker/dockerfile:1

# The Go stages run on the build machine's native platform and cross-compile for linux/amd64.

# Build OctoAISpaceBuilder
FROM --platform=$BUILDPLATFORM golang:1.25 AS spacebuilder
WORKDIR /src
ADD https://github.com/mcasperson/OctoAISpaceBuilder.git .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/octoaispacebuilder cmd/web/main.go

# Build the Octopus Terraform provider used by OctoAISpaceBuilder
FROM --platform=$BUILDPLATFORM golang:1.26 AS provider
WORKDIR /src
ADD https://github.com/OctopusDeploy/terraform-provider-octopusdeploy.git#main .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/terraform-provider-octopusdeploy

# Assemble the OctoAISpaceBuilder runtime files: OPA policies, the OPA and tofu binaries, and the provider.
# The provider version must match the one OctoAISpaceBuilder expects (terraformProviderVersion in its source).
FROM spacebuilder AS spacebuilder-functions
ARG PROVIDER_VERSION=1.18.2
ADD --chmod=755 https://github.com/open-policy-agent/opa/releases/download/v1.3.0/opa_linux_amd64 /src/functions/binaries/opa_linux_amd64
ADD --chmod=755 https://github.com/OctopusSolutionsEngineering/opentofu/releases/download/v1.10.6.3/tofu /src/functions/binaries/tofu
COPY --from=provider --chmod=755 /out/terraform-provider-octopusdeploy \
    /src/functions/provider/registry.opentofu.org/octopusdeploy/octopusdeploy/${PROVIDER_VERSION}/linux_amd64/terraform-provider-octopusdeploy_v${PROVIDER_VERSION}

# Build the fakeapps server from octopus-argocd-gateway
FROM --platform=$BUILDPLATFORM golang:1.26 AS fakeapps
WORKDIR /src
ADD https://github.com/OctopusDeploy/octopus-argocd-gateway.git#mattc/mockedargo2 .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/fakeapps ./cmd/fakeapps

# Install Azurite (requires Node.js 22+)
FROM --platform=linux/amd64 node:22-bookworm-slim AS azurite
ARG AZURITE_VERSION=3.37.0
RUN npm install --prefix /opt/azurite --omit=dev azurite@${AZURITE_VERSION}

# The image only supports amd64, because opa, tofu and the Go binaries are built for amd64
FROM --platform=linux/amd64 python:3.11-slim-bookworm

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
COPY --from=spacebuilder-functions /src/functions /opt/spacebuilder/functions
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
