#!/bin/sh
# Build alertmanager.yml from .env.
# Shift lines (SHIFT_PRIYA=05:00|14:00|routing_key) decide who is called.
# PagerDuty cannot dial a raw phone number: each routing key must belong to a
# service whose escalation policy contains only that person.
set -eu

OUT=/alertmanager/alertmanager.rendered.yml
TZ_NAME=${ALERT_TIMEZONE:-Asia/Kolkata}
slack_channel=${SLACK_CHANNEL-}
slack_url=${SLACK_WEBHOOK_URL-}
default_key=${PAGERDUTY_ROUTING_KEY-}

sq() {
  printf '%s' "$1" | sed "s/'/''/g"
}

valid_time() {
  printf '%s' "$1" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]$'
}

shifts=$(mktemp)
trap 'rm -f "$shifts"' EXIT

env | sed -n 's/^SHIFT_//p' | while IFS= read -r line; do
  name=${line%%=*}
  rest=${line#*=}
  start=${rest%%|*}
  rest=${rest#*|}
  end=${rest%%|*}
  key=${rest#*|}
  name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

  if ! printf '%s' "$name" | grep -Eq '^[a-z][a-z0-9_]*$'; then
    echo "alertmanager: ignoring SHIFT_$name (use letters, numbers, underscore)" >&2
    continue
  fi
  if [ -z "$key" ]; then
    echo "alertmanager: SHIFT_$name has no routing key; that shift will not call" >&2
    continue
  fi
  if ! valid_time "$start" || ! valid_time "$end" || [ "$start" = "$end" ]; then
    echo "alertmanager: SHIFT_$name has invalid hours ($start-$end); expected HH:MM" >&2
    continue
  fi
  printf '%s|%s|%s|%s\n' "$start" "$end" "$name" "$key"
done | sort > "$shifts"

shift_count=$(grep -c . "$shifts" || true)
if [ "$shift_count" -eq 0 ] && [ -z "$slack_url" ] && [ -z "$default_key" ]; then
  echo "alertmanager: no Slack webhook, PagerDuty key, or shift key; alerts will be received but not delivered" >&2
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

{
  echo "global:"
  echo "  resolve_timeout: 5m"
  echo

  if [ "$shift_count" -gt 0 ]; then
    echo "time_intervals:"
    while IFS='|' read -r start end name key; do
      echo "  - name: ${name}"
      echo "    time_intervals:"
      echo "      - location: '${TZ_NAME}'"
      # End is exclusive. A window that passes midnight is two intervals.
      first=$(printf '%s\n%s\n' "$start" "$end" | sort | head -n 1)
      if [ "$first" = "$start" ]; then
        echo "        times:"
        echo "          - start_time: '${start}'"
        echo "            end_time: '${end}'"
      else
        echo "        times:"
        echo "          - start_time: '${start}'"
        echo "            end_time: '24:00'"
        echo "          - start_time: '00:00'"
        echo "            end_time: '${end}'"
      fi
    done < "$shifts"
    echo
  fi

  if [ -n "$slack_url" ]; then
    root=slack
  else
    root=empty
  fi

  echo "route:"
  echo "  receiver: ${root}"
  echo "  group_by: ['alertname', 'environment', 'instance']"
  echo "  group_wait: 30s"
  echo "  group_interval: 5m"
  echo "  repeat_interval: 12h"
  echo "  routes:"

  # One matching shift calls that person only. continue reaches Slack, then stops
  # before the fallback key.
  while IFS='|' read -r start end name key; do
    echo "    - match:"
    echo "        severity: critical"
    echo "      receiver: pd-${name}"
    echo "      active_time_intervals: [${name}]"
    echo "      repeat_interval: 10m"
    if [ -n "$slack_url" ]; then
      echo "      continue: true"
      echo "    - match:"
      echo "        severity: critical"
      echo "      receiver: slack"
      echo "      active_time_intervals: [${name}]"
      echo "      repeat_interval: 10m"
    fi
  done < "$shifts"

  if [ -n "$default_key" ]; then
    echo "    - match:"
    echo "        severity: critical"
    echo "      receiver: pd-default"
    echo "      repeat_interval: 10m"
    if [ -n "$slack_url" ]; then
      echo "      continue: true"
    fi
  fi

  if [ -n "$slack_url" ]; then
    echo "    - match:"
    echo "        severity: critical"
    echo "      receiver: slack"
    echo "      repeat_interval: 10m"
    echo "    - match:"
    echo "        severity: warning"
    echo "      receiver: slack"
    echo "      repeat_interval: 12h"
  fi

  echo
  echo "receivers:"
  if [ -n "$slack_url" ]; then
    echo "  - name: slack"
    echo "    slack_configs:"
    echo "      - channel: '$(sq "$slack_channel")'"
    echo "        api_url: '$(sq "$slack_url")'"
    echo "        send_resolved: true"
  fi
  if [ "$root" = "empty" ]; then
    echo "  - name: empty"
  fi

  pd_block() {
    echo "  - name: pd-${1}"
    echo "    pagerduty_configs:"
    echo "      - routing_key: '$(sq "$2")'"
    echo "        send_resolved: true"
    echo "        severity: critical"
    echo "        description: '{{ .CommonAnnotations.summary }}'"
    echo "        details:"
    echo "          environment: '{{ .CommonLabels.environment }}'"
    echo "          instance: '{{ .CommonLabels.instance }}'"
    echo "          description: '{{ .CommonAnnotations.description }}'"
  }

  while IFS='|' read -r start end name key; do
    pd_block "$name" "$key"
  done < "$shifts"

  if [ -n "$default_key" ]; then
    pd_block default "$default_key"
  fi
} > "$OUT"

exec /bin/alertmanager --config.file="$OUT" "$@"
