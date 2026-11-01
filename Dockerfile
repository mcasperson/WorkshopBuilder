# syntax=docker/dockerfile:1

# The image can be built for linux/amd64 or linux/arm64. The Go stages run on the build machine's
# native platform and cross-compile for the target architecture (TARGETARCH).

# Build OctoAISpaceBuilder
FROM --platform=$BUILDPLATFORM golang:1.25 AS spacebuilder
ARG TARGETARCH
WORKDIR /src
ADD https://github.com/mcasperson/OctoAISpaceBuilder.git .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -o /out/octoaispacebuilder cmd/web/main.go

# Build the Octopus Terraform provider used by OctoAISpaceBuilder
FROM --platform=$BUILDPLATFORM golang:1.26 AS provider
ARG TARGETARCH
WORKDIR /src
ADD https://github.com/OctopusDeploy/terraform-provider-octopusdeploy.git#main .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -o /out/terraform-provider-octopusdeploy

# Assemble the OctoAISpaceBuilder runtime files: OPA policies, the OPA and tofu binaries, and the provider.
# The provider version must match the one OctoAISpaceBuilder expects (terraformProviderVersion in its source).
FROM spacebuilder AS spacebuilder-functions
ARG TARGETARCH
ARG PROVIDER_VERSION=1.18.2
ARG OPA_VERSION=1.3.0
ARG TOFU_VERSION=1.10.6
ADD --chmod=755 https://github.com/open-policy-agent/opa/releases/download/v${OPA_VERSION}/opa_linux_${TARGETARCH}_static /src/functions/binaries/opa
RUN curl -fsSL https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz \
    | tar -xz -C /src/functions/binaries tofu
ARG PROVIDER_DIR=/src/functions/provider/registry.opentofu.org/octopusdeploy/octopusdeploy/${PROVIDER_VERSION}
COPY --from=provider --chmod=755 /out/terraform-provider-octopusdeploy \
    ${PROVIDER_DIR}/linux_${TARGETARCH}/terraform-provider-octopusdeploy_v${PROVIDER_VERSION}
# OctoAISpaceBuilder's startup check always looks for the provider in linux_amd64, while tofu loads it
# from the directory matching the platform it runs on. On arm64, point linux_amd64 at linux_arm64.
RUN if [ "$TARGETARCH" != "amd64" ]; then \
        rm -rf ${PROVIDER_DIR}/linux_amd64 && ln -s linux_${TARGETARCH} ${PROVIDER_DIR}/linux_amd64; \
    fi

# Build the fakeapps server from octopus-argocd-gateway
FROM --platform=$BUILDPLATFORM golang:1.26 AS fakeapps
ARG TARGETARCH
WORKDIR /src
ADD https://github.com/OctopusDeploy/octopus-argocd-gateway.git#mattc/mockedargo2 .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -o /out/fakeapps ./cmd/fakeapps

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
