# Generieke helpers voor alle stacks in deze repo.
#
#   make setup                  eenmalig: netwerk + .env-symlinks herstellen
#   make check                  valideer alles, start niets
#   make up    SVC=trilium-notes
#   make down  SVC=trilium-notes
#   make logs  SVC=trilium-notes
#   make ps    SVC=trilium-notes
#   make help                  overzicht van alle stacks
#
# SVC accepteert ook paden, dus SVC=mcp/trilium werkt.

SHELL := /bin/sh

# Alle stacks = elke map met een niet-lege docker-compose.yml.
STACKS := $(shell find . -name docker-compose.yml -size +0c -not -path './.git/*' \
	| sed 's|/docker-compose.yml||; s|^\./||' | sort)

COMPOSE_DIR := $(CURDIR)/$(SVC)
COMPOSE := docker compose --project-directory $(COMPOSE_DIR) -f $(COMPOSE_DIR)/docker-compose.yml

.PHONY: help setup check stacks up down restart pull logs ps shell clean \
        require-svc require-service \
        trilium-up trilium-down trilium-logs trilium-ps

help:
	@echo "Stacks: $(STACKS)"
	@echo
	@echo "  make setup              netwerk 'infra-net' + .env-symlinks herstellen"
	@echo "  make check              alle stacks valideren (docker compose config)"
	@echo "  make up     SVC=<stack> stack starten"
	@echo "  make down   SVC=<stack> stack stoppen"
	@echo "  make restart SVC=<stack> stack herstarten"
	@echo "  make pull   SVC=<stack> images ophalen"
	@echo "  make logs   SVC=<stack> logs volgen"
	@echo "  make ps     SVC=<stack> status"
	@echo "  make shell  SVC=<stack> SERVICE=<svc>  shell in de container"
	@echo "  make clean  SVC=<stack> stack stoppen en volumes weggooien"

stacks:
	@printf '%s\n' $(STACKS)

setup:
	@./scripts/setup.sh

check:
	@./scripts/validate.sh

# --- stackbeheer --------------------------------------------------------------

up: require-svc
	$(COMPOSE) up -d --pull always

down: require-svc
	$(COMPOSE) down

restart: require-svc
	$(COMPOSE) restart

pull: require-svc
	$(COMPOSE) pull

logs: require-svc
	$(COMPOSE) logs -f --tail=100

ps: require-svc
	$(COMPOSE) ps

shell: require-svc require-service
	$(COMPOSE) exec $(SERVICE) sh

# Vernietigt de data: volumes gaan eraan. 'down' behoudt ze.
clean: require-svc
	$(COMPOSE) down -v

# --- guards -------------------------------------------------------------------

require-svc:
	@if [ -z "$(SVC)" ]; then \
		echo "Fout: SVC ontbreekt. Gebruik bijv. 'make up SVC=trilium-notes'."; \
		echo "Beschikbare stacks: $(STACKS)"; \
		exit 1; \
	fi
	@case " $(STACKS) " in \
		*" $(SVC) "*) ;; \
		*) echo "Fout: onbekende stack '$(SVC)'. Beschikbaar: $(STACKS)"; exit 1 ;; \
	esac

# Elke stack heeft andere servicenamen, dus die geef je expliciet mee:
#   make shell SVC=trilium-notes SERVICE=trilium
SERVICE ?=

require-service:
	@if [ -z "$(SERVICE)" ]; then \
		echo "Fout: SERVICE ontbreekt, bijv. make shell SVC=trilium-notes SERVICE=trilium"; \
		echo "Bekijk de namen met: make ps SVC=<stack>"; \
		exit 1; \
	fi

# --- oude trilium-targets -----------------------------------------------------
# Vervangen door de generieke targets; hier gehouden zodat bestaande scripts
# en muscle memory blijven werken.

trilium-up:
	@$(MAKE) up SVC=trilium-notes

trilium-down:
	@$(MAKE) down SVC=trilium-notes

trilium-logs:
	@$(MAKE) logs SVC=trilium-notes

trilium-ps:
	@$(MAKE) ps SVC=trilium-notes
