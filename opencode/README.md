# opencode

The opencode server, reachable from the browser. It can edit this repository,
which is why the repo itself is mounted into the container.

## Access

`http://opencode.test` via Traefik. No port is published on the host.

## Start

```bash
docker compose -f opencode/docker-compose.yml up -d
docker compose -f opencode/docker-compose.yml logs -f --tail=100
```

## The image needs patching at startup

The base image ships without `git`, which opencode needs. Instead of baking a
custom image, the compose file neutralises the entrypoint and installs git on the
fly:

```yaml
entrypoint: []
command: >
  sh -c "command -v git >/dev/null 2>&1 || apk add --no-cache git;
  exec opencode serve --hostname 0.0.0.0 --port 4096"
```

Consequence: **the first start of every new container pulls and installs git**,
which needs network access and adds a few seconds. An offline start fails.

## Volumes

| What | Where in container |
|------|--------------------|
| `${OPENCODE_PERSIST_DIR}/data` | `/home/opencode/.local` |
| `${OPENCODE_PERSIST_DIR}/config` | `/home/opencode/.config/opencode` |
| `${OPENCODE_PERSIST_DIR}/projects` | `/workspace` (this is `working_dir`) |
| `${OPENCODE_REPO_DIR}` | `/workspace/repo` - **this repository**, live |

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCODE_PERSIST_DIR` | yes | Host dir holding `data/`, `config/` and `projects/`. |
| `OPENCODE_REPO_DIR` | yes | Absolute path to this repository on the host. |
| `OPENCODE_SERVER_PASSWORD` | yes | Password for the web UI. |
| `OPENCODE_SERVER_USERNAME` | no | Defaults to `opencode`. |

## Dependencies

- **Traefik** for the `opencode.test` route.
- `${OPENCODE_REPO_DIR}` must point at a real clone. The container writes to it
  as the non-root `opencode` user, so a mismatched owner shows up as permission
  errors on files it tries to edit.

## Gotchas

- **`opencode/volumes/` is not mounted.** The compose file mounts
  `${OPENCODE_PERSIST_DIR}/...`, so nothing in `volumes/` ever reaches the
  container. The `volumes/config/opencode.jsonc` stub that used to sit there has
  been deleted; edit the real config under `${OPENCODE_PERSIST_DIR}/config`
  instead. The empty `volumes/data` and `volumes/projects` directories are
  leftovers too, and git ignores them only because it cannot track empty dirs.
- **This repository is mounted read-write**, so opencode can commit to it. That
  is the intent, but it means a web session has write access to your working
  tree.
- **Check that the basic-auth variables actually apply.** They are set from
  `OPENCODE_SERVER_USERNAME` and `OPENCODE_SERVER_PASSWORD`; if the server does
  not honour them, the UI is reachable unauthenticated by anyone on the network.
  Worth verifying once, then removing the "basic auth" claim from the main
  README if it does not hold.
- A commented-out `ports` block publishes `127.0.0.1:4096` for debugging.
- The image is pinned to a version plus a digest. The shell-patch still means
  that every *new* image version gets a fresh `apk add` of git and ripgrep, so
  bumping the pin costs a rebuild of that layer.
