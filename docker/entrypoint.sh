#!/bin/sh
set -e

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set. Pass it with: docker run -e ANTHROPIC_API_KEY ..." >&2
    exit 1
fi

# Start the background services (OctoAISpaceBuilder and octopus-argocd-gateway fakeapps)
mkdir -p /var/log/supervisor
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf

# Run OctopusCopilot with the arguments passed to the container
cd /app/OctopusCopilot
exec python main.py "$@"
