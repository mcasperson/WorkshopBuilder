# WorkshopBuilder

A Docker image that bundles [OctopusCopilot](https://github.com/mcasperson/OctopusCopilot) with the services it depends on:

* [OctoAISpaceBuilder](https://github.com/mcasperson/OctoAISpaceBuilder), listening on port 8080
* The `fakeapps` mock Argo CD server from [octopus-argocd-gateway](https://github.com/OctopusDeploy/octopus-argocd-gateway) (branch `mattc/mockedargo2`), listening on port 8085
* [Azurite](https://github.com/Azure/Azurite), the Azure Storage emulator, listening on ports 10000 (blob), 10001 (queue) and 10002 (table)

supervisord runs these services in the background. Arguments passed to `docker run` are forwarded to `OctopusCopilot/main.py`.

## Running the image

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export OCTOPUS_CLI_API_KEY=API-...
export OCTOPUS_CLI_SERVER=https://your-instance.octopus.app
export MOCKGIT_API_URL=https://your-mockgit-instance
export MOCKGIT_API_KEY=your-mockgit-api-key

docker run --rm \
  -e ANTHROPIC_API_KEY \
  -e OCTOPUS_CLI_API_KEY \
  -e OCTOPUS_CLI_SERVER \
  -e MOCKGIT_API_URL \
  -e MOCKGIT_API_KEY \
  ghcr.io/mcasperson/workshopbuilder:latest \
  --query "Create an Argo CD Manifest Update project called \"16. Argo CD Manifest Update\" with the slug \"argo-cd-octopub-manifest\" using a Git Connection called \"Mock\" with a random username and the allowed repository \"https://mockgit.octopusdemos.com/*\" in the space \"Scratchpad\""
```

Passing `-e NAME` without a value copies the variable from your shell, which keeps secrets out of your shell history.

The image is published for both `linux/amd64` and `linux/arm64`, so it runs natively on Apple Silicon Macs.

### Required environment variables

| Variable | Description |
| --- | --- |
| `ANTHROPIC_API_KEY` | Claude API key |
| `OCTOPUS_CLI_API_KEY` | Octopus Deploy API key |
| `OCTOPUS_CLI_SERVER` | Octopus Deploy server URL |

The container exits with an error if any of these are missing.

### Optional environment variables

These are set in the image and can be overridden with `-e`:

| Variable | Default |
| --- | --- |
| `ANTHROPIC_MODEL` | `claude-sonnet-5-5` |
| `FUNCTIONS_SERVICE` | `anthropic_functions` |
| `PROJECT_GEN_SERVICE` | `anthropic_project` |
| `APPLICATION_SPACEBUILDER_URL` | `http://localhost:8080` |
| `MOCKARGO_API_URL` | `http://localhost:8085` |
| `MOCKGIT_API_URL` | none; pass it with `-e MOCKGIT_API_URL` |
| `MOCKGIT_API_KEY` | none; pass it with `-e MOCKGIT_API_KEY` |
| `AzureWebJobsStorage` | Connection string for the bundled Azurite instance |

## Building the image

```bash
docker build -t workshopbuilder .
```

The multi-stage `Dockerfile` fetches and builds all three projects, so no local checkouts are needed. The GitHub workflow in `.github/workflows/build.yaml` builds the image and publishes it to `ghcr.io/mcasperson/workshopbuilder`.
