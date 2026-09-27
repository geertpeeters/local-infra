# portainer

Web UI for managing the Docker host.

## Access

`http://portainer.test` via Traefik. No port is published on the host.

## Start

```bash
docker compose -f portainer/docker-compose.yml up -d
docker compose -f portainer/docker-compose.yml logs -f --tail=100
```

## Configuration

| What | Where |
|------|-------|
| Portainer state | `${PORTAINER_PERSIST_DIR}` on the host, mounted at `/data` |
| Docker socket | `/var/run/docker.sock`, mounted **read-write** |

Required variable:

| Variable | Description |
|----------|-------------|
| `PORTAINER_PERSIST_DIR` | Host dir for Portainer data |

The variable name is misspelled: `PORTAINER` should read `PORTAINER`. It is left
alone on purpose, because it already lives in the central `.env` and renaming it
in only one of the three places (compose, README, `.env`) breaks the stack.

Portainer has its own login. The stack configures nothing about it; the first
run sets up the admin account through the web UI.

Traefik router: host `portainer.test`, container port `9000`.

## Dependencies

- **Traefik** for the route.
- Nothing else. It manages the host, not the other stacks.

## Gotchas

- **The Docker socket is mounted read-write.** Combined with the fact that this
  container can start, stop and exec into anything on the host, that is
  effectively root access. It is how Portainer works, but it means anyone who
  gets past the login owns the machine.
- **The container receives the entire central `.env`** through `env_file`,
  including API keys for services that have nothing to do with Portainer. Drop
  the `env_file` if you do not need any of them.
- The image is pinned to `portainer/portainer-ce:2.45.1` plus a digest, so the
  same version comes back after a `pull` or a host rebuild.
- Portainer's own agent stack (for swarm/endpoint agents) is not configured here.
