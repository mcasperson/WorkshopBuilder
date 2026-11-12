#!/bin/sh
set -e

missing=0
for var in ANTHROPIC_API_KEY OCTOPUS_CLI_API_KEY OCTOPUS_CLI_SERVER; do
    eval "value=\${$var}"
    if [ -z "$value" ]; then
        echo "ERROR: $var is not set. Pass it with: docker run -e $var ..." >&2
        missing=1
    fi
done
[ "$missing" -eq 0 ] || exit 1

# Start the background services (OctoAISpaceBuilder, octopus-argocd-gateway fakeapps and Azurite)
mkdir -p /var/log/supervisor /var/lib/azurite
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf

# Append PROMPT_SUFFIX (if set and non-empty) to the prompt argument
if [ -n "$PROMPT_SUFFIX" ] && [ "$#" -gt 0 ]; then
    prompt="$1$PROMPT_SUFFIX"
    shift
    set -- "$prompt" "$@"
fi

# Run OctopusCopilot with the arguments passed to the container
cd /app/OctopusCopilot
exec python main.py "$@"
