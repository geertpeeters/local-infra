# Local Infrastructure

A set of Docker‑compose services for local development, testing, and management.

## Services

- **mcp** – Model Context Protocol services.
- **trilium-notes** – Note‑taking application (single source of truth for the agentic framework).
- **hermes** – AI agent and web UI (gateway + web UI).  
  The `.hermes` container uses a bind‑mount to a host directory outside the repository that holds multiple profiles; this folder is not version‑controlled.
- **omniroute** – Reverse proxy / API gateway.
- **portainer** – Docker management UI.

## Prerequisites

- Docker Engine (≥ 24.x)
- Docker Compose (v2)
- Git
- API keys for NVIDIA, OpenAI, etc. (the `.env` file is a symlink one level above the repository root)

## Setup

1. Clone the repository.
   ```bash
   git clone https://github.com/yourname/local-infra.git
   cd local-infra
   ```
2. Create a symlink to the central `.env` file (one level above the repo).
   ```bash
   ln -s /path/to/central/.env ../.env   # adjust path as needed
   ```
   Then edit the central `.env` to add any required keys.
   ```bash
   nano /path/to/central/.env
   ```
3. Start a specific service (example for Hermes):
   ```bash
   docker compose -f hermes/docker-compose.yml up -d
   ```
   (Replace `hermes` with the desired service name.)

4. Verify the service is running.
   ```bash
   docker compose -f hermes/docker-compose.yml ps
   ```

## Running Individual Services

Each service lives in its own directory and contains its own `docker-compose.yml`. Use the `-f` flag to point to the correct file for the service you want to run.

## Stopping and Cleanup

```bash
docker compose -f <service>/docker-compose.yml down
```

Data volumes are retained; use `docker compose -f <service>/docker-compose.yml down -v` to remove them.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TRILIUM_DATA_DIR` | Path for Trilium data directory (default: `/home/node/trilium-data`). |
| `HERMES_PERSIST_DIR` | Directory for Hermes persistence (default: `${HOME}/.hermes`). |
| `NVIDIA_API_KEY` | NVIDIA API key for GPU‑accelerated services. |
| `OMNIROUTE_API_KEY` | API key for the Omniroute service. |

All services read from the single `.env` file referenced by the symlink one level above the repository root.

## Troubleshooting

- **Missing env vars** – Containers will fail to start; check the logs with `docker compose -f <service>/docker-compose.yml logs`.
- **Port conflicts** – Services bind to `127.0.0.1`; modify the host port in the compose file if needed.
- **Permission errors** – Ensure mounted host directories are writable by the container user.

## Contributing

Feel free to open issues or submit PRs. Add new services under a dedicated folder and ensure each has its own `docker-compose.yml`.

## License

MIT License.