# Local Infrastructure

A set of Docker Compose stacks for local development, testing, and management.

Every service lives in its own directory with its own `docker-compose.yml`. They
all join one externally created Docker network, `infra-net`, and Traefik is the
single entry point: services are reached by hostname, e.g. `http://trilium.test`.
Three stacks are the exception to "no published ports", all on `127.0.0.1` only:
the Hermes agent API (`:8642`), the Trilium MCP server (`${TRILIUM_MCP_HTTP_PORT}`)
and the Traefik dashboard (`:8083`). Traefik itself owns `:80` and `:443`.

Each stack has its own README with the details. This file covers the parts that
are shared by all of them.

## Repository layout

```
.
├── Makefile                 optional shortcuts (you do not need it)
├── scripts/                 setup.sh, validate.sh, backup.sh
├── traefik/                 reverse proxy, owns :80 and :443
├── trilium-notes/           note-taking, single source of truth
├── hermes/                  AI agent + web UI
├── omniroute/               API gateway + redis
├── portainer/               Docker management UI
├── homepage/                dashboard
├── opencode/                opencode server
└── mcp/
    └── trilium/             MCP server for Trilium
```

## Services

| Stack | Container(s) | Reachable at | Own README |
|-------|--------------|--------------|------------|
| **traefik** | `traefik` | proxy on `:80`/`:443`, dashboard on `127.0.0.1:8083` | [traefik/README.md](traefik/README.md) |
| **trilium-notes** | `trilium` | `http://trilium.test` | [trilium-notes/README.md](trilium-notes/README.md) |
| **hermes** | `hermes-agent` + `hermes-webui` | `http://hermes-webui.test`, agent on `127.0.0.1:8642` | [hermes/README.md](hermes/README.md) |
| **omniroute** | `omniroute` + `omniroute-redis` | `http://omniroute.test` | [omniroute/README.md](omniroute/README.md) |
| **portainer** | `portainer` | `http://portainer.test` | [portainer/README.md](portainer/README.md) |
| **homepage** | `homepage` | `http://homepage.test` | [homepage/README.md](homepage/README.md) |
| **opencode** | `opencode` | `http://opencode.test` | [opencode/README.md](opencode/README.md) |
| **mcp/trilium** | `trilium-mcp` | `127.0.0.1:${TRILIUM_MCP_HTTP_PORT}` only | [mcp/trilium/README.md](mcp/trilium/README.md) |

## Prerequisites

- Docker Engine 24 or newer, with the Compose v2 plugin. Check both with
  `docker --version` and `docker compose version`; if the second one errors, your
  Docker is too old or Compose v1 is still installed.
- A Git client, and free disk for several gigabytes of images. The first run
  pulls them all.
- An NVIDIA API key, but only if you intend to run the Hermes agent against
  NVIDIA. Everything else runs without any third-party account.

No Makefile required. Everything below is plain `docker compose`.

## Setup

Steps 1 to 7 are the complete first run; everything after this section is
reference material you only need when something breaks. Allow 10 to 15 minutes,
most of it downloading images on the first run.

### 1. Get the code

```bash
git clone git@github.com:geertpeeters/local-infra.git
cd local-infra
```

Stay in this directory for the rest of the setup: step 2 writes the location of
this checkout into the configuration.

### 2. Create the central `.env`

