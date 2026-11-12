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

# Append PROMPT_SUFFIX (if set and non-empty) to the value following --query
if [ -n "$PROMPT_SUFFIX" ]; then
    n=$#
    next_is_query=0
    while [ "$n" -gt 0 ]; do
        arg="$1"
        shift
        if [ "$next_is_query" -eq 1 ]; then
            arg="$arg$PROMPT_SUFFIX"
            next_is_query=0
        elif [ "$arg" = "--query" ]; then
            next_is_query=1
        fi
        set -- "$@" "$arg"
        n=$((n - 1))
    done
fi

# Run OctopusCopilot with the arguments passed to the container
cd /app/OctopusCopilot
exec python main.py "$@"
