# Nostr Spam Fighter

Content classification and moderation for Nostr. V1 scans `kind:30023` articles,
matches URLs against category blocklists, publishes NIP-32 labels under
`space.pareto.content`, and exposes a protected naddr moderation API.

## Stack

Phoenix, LiveView, Ecto, PostgreSQL, Oban, Req. Relay I/O via
[`nostr_access`](https://hex.pm/packages/nostr_access); crypto via
[`nostr_elixir`](https://github.com/twenty-eighty/nostr_elixir).

## Setup

```bash
docker compose up -d postgres   # Postgres on localhost:5434
mix setup
INITIAL_ADMIN_PUBKEY=<hex> mix nsf.bootstrap_admin
mix phx.server
```

Admin login is NIP-07 / NIP-98 at `/login`. No passwords.

## Deploy on Render

This repo includes a [Render Blueprint](https://render.com/docs/blueprint-spec) at `render.yaml`.

1. Push the repo to GitHub or GitLab.
2. In Render, choose **New → Blueprint** and select the repo.
3. When prompted, set `INITIAL_ADMIN_PUBKEY` (64-character hex) and `MODERATION_NSEC`.

The blueprint creates a private Postgres database and a Docker web service. First boot migrates the schema and creates the bootstrap admin. Open `/login` and sign in with a NIP-07 extension.

## API

```
Authorization: Bearer nsf_<prefix>_<secret>
GET /api/v1/articles/:naddr/moderation
POST /api/v1/articles/moderation/check
```

`blacklisted` is tri-state: `true`, `false`, or `null` (unknown/pending).

## Secrets

Never store the moderation nsec in Postgres or in a file under the app.
Set `MODERATION_NSEC` (bech32 `nsec1…` or 64-character hex). API-key secrets
are shown once and stored as hashes only.

## Health

`GET /health` and `GET /health/ready` (database + policy cache). Ready does not
require relays to be online.

## Future kinds

Add a `Scanner.Processor` (see `Kind1Processor`) and include the kind in
`ingest_kinds`. Policy, labels, and the article API stay unchanged.