Every stack reads the **same** `.env`, and it lives **one level above the
repository** - outside Git, on purpose, so a secret can never land in a commit.
(The per-stack `.env` files that Compose also needs are symlinks to it; see
[The `.env` symlinks](#the-env-symlinks) below.)

Create the file and fill in the paths and the owner IDs. This block is executed
by your shell, which is why `$HOME` and `$(id -u)` are expanded into real values
instead of being stored as literal text:

```bash
touch ../.env
cat >> ../.env <<EOF
HERMES_PERSIST_DIR=$HOME/data/hermes
TRILIUM_DATA_DIR=$HOME/data/trilium
OMNIROUTE_PERSIST_DIR=$HOME/data/omniroute
PORTAINER_PERSIST_DIR=$HOME/data/portainer
HOMEPAGE_PERSIST_DIR=$HOME/data/homepage
OPENCODE_PERSIST_DIR=$HOME/data/opencode
OPENCODE_REPO_DIR=$PWD
TRILIUM_MCP_HTTP_PORT=8081
UID=$(id -u)
GID=$(id -g)
EOF
chmod 600 ../.env
```

Run that block **once**. A second run appends duplicate keys, and which one wins
is not worth reasoning about.

Three things about those values:

- **Paths must be absolute.** Compose does not expand `~`, so
  `HERMES_PERSIST_DIR=~/data/hermes` creates a directory literally named `~`.
  `OPENCODE_REPO_DIR` is the absolute path of this checkout; `$PWD` just filled it
  in for you.
- **`UID` and `GID` are numbers, not commands.** The `$(id -u)` above is already
  expanded. They decide who owns files inside the Hermes bind mounts, so correct
  values save you a pile of permission errors later.
- **`TRILIUM_MCP_HTTP_PORT` is a port on your machine.** `8081` is a suggestion;
  pick another free one if something already listens there.

Now add the five secrets by hand:

```bash
$EDITOR ../.env
```

| Variable | What to put there |
|----------|-------------------|
| `HERMES_WEBUI_PASSWORD` | a password of your own choosing |
| `OPENCODE_SERVER_PASSWORD` | a password of your own choosing |
| `OMNIROUTE_API_KEY` | the key the agent presents to Omniroute; it must match a key configured in Omniroute itself |
| `NVIDIA_API_KEY` | your NVIDIA API key, or the placeholder `not-yet-set` if you have none yet. The agent will only fail once you actually use it. |
| `TRILIUM_API_TOKEN` | the placeholder `not-yet-set` for now; step 7 replaces it |

Use a placeholder rather than leaving a value empty: an empty value can make
Compose stop with `variable is not set`, and step 6 would blame it on something
else. Also do not use a `$` in these values - Compose expands `${...}` inside
`.env`, so a password containing a dollar sign gets mangled. If you need one
anyway, wrap the value in single quotes.

### 3. Create the data directories

```bash
mkdir -p "$HOME/data/hermes" "$HOME/data/trilium" "$HOME/data/omniroute" \
         "$HOME/data/portainer" "$HOME/data/homepage" "$HOME/data/opencode"
```

Do this yourself even though Docker would create the directories for you: Docker
creates missing bind mounts as **root**, and the applications then cannot write
to their own data. These paths must match the ones in step 2. Note that
`./scripts/setup.sh` does not create them; it handles step 4.

### 4. Create the shared network and the `.env` symlinks

Every stack joins one external Docker network called `infra-net`, and every
stack directory needs its own `.env` symlink pointing at the central file.
`scripts/setup.sh` does both:

```bash
./scripts/setup.sh
```

It is safe to run more than once: a symlink that already works is never
rewritten. If you prefer to do it by hand, it is `docker network create infra-net`
(once) plus one `ln -s ../../.env <stack>/.env` per stack directory - two levels
up for the top-level stacks, three for `mcp/trilium`.

#### The `.env` symlinks

Compose resolves both `${VARIABLES}` and `env_file` relative to the directory
holding the compose file, which is why every stack needs its own `.env` even
though they all read the same central one:

```
trilium-notes/.env  ->  ../../.env          (two levels up: repo root, then out)
mcp/trilium/.env     ->  ../../../.env       (nested stacks need one more)
```

Never replace a symlink with a real file. That is how secrets end up in a
commit. `scripts/validate.sh` fails when it finds a real file instead of a
symlink.

### 5. Make the hostnames resolve

The services are reached by name, such as `http://trilium.test`, so your machine
has to know those names:

```bash
echo "127.0.0.1 trilium.test hermes-webui.test omniroute.test portainer.test homepage.test opencode.test" \
  | sudo tee -a /etc/hosts
```

Skip this and every hostname fails to resolve, so a browser shows a DNS error
instead of your services. Use your LAN address instead of `127.0.0.1` if you also
want to reach them from another device on the network.

### 6. Check the configuration before starting anything

```bash
./scripts/validate.sh
```

This resolves every stack without starting a single container, and names the
variable or file behind each problem. Fix what it reports and run it again -
a minute here beats downloading gigabytes only to hit `variable is not set`.

All eight stacks should come out as `OK` at this point. The MCP server passes
with the `not-yet-set` placeholder from step 2; that is expected, and step 7
replaces it.

### 7. First run

Start Traefik first: it discovers the other containers through the Docker API,
so routers only appear once it is up. Trilium comes before the MCP server for
the same reason.

```bash
docker compose -f traefik/docker-compose.yml up -d
docker compose -f omniroute/docker-compose.yml up -d
docker compose -f trilium-notes/docker-compose.yml up -d
docker compose -f hermes/docker-compose.yml up -d
docker compose -f portainer/docker-compose.yml up -d
docker compose -f homepage/docker-compose.yml up -d
docker compose -f opencode/docker-compose.yml up -d
```

Then check that a container is actually running:

```bash
docker compose -f homepage/docker-compose.yml ps
```

and open <http://homepage.test>. Homepage is a good first check, because it only
works when Traefik, `infra-net` and `/etc/hosts` are all correct at once.

**The MCP server comes last and needs one extra step.** It authenticates against
Trilium with a token that only Trilium itself can create:

1. Open <http://trilium.test> and log in.
2. In the settings, enable the **eAPI** and create a token.
3. Put that token in `../.env` as `TRILIUM_API_TOKEN=<the token>`.
4. Start the server:

```bash
docker compose -f mcp/trilium/docker-compose.yml up -d
```

When it works, these are yours to open:

| Address | What it is |
|---------|------------|
| <http://homepage.test> | dashboard linking all of the below |
| <http://trilium.test> | notes |
| <http://hermes-webui.test> | Hermes agent UI |
| <http://omniroute.test> | API gateway |
| <http://portainer.test> | container management |
| <http://opencode.test> | opencode |
| <http://127.0.0.1:8083> | Traefik dashboard, localhost only |

## Teardown

Stop everything; each stack keeps its data unless you add `-v`:

```bash
for d in traefik trilium-notes hermes omniroute portainer homepage opencode mcp/trilium; do
  docker compose -f "$d/docker-compose.yml" down
done
```

The network can only be removed once nothing is attached to it any more:

```bash
docker network rm infra-net
```

**To delete the data as well** - notes, databases, API keys, the lot - add `-v`
to the `down` above and delete the directories from step 3. That cannot be
undone, so take a backup first if there is anything in there you want to keep:

```bash
./scripts/backup.sh --stop
```

To start over completely: stop everything as above, delete the repository,
delete `../.env`, and work through the setup from step 1 again.

## Running a stack

```bash
# start
docker compose -f trilium-notes/docker-compose.yml up -d

# status, logs, config
docker compose -f trilium-notes/docker-compose.yml ps
docker compose -f trilium-notes/docker-compose.yml logs -f --tail=100
docker compose -f trilium-notes/docker-compose.yml config

# stop (keeps data)
docker compose -f trilium-notes/docker-compose.yml down
```

Nested stacks are addressed by their path, e.g.
`docker compose -f mcp/trilium/docker-compose.yml up -d`.

To destroy a stack's data as well, add `-v`. Note the exception: the `hermes`
stack's `hermes-home` volume is a *named* volume backed by a bind to
`${HERMES_PERSIST_DIR}`, so `-v` removes the volume entry but leaves your host
directory alone.

### Start order

Stacks are not independent. These relations are not expressed in the compose
files, so nothing enforces them:

1. **traefik** first. Routers appear only after Traefik is up, because it
   discovers containers through the Docker API.
2. **omniroute** before **hermes** - the agent points at
   `http://omniroute:20129/v1`.
3. **trilium-notes** before **mcp/trilium** - the MCP server calls the Trilium
   eAPI at `http://trilium:8080/etapi`.

## Validation

```bash
./scripts/validate.sh
```

Resolves every stack with `docker compose config` and reports, per stack: YAML
and schema errors, a missing or broken `.env` symlink, unset variables, whether
the stack still joins `infra-net`, an image without a digest, and a missing
`container_name`. It starts nothing and opens no ports. Exit codes: `0` all
good, `1` problems found, `2` Docker unavailable.

`hermes/docker-compose-org.yml` is skipped as a variant; see
[hermes/README.md](hermes/README.md).

## Image versions

Every image is pinned to a tag **and** a digest, in the form
`image:tag@sha256:...`. The tag is there so a human can read the version; the
digest is what actually decides the bits. A floating `:latest` would let
`docker compose pull` - or a host rebuild - hand you a different application
under the same data directory, and nothing in git would show it.

| Stack | Image | Pinned to |
|-------|-------|-----------|
| traefik | `traefik` | `v3.7` (= v3.7.13) |
| trilium-notes | `triliumnext/trilium` | `v0.106.0` |
| hermes | `nousresearch/hermes-agent` | `v2026.8.13` |
| hermes | `ghcr.io/nesquena/hermes-webui` | `0.52.113` |
| omniroute | `diegosouzapw/omniroute` | `latest` (meaningless tag; the digest is the pin) |
| omniroute | `redis` | `7-alpine` |
| portainer | `portainer/portainer-ce` | `2.45.1` |
| homepage | `ghcr.io/gethomepage/homepage` | `v2.4.0` |
| opencode | `ghcr.io/anomalyco/opencode` | `1.18.32` |

Three things are worth a second look:

- **`ghcr.io/nesquena/hermes-webui:latest` is not the stable release.** It
  currently carries the same digest as `:experimental` and `0.52.379`. Never
  widen this one to `:latest`; read [hermes/README.md](hermes/README.md) for why
  the agent and the web UI must move together.
- **`diegosouzapw/omniroute:latest` is the honest option.** The newest real
  release tag is `1.0.5` from February, while the image tagged `latest` is from
  August. The digest pins the newer build; the tag itself carries no promise.
- **`mcp/trilium` builds from source**, so it has no upstream image to pin. A
  `build --pull` there refreshes the build base, which is the point.

To move a version: change tag and digest in one edit, run
`./scripts/validate.sh`, take a backup, then `up -d`.

## Environment Variables

All stacks read the single `.env` one level above the repository root. A variable
marked **required** has no default. `scripts/validate.sh` lists any that are
unset.

| Variable | Stack | Description |
|----------|-------|-------------|
| `HERMES_PERSIST_DIR` | hermes | **required.** Host dir for Hermes state; also the bind device of the `hermes-home` volume and the parent of `workspace/` and `wiki/`. |
| `HERMES_WEBUI_PASSWORD` | hermes | **required.** Password for the Hermes web UI. |
| `NVIDIA_API_KEY` | hermes | NVIDIA API key for the agent. |
| `OMNIROUTE_API_KEY` | hermes | Key for Omniroute; also passed to the agent as `OPENAI_API_KEY`. |
| `OMNIROUTE_PERSIST_DIR` | omniroute | **required.** Host dir; `data/` and `redis/` are created inside it. |
| `OMNIROUTE_DASHBOARD_PORT` | omniroute | Dashboard port (default `20128`). See the warning below. |
| `OMNIROUTE_API_PORT` | omniroute | API port (default `20129`). See the warning below. |
| `HOMEPAGE_PERSIST_DIR` | homepage | **required.** Host dir; `config/` is created inside it. |
| `PORTAINER_PERSIST_DIR` | portainer | **required.** Host dir for Portainer data. The name is a typo for `PORTAINER`, kept as-is because it is already in the central `.env`; do not "fix" it on one side only. |
| `OPENCODE_PERSIST_DIR` | opencode | **required.** Host dir; `data/`, `config/` and `projects/` are created inside it. |
| `OPENCODE_REPO_DIR` | opencode | **required.** Absolute path to this repository on the host, mounted at `/workspace/repo`. |
| `OPENCODE_SERVER_USERNAME` | opencode | Basic-auth user (default `opencode`). |
| `OPENCODE_SERVER_PASSWORD` | opencode | **required.** Password for the web UI. |
| `TRILIUM_DATA_DIR` | trilium-notes | **required.** Host dir for the Trilium data directory. |
| `TRILIUM_API_TOKEN` | mcp/trilium | **required.** eAPI token for Trilium. |
| `TRILIUM_MCP_HTTP_PORT` | mcp/trilium | **required.** Host *and* container port for the MCP server. |
| `UID` / `GID` | hermes | Owner for bind-mounted files (default `1000`). Usually not exported by your shell; set them explicitly if the images need another uid. |

> **Two variables look configurable but are not.** `OMNIROUTE_DASHBOARD_PORT` is
> read by the container, but the Traefik label hardcodes `20128`. Likewise
> `OMNIROUTE_API_PORT` is read by the container, but `hermes` hardcodes
> `http://omniroute:20129/v1`. Change either one and you break the proxy route or
> the agent, without any error. Leave both at their defaults until the compose
> files use the variables too.

## Where configuration and data actually live

The compose files only describe the container. Everything an application reads
or writes at runtime is outside this repository:

| What | Lives in | In git? |
|------|----------|---------|
| Homepage dashboard layout | `${HOMEPAGE_PERSIST_DIR}/config/services.yaml` | no |
| Homepage settings | `${HOMEPAGE_PERSIST_DIR}/config/settings.yaml` | no |
| Trilium notes | `${TRILIUM_DATA_DIR}` | no |
| Omniroute state | `${OMNIROUTE_PERSIST_DIR}/data` | no |
| Redis persistence | `${OMNIROUTE_PERSIST_DIR}/redis` | no |
| Portainer state | `${PORTAINER_PERSIST_DIR}` | no |
| Opencode data, config, projects | `${OPENCODE_PERSIST_DIR}/{data,config,projects}` | no |
| This repository, inside opencode | mounted from `${OPENCODE_REPO_DIR}` | yes, that is the point |
| Hermes workspace and wiki | `${HERMES_PERSIST_DIR}/{workspace,wiki}` | no |
| Hermes agent state, credentials, sessions | `${HERMES_PERSIST_DIR}` | no |
| Hermes agent source cache | `hermes-agent-src` volume | no |

The only configuration that is version-controlled is the compose files
themselves, plus the tracked `.env` symlinks.

`hermes-home` does not appear as its own state because it is not any: it is
declared as a named volume whose driver is `type: none, o: bind` with
`device: ${HERMES_PERSIST_DIR}`, so its data is the Hermes persist directory. The
one volume that genuinely lives outside any host directory is
`hermes-agent-src`, the agent source cache. Its real name depends on the Compose
project name, which in turn depends on the directory you ran `docker compose`
from, so `scripts/backup.sh` looks it up by label instead of by name.

## Backups

```bash
./scripts/backup.sh              # live copy, no downtime
./scripts/backup.sh --stop       # stop the stacks first, restart them after
./scripts/backup.sh --with-env   # also copy the central .env into the backup
```

Each run writes a new timestamped directory, so an older backup is never
overwritten:

```
<BACKUP_ROOT>/<UTC timestamp>/
├── hermes.tar.gz            <- ${HERMES_PERSIST_DIR}
├── trilium-notes.tar.gz     <- ${TRILIUM_DATA_DIR}
├── omniroute.tar.gz         <- ${OMNIROUTE_PERSIST_DIR}   (data/ and redis/)
├── portainer.tar.gz         <- ${PORTAINER_PERSIST_DIR}
├── homepage.tar.gz          <- ${HOMEPAGE_PERSIST_DIR}
├── opencode.tar.gz          <- ${OPENCODE_PERSIST_DIR}
├── hermes-agent-src.tar.gz  <- hermes-agent-src volume
├── centrale.env             <- only with --with-env
└── MANIFEST.txt             <- host, the images that were configured, sha256s
```

`BACKUP_ROOT` defaults to `backups/` next to the central `.env`; override it in
the environment. The directory is created `0700` and every file in it `0600`,
because `hermes.tar.gz` and the `.env` contain credentials.

**Use `--stop` for anything you intend to restore.** Trilium's database is SQLite
and Redis rewrites `dump.rdb` while it runs, so a live copy can catch either
half-written. `--stop` stops the stateful stacks, takes the copy, and restarts
exactly the ones that were running. Without it the script still runs, but warns
that the result is best treated as a rough snapshot.

To restore one stack:

```bash
docker compose -f trilium-notes/docker-compose.yml down
tar -xzf /path/to/backup/<timestamp>/trilium-notes.tar.gz -C <target-parent-dir>
docker compose -f trilium-notes/docker-compose.yml up -d
```

The archive is built with a relative path, so it unpacks into the directory you
name rather than into an absolute path on the new host. The agent source volume
is restored the same way, into a volume you just created:

```bash
docker volume create <project>_hermes-agent-src
docker run --rm -v <project>_hermes-agent-src:/dst -v /path/to/backup:/src:ro \
  alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc \
  tar -xzf /src/hermes-agent-src.tar.gz -C /dst
```

That is the same pinned helper image `scripts/backup.sh` uses, so a restore
cannot silently pull a different Alpine than the one that made the archive.

## Troubleshooting

Start here in most cases: `./scripts/validate.sh` names the variable or the file
behind most problems without starting anything.

- **`variable is not set`** - add the variable to `../.env`;
  `./scripts/validate.sh` lists which ones.
- **No router for `*.test` in the Traefik dashboard** - the stack is not joined
  to `infra-net`, or its container never started. Check `ps` for the stack and
  `docker network inspect infra-net`.
- **Host not resolving** - the `/etc/hosts` line from step 5 is missing. Without
  it a browser shows a DNS error rather than your service. Re-run that command.
- **Permission errors on mounted dirs** - the hermes containers run as
  `WANTED_UID` / `WANTED_GID`; set `UID` and `GID` in `../.env` to the numbers
  `id -u` and `id -g` report, and make sure the data directories from step 3 are
  owned by you rather than by root.
- **A directory was created as root, or named `~`** - that is a path that was not
  absolute, or a directory Docker created for you. Fix the value in `../.env`,
  delete the wrong directory and re-create it yourself as in step 3.
- **Port conflicts** - Traefik owns `:80` and `:443`; stop anything else that
  wants them. The dashboard is on `127.0.0.1:8083`.
- **A stack behaves as if its config is ignored** - see the per-stack README;
  Homepage in particular silently falls back to its own example config.
- **The MCP server starts but every request fails** - `TRILIUM_API_TOKEN` is
  empty, or was copied with trailing whitespace. Generate a new token in Trilium
  and set it again, then restart the stack.
- **A version bump went wrong** - stop guessing. Take a backup first next time
  (`./scripts/backup.sh --stop`), then roll back by restoring the stack's
  `tar.gz` and pinning the previous digest.

## Security Notes

This is a local development setup, so some things are deliberately convenient
rather than safe.

- **No TLS.** Traefik listens on `:443` but no `certificatesResolver` is
  configured, so all hostnames are plain HTTP.
- **The Traefik dashboard has no auth.** It runs with `api.insecure: true` and is
  therefore bound to `127.0.0.1:8083` only. Do not move that port to `0.0.0.0`.
- **Nothing authenticates at the proxy level.** The Hermes web UI relies on
  `HERMES_WEBUI_PASSWORD` and Trilium on its own login, but Traefik adds no
  authentication in front of either, so both are reachable by anything on the
  network that knows the hostname.
- **Homepage's built-in auth is not enabled.** v2.0 can do password or OIDC; it
  is off here, so anything on the network can read the dashboard.
- **Portainer mounts the Docker socket read-write** and receives the entire
  central `.env` as its environment. Both are equivalent to root access on the
  host.
- **Five stacks receive the whole `.env`** via `env_file`, including keys they do
  not need: `hermes`, `omniroute`, `portainer`, `trilium-notes` and `mcp/trilium`.
  Only `homepage`, `opencode` and `traefik` are spared. Every `.env` key is
  therefore readable inside all five containers.

## Contributing

Add new services under a dedicated directory with their own `docker-compose.yml`,
a `README.md` describing purpose, ports, volumes, variables and dependencies,
and a tracked `.env` symlink. Join `infra-net` and expose the service through
Traefik labels rather than published ports. Pin new images by tag *and* digest
(see [Image versions](#image-versions)), and run `./scripts/validate.sh` before
opening a pull request.

## License

MIT License.
