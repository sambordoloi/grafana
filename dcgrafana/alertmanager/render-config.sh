#!/bin/sh
# Render alertmanager.yml from the environment.
# prom/alertmanager does not expand env vars. A receiver is included only when
# its secret is set, so an empty Slack webhook or PagerDuty key does not
# prevent Alertmanager from starting.
set -eu

TEMPLATE=/etc/alertmanager/alertmanager.yml.template
OUT=/alertmanager/alertmanager.rendered.yml

slack_channel=${SLACK_CHANNEL-}
slack_url=${SLACK_WEBHOOK_URL-}
pagerduty_key=${PAGERDUTY_ROUTING_KEY-}

if [ -z "$slack_url" ] && [ -z "$pagerduty_key" ]; then
  echo "alertmanager: SLACK_WEBHOOK_URL and PAGERDUTY_ROUTING_KEY are empty; alerts will be received but not delivered" >&2
  cat > "$OUT" <<'EOF'
global:
  resolve_timeout: 5m

route:
  receiver: empty
  group_by: ['alertname', 'environment', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h

receivers:
  - name: empty
EOF
  exec /bin/alertmanager --config.file="$OUT" "$@"
fi

if command -v envsubst >/dev/null 2>&1; then
  envsubst '${SLACK_CHANNEL} ${SLACK_WEBHOOK_URL} ${PAGERDUTY_ROUTING_KEY}' < "$TEMPLATE" > "$OUT"
else
  chan=$(printf '%s' "$slack_channel" | sed 's/[\\&|]/\\&/g')
  hook=$(printf '%s' "$slack_url" | sed 's/[\\&|]/\\&/g')
  key=$(printf '%s' "$pagerduty_key" | sed 's/[\\&|]/\\&/g')
  sed \
    -e "s|\${SLACK_CHANNEL}|${chan}|g" \
    -e "s|\${SLACK_WEBHOOK_URL}|${hook}|g" \
    -e "s|\${PAGERDUTY_ROUTING_KEY}|${key}|g" \
    "$TEMPLATE" > "$OUT"
fi

# Drop an integration whose secret was left blank so Alertmanager can start
# with only the one that is configured.
if [ -z "$slack_url" ]; then
  awk '
    /^    slack_configs:/ { skip=1; next }
    skip && /^    pagerduty_configs:/ { skip=0 }
    skip { next }
    { print }
  ' "$OUT" > "${OUT}.tmp"
  mv "${OUT}.tmp" "$OUT"
fi

if [ -z "$pagerduty_key" ]; then
  awk '
    /^    pagerduty_configs:/ { skip=1; next }
    skip { next }
    { print }
  ' "$OUT" > "${OUT}.tmp"
  mv "${OUT}.tmp" "$OUT"
fi

exec /bin/alertmanager --config.file="$OUT" "$@"
