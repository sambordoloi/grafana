# grafana

## Configure PagerDuty

Critical alerts (CPU, memory, or disk above 85%) open a PagerDuty incident. PagerDuty places a phone call when your user has a phone notification rule for high-urgency incidents. Warning alerts (above 75% and below 85%) are sent as warning and do not call.

Prometheus sends alerts to the local Alertmanager at `alertmanager:9093`.

1. In PagerDuty, create a service.
2. On that service, add an **Events API v2** integration.
3. Copy the Integration Key.
4. In `dcgrafana/.env`, set `PAGERDUTY_ROUTING_KEY` to that key. Copy `dcgrafana/.env.example` to `dcgrafana/.env` if the file does not exist yet. Do not commit `.env`.
5. On your PagerDuty user profile, add a phone notification rule for **high-urgency** incidents.
6. Restart Alertmanager so it reloads `.env`:

   ```bash
   docker compose -f dcgrafana/docker-compose.yaml up -d alertmanager
   ```

Slack is optional. Set `SLACK_CHANNEL` and `SLACK_WEBHOOK_URL` in the same file to also receive a Slack message. Leave either value blank to skip that channel. If both PagerDuty and Slack are blank, Alertmanager accepts alerts and does not deliver them.
