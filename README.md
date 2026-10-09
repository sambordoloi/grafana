# grafana

## Configure PagerDuty

Critical alerts (CPU, memory, or disk above 85%) open a PagerDuty incident and place a phone call. Warning alerts (above 75% and below 85%) do not call. Prometheus sends alerts to the local Alertmanager at `alertmanager:9093`.

One PagerDuty account covers the team. Each person is a user on that account. A user can store more than one phone number, and a high-urgency notification rule decides which numbers ring.

To ring only the person on shift, give each person their own PagerDuty service. Alertmanager cannot dial a phone number by itself. It sends the alert to one service, and that service's escalation policy decides who is called.

### Shifts

Shifts are set in `dcgrafana/.env`. Copy `dcgrafana/.env.example` to `dcgrafana/.env` if that file does not exist. Do not commit `.env`.

```
ALERT_TIMEZONE=Asia/Kolkata
SHIFT_PRIYA=05:00|14:00|priya-integration-key
SHIFT_RAHUL=14:00|22:00|rahul-integration-key
SHIFT_NIGHT=22:00|05:00|night-integration-key
```

`SHIFT_PRIYA=05:00|14:00|...` calls only Priya from 5:00 to 14:00. Add a `SHIFT_NAME` line for each other block. Times are 24-hour in `ALERT_TIMEZONE`. A block that passes midnight, such as `22:00|05:00`, is allowed. Windows should not overlap.

`PAGERDUTY_ROUTING_KEY` is used only when the current time matches no shift. Leave it blank to place no call outside the shifts.

Change a roster by editing the hours or the key in `.env`, then restart Alertmanager:

```bash
docker compose -f dcgrafana/docker-compose.yaml up -d alertmanager
```

### One service per person

1. In PagerDuty, create a service named for that person, for example `Priya`.
2. On the service escalation policy, add only that user.
3. On the user profile, add the phone number and a phone notification rule for **high-urgency** incidents.
4. On the service, add an **Events API v2** integration and copy the Integration Key.
5. Paste the key into that person's `SHIFT_` line in `dcgrafana/.env`.
6. Restart Alertmanager.

Slack is optional. Set `SLACK_CHANNEL` and `SLACK_WEBHOOK_URL` in the same file to also receive a Slack message. Leave either value blank to skip Slack. If Slack, the fallback key, and every shift key are blank, Alertmanager accepts alerts and does not deliver them.
