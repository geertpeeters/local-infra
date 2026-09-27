# trilium-notes

TriliumNext, the note-taking application. Doubles as the single source of truth
for the agentic framework, and as the knowledge base the Hermes wiki mounts.

## Access

`http://trilium.test` via Traefik. No port is published on the host.

## Start

```bash
docker compose -f trilium-notes/docker-compose.yml up -d
docker compose -f trilium-notes/docker-compose.yml logs -f --tail=100
```

## Configuration

| What | Where |
|------|-------|
| Notes | `${TRILIUM_DATA_DIR}` on the host, mounted at `/home/node/trilium-data` |
| Timezone | `/etc/timezone` and `/etc/localtime` mounted read-only |

Required variable:

| Variable | Description |
|----------|-------------|
| `TRILIUM_DATA_DIR` | Host dir for the Trilium data directory |

Inside the container `TRILIUM_DATA_DIR` is set to `/home/node/trilium-data`.
The host path only exists in the compose file, not in the container environment.

Traefik router: host `trilium.test`, container port `8080`.

## Dependencies

None, but other stacks depend on this one:

- **mcp/trilium** calls the eAPI at `http://trilium:8080/etapi`, so Trilium must
  be running and the eAPI must be enabled with a token (`TRILIUM_API_TOKEN`).
- **hermes** mounts a wiki, though the path is configured on the Hermes side.

## Gotchas

- **Traefik must be up** or the router will not resolve, even though the
  container itself is healthy.
- **The image is pinned** to `triliumnext/trilium:v0.106.0` plus a digest, so a
  `pull` cannot move Trilium under your feet. When you bump it, back up
  `${TRILIUM_DATA_DIR}` first with `./scripts/backup.sh --stop`.
- Nothing in front of it at the proxy level. Trilium does its own
  authentication, but this stack does not configure or expose it.
- The whole `.env` is handed to the container through `env_file`, including keys
  Trilium has no use for.
