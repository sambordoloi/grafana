#!/bin/sh
# Render alertmanager.yml with Slack settings from the environment.
# prom/alertmanager does not expand env vars. envsubst is used when present;
# the image's shell is used otherwise. Secrets stay out of the tracked file.
set -eu

TEMPLATE=/etc/alertmanager/alertmanager.yml.template
OUT=/alertmanager/alertmanager.rendered.yml

if command -v envsubst >/dev/null 2>&1; then
  envsubst '${SLACK_CHANNEL} ${SLACK_WEBHOOK_URL}' < "$TEMPLATE" > "$OUT"
else
  chan=$(printf '%s' "${SLACK_CHANNEL-}" | sed 's/[\\&|]/\\&/g')
  hook=$(printf '%s' "${SLACK_WEBHOOK_URL-}" | sed 's/[\\&|]/\\&/g')
  sed \
    -e "s|\${SLACK_CHANNEL}|${chan}|g" \
    -e "s|\${SLACK_WEBHOOK_URL}|${hook}|g" \
    "$TEMPLATE" > "$OUT"
fi

exec /bin/alertmanager --config.file="$OUT" "$@"
