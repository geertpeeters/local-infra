# traefik

Reverse proxy and the only entry point into this infrastructure. Discovers
containers on `infra-net` and routes them by hostname.

## Access

| What | Where |
|------|-------|
| HTTP entrypoint | `:80` on all interfaces |
| HTTPS entrypoint | `:443` on all interfaces (no TLS configured, see Gotchas) |
| Dashboard | `http://127.0.0.1:8083` |

## Start

Start this **first**. Routers for other stacks only appear once Traefik is
running, because it learns about containers through the Docker API.

```bash
docker compose -f traefik/docker-compose.yml up -d
docker compose -f traefik/docker-compose.yml logs -f --tail=100
```

## Configuration

`traefik.yml` is bind-mounted read-only, so changes take effect after a restart:

```bash
docker compose -f traefik/docker-compose.yml restart traefik
```

Current settings:

- `providers.docker.exposedByDefault: false` - a container is only routed if it
  carries `traefik.enable=true`. This is why no service publishes a port.
- `api.dashboard: true` with `api.insecure: true` - the dashboard is unauthenticated.
- Two entrypoints, `web` (`:80`) and `websecure` (`:443`).
- Access logging on, log level `INFO`.

No environment variables. Nothing in this stack is configurable via `.env`.

## Gotchas

- **The dashboard has no authentication.** It is bound to `127.0.0.1:8083` for
  that reason. Do not move it to `0.0.0.0` without putting auth in front of it.
- **`:443` serves plain HTTP.** There is no `certificatesResolver` and no
  certificate, so do not point anything sensitive at it over the network.
- **Nothing routes to `:443` yet.** The `websecure` entrypoint exists and the
  port is published, but every router in this repo uses `entrypoints=web`, so a
  request on 443 gets no route at all until TLS is set up. The port is kept on
  purpose, as a placeholder for that.
- **The Docker socket is mounted read-only**, which is required for the
  discovery API but still exposes container metadata.
- **API version is forced to 1.40** (`--docker.apiVersion=1.40`), well below
  what a modern Docker Engine offers. Harmless today, but it is the kind of pin
  that breaks when Traefik drops support for old API versions. The duplicate
  `DOCKER_API_VERSION=1.40` environment variable that used to sit next to it is
  gone; the flag alone is enough.
- The image is pinned to `traefik:v3.7` plus a digest. The tag is a moving one
  (it currently equals v3.7.13), so the digest is what actually holds the line:
  a `pull` of the same tag can only ever give you the same bits.
