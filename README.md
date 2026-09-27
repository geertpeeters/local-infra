# Local Infrastructure

A set of Docker Compose stacks for local development, testing, and management.

Every service lives in its own directory with its own `docker-compose.yml`, and
all of them join one externally created Docker network, `infra-net`. Traefik sits
in front as the single entry point: services publish no ports (with a few
documented exceptions) and are reached by hostname, e.g. `http://trilium.test`.

## Services

| Stack | Container(s) | Reachable at |
|-------|--------------|--------------|
| **traefik** | `traefik:v3.6` | proxy on `:80`/`:443`, dashboard on `127.0.0.1:8083` |
| **trilium-notes** | TriliumNext | `http://trilium.test` |
| **hermes** | `hermes-agent` + `hermes-webui` | `http://hermes-webui.test`, agent on `127.0.0.1:8642` |
| **omniroute** | `omniroute` + `redis` | `http://omniroute.test` |
| **portainer** | Portainer CE | `http://portainer.test` |
| **homepage** | Homepage dashboard | `http://homepage.test` |
| **opencode** | `opencode serve` | `http://opencode.test` (basic auth) |
| **mcp/trilium** | `triliumnext-mcp` | `127.0.0.1:${TRILIUM_MCP_HTTP_PORT}` only |

The `.hermes` container bind-mounts a host directory outside this repository that
holds multiple profiles. That directory is not version-controlled.

### Where configuration actually lives

The compose files only describe the container. Files that an application reads
at runtime are not in this repository unless noted:

| What | Lives in | In git? |
|------|----------|---------|
| Homepage dashboard layout | `${HOMEPAGE_PERSIST_DIR}/config/services.yaml` | `homepage/services.yaml` is the source, see below |
| Trilium notes | `${TRILIUM_DATA_DIR}` | no |
| Opencode config | `${OPENCODE_PERSIST_DIR}/config` | no |

> **Homepage reads `services.yaml`, not `services.yaml`.** The extension is
> hardcoded in the image, and if the file is missing Homepage silently copies its
> own example config from `/app/src/skeleton` instead of failing, so a wrong
> filename looks like "my changes are ignored". `homepage/services.yaml` in this
> repo is the version-controlled source; symlink it into the mounted directory to
> keep the dashboard in git:
>
> ```bash
> mkdir -p "$HOMEPAGE_PERSIST_DIR/config"
> ln -sfn "$PWD/homepage/services.yaml" "$HOMEPAGE_PERSIST_DIR/config/services.yaml"
> ```

## Prerequisites

- Docker Engine (>= 24.x) with the Compose v2 plugin (`docker compose`)
- GNU Make (optional; every target has a plain `docker compose` equivalent)
- API keys for NVIDIA, OpenAI, etc.

## Setup

```bash
git clone git@github.com:geertpeeters/local-infra.git
cd local-infra
```

Create the central `.env` **one level above the repository root**, then let the
setup script wire up the network and the per-stack symlinks:

```bash
touch ../.env && chmod 600 ../.env
$EDITOR ../.env          # fill in the keys from Environment Variables below
make setup
```

`make setup` is idempotent and never overwrites existing files. It

1. checks that `../.env` exists,
2. creates the external network `infra-net` if it is missing,
3. creates or repairs the `<stack>/.env` symlink that points at `../.env`.

You can do the same by hand:

```bash
docker network create infra-net
```

The `<stack>/.env` symlinks are already committed, so usually only the network is
missing. To recreate one by hand, use a path relative to the stack directory:
`../../.env` for `trilium-notes/`, `../../../.env` for `mcp/trilium/`.

> The `<stack>/.env` entries are symlinks and are intentionally tracked in git,
> so a fresh clone works without extra steps. Never replace one with a real
> file: that is how secrets end up in a commit. `make check` fails if it finds a
> real file instead of a symlink.

## Running Services

The Makefile drives every stack through one generic target. `SVC` is any
directory that contains a `docker-compose.yml`:

```bash
make up    SVC=trilium-notes
make ps    SVC=trilium-notes
make logs  SVC=trilium-notes
make down  SVC=trilium-notes
make help                    # lists all stacks
```

Nested stacks use their path: `make up SVC=mcp/trilium`.

Without Make, pass the file explicitly:

```bash
docker compose -f trilium-notes/docker-compose.yml up -d
docker compose -f trilium-notes/docker-compose.yml logs -f --tail=100
```

Start `traefik` first; the other stacks register their routers with it over the
Docker API, so a router only appears once Traefik is running.

## Stopping and Cleanup

