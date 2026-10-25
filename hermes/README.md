# hermes

The AI agent (`hermes-agent`) and its web UI (`hermes-webui`). The agent talks to
models through Omniroute.

## Access

| What | Where |
|------|-------|
| Web UI | `http://hermes-webui.test` via Traefik |
| Agent API | `127.0.0.1:8642` on the host only |

## Start

```bash
docker compose -f hermes/docker-compose.yml up -d
docker compose -f hermes/docker-compose.yml logs -f --tail=100
```

`hermes-webui` has `depends_on: hermes-agent`, so Compose starts the agent
first.

## Containers

### hermes-agent

`nousresearch/hermes-agent:v2026.8.13`, runs `gateway run`.

- `HERMES_HOME=/home/hermes/.hermes`
- `HERMES_UID` / `HERMES_GID` from `UID` / `GID`, default `1000`
- `OPENAI_API_BASE=http://omniroute:20129/v1` and
  `OPENAI_API_KEY=${OMNIROUTE_API_KEY}` - the agent reaches models **through
  Omniroute**, not directly
- `NVIDIA_API_KEY`

### hermes-webui

`ghcr.io/nesquena/hermes-webui:0.52.113`.

- Listens on `0.0.0.0:8787`, routed by Traefik as `hermes-webui.test`
- `HERMES_API_URL=http://hermes-agent:8642`
- `HERMES_WEBUI_PASSWORD` gates the UI
- `WANTED_UID` / `WANTED_GID` from `UID` / `GID`, default `1000`
- `WIKI_PATH=/wiki`, `HERMES_WEBUI_AUTO_INSTALL=1`, `HERMES_SKIP_CHMOD=1`

## Volumes

| Volume | Mounted at | Notes |
|--------|------------|-------|
| `hermes-home` | `/home/hermes/.hermes` and `/home/hermeswebui/.hermes` | named volume, but backed by a bind to `${HERMES_PERSIST_DIR}` |
| `hermes-agent-src` | `/opt/hermes` and `/home/hermeswebui/.hermes/hermes-agent` (read-only) | the second mount is shared between both containers |
| `${HERMES_PERSIST_DIR}/workspace` | `/workspace` | only in the web UI |
| `${HERMES_PERSIST_DIR}/wiki` | `/wiki` | only in the web UI |

The `hermes-home` volume is declared with `driver_opts: {type: none, o: bind,
device: ${HERMES_PERSIST_DIR}}`. That is a bind dressed up as a named volume, so
it inherits the usual bind-mount rule: **the host directory must already exist**,
or creating the volume fails.

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `HERMES_PERSIST_DIR` | yes | Host dir for all Hermes state, workspace and wiki. |
| `HERMES_WEBUI_PASSWORD` | yes | Password for the web UI. |
| `OMNIROUTE_API_KEY` | no | Key for Omniroute; also used as `OPENAI_API_KEY`. |
| `NVIDIA_API_KEY` | no | NVIDIA API key. |
| `UID` / `GID` | no | Owner for bind-mounted files, default `1000`. |

## Dependencies

- **Traefik** for the web UI route.
- **Omniroute** for the agent. `OPENAI_API_BASE` points at
  `http://omniroute:20129/v1`, so with Omniroute down the agent has no model
  access. This is not expressed in the compose files.

## Version pairing

The two images are not independent. The web UI's README states that its release
branches are tested against **the matching agent release that existed when the
web UI was released**, and its Docker docs tell you to upgrade both together.
Treat them as one unit.

This repo runs agent `v2026.8.13` with web UI `0.52.113`:

| | Agent | Web UI |
|---|-------|--------|
| Pinned | `v2026.8.13` (13 Aug 2026) | `0.52.113` (14 Aug 2026) |
| Latest available | `v2026.9.24` | `0.52.379` (experimental) |

`0.52.113` is the newest **stable** web UI release, and `v2026.8.13` is the agent
release that was current when it shipped. There is no published test matrix, so
the pairing is derived from the release dates and the stated policy rather than
from a table upstream.

### Do not "upgrade" the web UI to `:latest`

`ghcr.io/nesquena/hermes-webui:latest` currently resolves to the same digest as
`:experimental` and `0.52.379`. The floating tag that looks like the safe default
is the experimental build, which is why the tag is never used here.

### Upgrading to a newer stable pair

Back up first (`./scripts/backup.sh --stop`), then expect the source cache to
get in the way. `hermes-agent-src` holds the agent source, and a `docker pull`
does **not** update it: the volume keeps serving the code it already has, so a
new agent image can end up running old source. Delete it and let the container
recreate it:

```bash
docker compose -f hermes/docker-compose.yml down
docker volume rm <project>_hermes-agent-src
docker compose -f hermes/docker-compose.yml up -d
```

`<project>` is the Compose project name, which follows the directory you ran the
command from: `hermes` from inside `hermes/`, or the repository name when you use
`-f hermes/docker-compose.yml` from the root. Look it up with
`docker volume ls | grep hermes-agent-src` instead of guessing.

`hermes-home` is *not* part of that procedure: it is a bind to
`${HERMES_PERSIST_DIR}` and is left alone.

## Gotchas

- **`20129` is hardcoded** in `OPENAI_API_BASE`. Changing `OMNIROUTE_API_PORT`
  breaks the agent with no error from Docker.
- **`${HERMES_PERSIST_DIR}` must exist** before the first `up`, as explained
  above.
- **`docker-compose-org.yml` is a leftover and does not work.** It is an older
  single-service variant using variables that exist nowhere else:
  `HERMES_HOST_HOME`, `HERMES_WORKSPACE`, `HERMES_WIKI`. An `up` with it stops on
  `variable is not set`. It declares the same `container_name: hermes-webui`, so
  the two can never run at the same time, and `scripts/validate.sh` skips it
  because the filename differs. The image pin inside it was carried along so the
  file does not look maintained; it does not make the file work. Delete it or
  bring it in sync.
- A commented-out `ports` block maps `127.0.0.1:4545:8787`. If you need direct
  access while debugging Traefik, uncomment it.
- Both images are pinned by tag **and** digest; see
  [Version pairing](#version-pairing) before changing either one.
- The web UI receives the **entire** central `.env` through `env_file`, including
  keys it does not need.
