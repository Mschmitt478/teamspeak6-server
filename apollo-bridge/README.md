# ApolloBridge

Text-only bridge from TeamSpeak 6 ServerQuery to OpenClaw/Apollo.

## What it does

- Connects to TeamSpeak 6 SSH ServerQuery.
- Moves the ServerQuery client into `TS_CHANNEL_ID`.
- Registers for channel text events.
- Sends human channel messages into Apollo.
- Posts Apollo's reply back to the TeamSpeak channel.
- Provides small Discordbot-like commands such as `!apollo help`, `!apollo status`, and `!apollo ping`.
- Watches an outbox directory so other local automation can ask ApolloBridge to post proactive messages.

## Local setup

```bash
cd apollo-bridge
cp .env.example .env.local
# edit .env.local if needed
npm start
```

`.env.local` is ignored by the repo root `.gitignore` via `*.local` / `*.env` patterns.

## Required TeamSpeak settings

The TS6 server needs SSH Query enabled, usually on `10022`, restricted by AWS security group and TS query allowlist.

For the current AWS deployment, the query admin password is stored on the EC2 host at:

```bash
/root/teamspeak-query-admin-password
```

ApolloBridge can read it via `TS_QUERY_PASSWORD_COMMAND`, so no password has to be committed locally.

## Usage in TeamSpeak

In the configured Apollo channel, just ask a question:

```text
what are you running on?
```

Commands:

```text
!apollo help
!apollo status
!apollo ping
```

To post proactively from the host, drop a `.txt` file into the outbox:

```bash
echo "Maintenance starts in 10 minutes." | sudo tee /opt/apollo-bridge/outbox/$(date +%s).txt
```

ApolloBridge will post the text and rename the file to `.sent`.

## Notes

- This is intentionally text-only.
- ServerQuery text events are used instead of a TS6 client plugin.
- The bridge ignores messages from the query bot itself.
