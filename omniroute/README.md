# omniroute

API gateway (`omniroute`) with Redis for state. Everything that talks to a model
in this repo goes through here, including the Hermes agent.

## Access

`http://omniroute.test` via Traefik. No port is published on the host.

## Start

```bash
docker compose -f omniroute/docker-compose.yml up -d
docker compose -f omniroute/docker-compose.yml logs -f --tail=100
```

`omniroute` has `depends_on: omniroute-redis`.

## Containers

### omniroute

`diegosouzapw/omniroute:latest`, with `stop_grace_period: 40s` so it can shut
down cleanly.

| Variable in container | Value |
|----------------------|-------|
| `DATA_DIR` | `/app/data` |
| `PORT` | `${OMNIROUTE_DASHBOARD_PORT:-20128}` |
| `DASHBOARD_PORT` | `${OMNIROUTE_DASHBOARD_PORT:-20128}` |
| `API_PORT` | `${OMNIROUTE_API_PORT:-20129}` |
| `API_HOST` | `0.0.0.0` |
| `REDIS_URL` | `redis://omniroute-redis:6379` |

Traefik router: host `omniroute.test`, container port `20128`.

### omniroute-redis

`docker.io/library/redis:7-alpine`, started with
`redis-server --save 60 1 --loglevel warning`, so it persists to disk once a
minute rather than on every write.

## Volumes

| What | Where |
|------|-------|
| Omniroute state | `${OMNIROUTE_PERSIST_DIR}/data` |
| Redis persistence | `${OMNIROUTE_PERSIST_DIR}/redis` |

`${OMNIROUTE_PERSIST_DIR}` itself must exist before the first `up`; the `data`
and `redis` subdirectories are created by Docker.

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OMNIROUTE_PERSIST_DIR` | yes | Host dir containing `data/` and `redis/`. |
| `OMNIROUTE_DASHBOARD_PORT` | no | Dashboard port, default `20128`. **Changing it breaks the proxy route.** |
| `OMNIROUTE_API_PORT` | no | API port, default `20129`. **Changing it breaks the Hermes agent.** |

## Dependencies

- **Traefik** for the `omniroute.test` route.
- Consumed by **hermes**, which points at `http://omniroute:20129/v1`.

## Gotchas

- **Two ports that look configurable but are not.** The Traefik label hardcodes
  `20128`, and `hermes` hardcodes `20129`. Changing either variable breaks
  something without any error from Docker: you get a 502 or an agent that cannot
  reach a model. Leave them at the defaults until the compose files use the
  variables as well.
- The container receives the **entire** central `.env` through `env_file`.
- A commented-out `ports` block would publish the dashboard on
  `127.0.0.1:${OMNIROUTE_DASHBOARD_PORT}`. Uncomment it to debug without Traefik.
- **Redis data lives inside the persist directory** at
  `${OMNIROUTE_PERSIST_DIR}/redis`, so it is part of the `omniroute.tar.gz`
  archive from `./scripts/backup.sh`. Redis is configured with `--save 60 1` and
  rewrites `dump.rdb` while running, so a *live* copy can catch it half-written:
  use `./scripts/backup.sh --stop` before an upgrade or a restore-test.
- **Both images are pinned by digest.** `7-alpine` and `latest` are moving tags
  and tell you nothing on their own; the digest after the colon is what holds
  the bits. The last real OmniRoute release tag is `1.0.5` (February) while the
  pinned `latest` image is from August, which is why the tag is ignored here.
