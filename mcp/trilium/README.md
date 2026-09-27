# mcp/trilium

Model Context Protocol server that exposes Trilium notes to MCP clients. Built
from source, not pulled as an image.

## Access

`127.0.0.1:${TRILIUM_MCP_HTTP_PORT}` on the host only. Not exposed through
Traefik.

## Start

```bash
docker compose -f mcp/trilium/docker-compose.yml up -d
docker compose -f mcp/trilium/docker-compose.yml logs -f --tail=100
```

## Built from a git remote

```yaml
build:
  context: https://github.com/perfectra1n/triliumnext-mcp.git
```

Docker clones the repository at build time. There is no Dockerfile in this repo
and **no pinned ref**, so the build uses whatever `main` happens to be. Two
consequences:

- The first `up` needs network access and a git client in the builder.
- Rebuilding later can silently pick up upstream changes:
  `docker compose -f mcp/trilium/docker-compose.yml build --pull`

To pin it, add a `ref` to the build context or vendor a Dockerfile.

## Configuration

| Variable in container | Value |
|----------------------|-------|
| `TRILIUM_URL` | `http://trilium:8080/etapi` |
| `TRILIUM_TOKEN` | `${TRILIUM_API_TOKEN}` |
| `TRILIUM_TRANSPORT` | `http` |
| `TRILIUM_HTTP_PORT` | `${TRILIUM_MCP_HTTP_PORT}` |

The same port is published on `127.0.0.1`, so it is not reachable from the LAN.

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TRILIUM_API_TOKEN` | yes | eAPI token for Trilium. |
| `TRILIUM_MCP_HTTP_PORT` | yes | Host **and** container port. Pick something free, e.g. `8081`. |

## Dependencies

- **trilium-notes** must be running, on the same `infra-net`, because
  `TRILIUM_URL` resolves the `trilium` container by name. This is a cross-stack
  dependency that the compose file cannot express.
- **Trilium's eAPI must be enabled** and the token created in the Trilium UI
  under settings. Without it the server starts but every request fails.

## Gotchas

- **Nested stack.** Its `.env` symlink is `../../../.env`, one level deeper than
  the others, because the project directory is `mcp/trilium/`.
- **A wrong `TRILIUM_MCP_HTTP_PORT` breaks two things at once** if you also map
  it in Traefik later; the value is used on both sides of the port mapping.
- The empty `mcp/github/` and `mcp/sqlite/` directories are leftovers from
  earlier MCP servers. Git does not track empty directories, so they exist only
  on this machine and can be removed.
- The container receives the **entire** central `.env` through `env_file`.
