# homepage

Dashboard that links the other services together. Configuration lives entirely
outside the repository.

## Access

`http://homepage.test` via Traefik. No port is published on the host.

## Start

```bash
docker compose -f homepage/docker-compose.yml up -d
docker compose -f homepage/docker-compose.yml logs -f --tail=100
```

## Configuration

| What | Where |
|------|-------|
| Dashboard layout | `${HOMEPAGE_PERSIST_DIR}/config/services.yaml` |
| Theme, layout, title | `${HOMEPAGE_PERSIST_DIR}/config/settings.yaml` |
| Custom icons | `${HOMEPAGE_PERSIST_DIR}/config/icons` (not present by default) |

Required variable:

| Variable | Description |
|----------|-------------|
| `HOMEPAGE_PERSIST_DIR` | Host dir; `config/` is created inside it |

`HOMEPAGE_ALLOWED_HOSTS` is hardcoded to `homepage.test` in the compose file.

## The filename must be `services.yaml`

This is the single most common way to get an empty or example dashboard:

- Homepage asks the image for `services.yaml`. **The extension is hardcoded, and
  there is no `.yml` fallback.**
- If that file is missing, Homepage does not fail. It copies its own example
  config from `/app/src/skeleton` and serves that instead, logging only an
  informational line. The symptom is "my changes are ignored", with no error
  anywhere.
- The same applies to `settings.yaml`, `widgets.yaml` and `bookmarks.yaml`.

So the layout of `${HOMEPAGE_PERSIST_DIR}/config` should be:

```
config/
├── services.yaml     <- your dashboard
└── settings.yaml     <- Homepage's own default is fine
```

If both `services.yml` and `services.yaml` are present, the `.yaml` one wins and
the `.yml` one is dead weight. Remove it.

## Dependencies

None. It only renders links, so it can start before the other services.

## Gotchas

- **No automatic service discovery.** The Docker socket is deliberately not
  mounted, so Homepage cannot enumerate containers. Every entry has to be written
  in `services.yaml` by hand. Mounting the socket read-only would enable it, at
  the cost of exposing container metadata.
- **Config is not in git.** `${HOMEPAGE_PERSIST_DIR}/config` lives outside the
  repository, so dashboard changes are not version-controlled. If you want them
  in git, keep a copy in the repository and symlink it into the mounted
  directory; Homepage follows symlinks.
- **No authentication is enabled.** v2.0 supports a password or OIDC gate, but
  it is off here, so anything that can reach the network can read the dashboard.
  To turn it on, set `HOMEPAGE_AUTH_ENABLED=true`, `HOMEPAGE_AUTH_SECRET` (32+
  characters, e.g. `openssl rand -base64 32`), `HOMEPAGE_EXTERNAL_URL` and
  `HOMEPAGE_AUTH_PASSWORD`.
- **Environment variables for widgets** must be prefixed `HOMEPAGE_VAR_` or
  `HOMEPAGE_FILE_` and referenced as `{{HOMEPAGE_VAR_NAME}}`. This stack has no
  `env_file`, so only variables listed under `environment:` reach the container,
  and they are read at container creation, not on restart.
- **The container runs as root** by default. The image supports `PUID`/`PGID` if
  you need otherwise, in which case the mounted config must be owned by that uid.
- This stack has no `.env` file of its own beyond the tracked symlink; there is
  no `env_file`, so the symlink only serves `${HOMEPAGE_PERSIST_DIR}`.