```bash
make down SVC=trilium-notes       # keeps data volumes
make clean SVC=trilium-notes       # also removes the volumes
```

`make clean` is destructive: it deletes the service's persistent data. The
external `infra-net` network is never removed by `down`.

## Validation

```bash
make check
```

`make check` runs `scripts/validate.sh`, which resolves every stack with
`docker compose config` and reports, per stack: YAML/schema errors, a missing or
broken `.env` symlink, unset variables, and whether the stack still joins
`infra-net`. It creates no containers and opens no ports, so it is safe to run
against a running system.

Exit codes: `0` all good, `1` problems found, `2` Docker unavailable.

## Environment Variables

All stacks read the single `.env` one level above the repository root. A variable
marked **required** has no default: `make check` will tell you if it is unset.

| Variable | Stack | Description |
|----------|-------|-------------|
| `HERMES_PERSIST_DIR` | hermes | **required.** Host dir for Hermes state; also the bind device of the `hermes-home` volume. |
| `HERMES_WEBUI_PASSWORD` | hermes | **required.** Password for the Hermes web UI. |
| `NVIDIA_API_KEY` | hermes | NVIDIA API key. |
| `OMNIROUTE_API_KEY` | hermes | Key for Omniroute; also set as `OPENAI_API_KEY`. |
| `OMNIROUTE_PERSIST_DIR` | omniroute | **required.** Host dir for Omniroute data and Redis. |
| `OMNIROUTE_DASHBOARD_PORT` | omniroute | Dashboard port (default `20128`). |
| `OMNIROUTE_API_PORT` | omniroute | API port (default `20129`). |
| `HOMEPAGE_PERSIST_DIR` | homepage | **required.** Host dir for the Homepage config. |
| `PORTAINER_PERSIST_DIR` | portainer | **required.** Host dir for Portainer data. |
| `OPENCODE_PERSIST_DIR` | opencode | **required.** Host dir for data, config and projects. |
| `OPENCODE_REPO_DIR` | opencode | **required.** Absolute path to this repository on the host, mounted at `/workspace/repo`. |
| `OPENCODE_SERVER_USERNAME` | opencode | Basic-auth user (default `opencode`). |
| `OPENCODE_SERVER_PASSWORD` | opencode | **required.** Basic-auth password. |
| `TRILIUM_DATA_DIR` | trilium-notes | **required.** Host dir for the Trilium data directory. |
| `TRILIUM_API_TOKEN` | mcp/trilium | **required.** eAPI token for Trilium. |
| `TRILIUM_MCP_HTTP_PORT` | mcp/trilium | **required.** Host and container port for the MCP server. |
| `UID` / `GID` | hermes | Owner for bind-mounted files (default `1000`). Usually not exported by your shell; set them explicitly if the images need another uid. |

## Troubleshooting

- **`variable is not set`** - add the variable to `../.env`; `make check` lists
  which ones.
- **No router for `*.test` in the Traefik dashboard** - the stack is not joined
  to `infra-net`, or its container never started. Check `make ps SVC=<stack>` and
  `docker network inspect infra-net`.
- **Host not resolving** - add `127.0.0.1 trilium.test portainer.test
  homepage.test opencode.test omniroute.test hermes-webui.test` to
  `/etc/hosts`.
- **Port conflicts** - Traefik owns `:80` and `:443`; stop anything else that
  wants them. The dashboard is on `127.0.0.1:8083`.
- **Permission errors on mounted dirs** - the container runs as `WANTED_UID` /
  `WANTED_GID`; align `UID`/`GID` with the owner of the persist dir.

## Security Notes

This is a local development setup, so some things are deliberately convenient
rather than safe:

- No TLS. Traefik listens on `:443` but no `certificatesResolver` is configured,
  so everything is plain HTTP.
- The Traefik dashboard runs with `api.insecure: true` and is therefore bound to
  `127.0.0.1:8083` only. Do not move that port to `0.0.0.0` without adding auth.
- Trilium has no authentication of its own. Anything that can reach the network
  can reach it. (Homepage does have a built-in gate as of v2.0, but it is not
  enabled here: set `HOMEPAGE_AUTH_ENABLED=true`, `HOMEPAGE_AUTH_SECRET`,
  `HOMEPAGE_EXTERNAL_URL` and `HOMEPAGE_AUTH_PASSWORD` to turn it on.)

## Contributing

Add new services under a dedicated directory with their own `docker-compose.yml`,
join `infra-net`, and expose them through Traefik labels rather than published
ports. Run `make check` before opening a pull request.

## License

MIT License.
