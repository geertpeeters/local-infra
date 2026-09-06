.PHONY: trilium-up trilium-down trilium-logs trilium-ps

# --- TRILIUM TARGETS ---
trilium-up:
	docker compose -f trilium-notes/docker-compose.yml up -d --pull always

trilium-down:
	docker compose -f trilium-notes/docker-compose.yml down

trilium-logs:
	docker compose -f trilium-notes/docker-compose.yml logs -f --tail=100

trilium-ps:
	docker compose -f trilium-notes/docker-compose.yml ps
