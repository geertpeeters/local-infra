#!/usr/bin/env bash
#
# setup.sh - maak een verse clone draaibaar.
#
# Idempotent en niet-destructief: een bestaand, werkend symlink wordt nooit
# herschreven; alleen ontbrekende of broken symlinks worden hersteld.
#
# Doet drie dingen:
#   1. Controleert de centrale secret-store (standaard REPO_ROOT/../.env).
#   2. Maakt het externe netwerk `infra-net` aan (alle stacks hangen eraan).
#   3. Herstelt de `<stack>/.env`-symlink naar die centrale secret-store.
#
# Daarna: ./scripts/validate.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CENTRAL_ENV="${CENTRAL_ENV:-${REPO_ROOT}/../.env}"
NETWORK="${NETWORK:-infra-net}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[2m%s\033[0m\n' "$*"; }

fail=0
LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT

# Alle compose-bestanden van de repo, lege bestanden overgeslagen: een lege
# docker-compose.yml is een achtergebleven artefact en geen stack.
find "$REPO_ROOT" -name 'docker-compose.yml' -not -path '*/.git/*' -size +0c | sort > "$LIST"

# Repo-relatieve stacknaam, zodat mcp/trilium niet 'trilium' heet.
stack_name() {
	printf '%s' "${1#"$REPO_ROOT"/}"
}

# Relatief pad van een stackmap naar de centrale .env, puur in shell zodat er
# geen realpath --relative-to (coreutils-only) nodig is. De conventie is: de
# centrale .env staat precies één map boven de repo root.
rel_to_central() {
	stack_dir="$1"
	rest="${stack_dir#"$REPO_ROOT"/}"
	rel=".."
	if [ "$rest" != "$stack_dir" ]; then
		depth="$(printf '%s' "$rest" | tr '/' '\n' | grep -c .)"
		i=0
		while [ "$i" -lt "$depth" ]; do
			rel="${rel}/.."
			i=$((i + 1))
		done
	fi
	printf '%s/.env' "$rel"
}

# --- 1. centrale secret-store -------------------------------------------------

if [ -f "$CENTRAL_ENV" ]; then
	green "OK   centrale .env gevonden: ${CENTRAL_ENV}"
elif [ -e "$CENTRAL_ENV" ]; then
	red "FOUT centrale .env is geen regular file: ${CENTRAL_ENV}"
	fail=1
else
	red "FOUT centrale .env ontbreekt: ${CENTRAL_ENV}"
	info "     Maak hem aan (chmod 600) en vul de keys uit README.md > Environment Variables."
	fail=1
fi

# --- 2. extern netwerk --------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
	red "FOUT docker niet gevonden op PATH"
	fail=1
elif docker network inspect "$NETWORK" >/dev/null 2>&1; then
	green "OK   netwerk '${NETWORK}' bestaat al"
else
	info "netwerk '${NETWORK}' aanmaken..."
	if docker network create "$NETWORK" >/dev/null 2>&1; then
		green "OK   netwerk '${NETWORK}' aangemaakt"
	else
		red "FOUT kon netwerk '${NETWORK}' niet aanmaken"
		fail=1
	fi
fi

# --- 3. .env-symlinks per stack -----------------------------------------------

# Elke map met een docker-compose.yml krijgt een eigen .env-symlink: Compose leest
# zowel de variabele-interpolatie (${VAR}) als env_file relatief aan de projectmap,
# en die is de map van het compose-bestand.
echo
info ".env-symlinks per stack controleren..."

while IFS= read -r compose_file; do
	stack_dir="$(dirname "$compose_file")"
	stack="$(stack_name "$stack_dir")"
	link="${stack_dir}/.env"
	rel="$(rel_to_central "$stack_dir")"

	if [ -L "$link" ]; then
		if [ -e "$link" ]; then
			green "OK   ${stack}/.env -> $(readlink "$link")"
		else
			ln -sfn "$rel" "$link"
			green "FIX  ${stack}/.env: broken symlink hersteld -> ${rel}"
		fi
	elif [ -e "$link" ]; then
		# een echt bestand: niet overschrijven, dat zijn waarschijnlijk de secrets
		red "FOUT ${stack}/.env is een ECHT bestand, geen symlink"
		info "     Zet hem handmatig om naar een symlink; de secrets blijven staan."
		fail=1
	else
		ln -sfn "$rel" "$link"
		green "AAN  ${stack}/.env -> ${rel}"
	fi
done < "$LIST"

# --- samenvatting -------------------------------------------------------------

echo
if [ "$fail" -eq 0 ]; then
	green "Setup klaar."
	info "Start een stack met:  make up SVC=trilium-notes"
	info "Valideer de repo met: make check"
	exit 0
fi

red "Setup niet afgerond, zie de FOUT-regels hierboven."
exit 1
