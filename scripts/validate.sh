#!/usr/bin/env bash
#
# validate.sh - controleer elke stack zonder iets te starten of te wijzigen.
#
# Draait `docker compose config`, wat het compose-bestand volledig resolvert:
# YAML-syntax, schema, env_file-bestaan, netwerkverwijzingen en variabelen.
# Er wordt geen container aangemaakt en geen poort vrijgegeven. Exit 0 = alles
# valideert, exit 1 = er is iets kapot, exit 2 = docker ontbreekt.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERR="$(mktemp)"
LIST="$(mktemp)"
trap 'rm -f "$ERR" "$LIST"' EXIT

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[2m%s\033[0m\n' "$*"; }

if ! command -v docker >/dev/null 2>&1; then
	red "FOUT docker niet gevonden op PATH"
	exit 2
fi
if ! docker compose version >/dev/null 2>&1; then
	red "FOUT de 'docker compose' plugin (Compose v2) ontbreekt"
	exit 2
fi

# Volledige, opgeloste config per stack ophalen. Compose zet project- EN werkmap
# op de map van het compose-bestand, dus variabelen en env_file worden daar
# geresolved - precies zoals bij een echte `up`.
resolve() {
	docker compose --project-directory "$(dirname "$1")" -f "$1" config 2>"$ERR"
}

# Lege compose-bestanden overgeslagen: een lege docker-compose.yml is een
# achtergebleven artefact en geen stack.
find "$REPO_ROOT" -name 'docker-compose.yml' -not -path '*/.git/*' -size +0c | sort > "$LIST"

fail=0
checked=0

echo "=== stacks valideren ==="
echo

while IFS= read -r compose_file; do
	stack_dir="$(dirname "$compose_file")"
	stack="${stack_dir#"$REPO_ROOT"/}"
	checked=$((checked + 1))
	problems=""

	# 1. .env moet een symlink zijn die ook echt resolveert
	link="${stack_dir}/.env"
	if [ -L "$link" ]; then
		if [ ! -e "$link" ]; then
			problems="${problems}     .env is een broken symlink -> $(readlink "$link")
"
		fi
	elif [ -e "$link" ]; then
		problems="${problems}     .env is een ECHT bestand i.p.v. een symlink - geen secrets in git
"
	else
		problems="${problems}     .env ontbreekt in ${stack}/ (draai ./scripts/setup.sh)
"
	fi

	# 2. volledige resolutie moet slagen
	out="$(resolve "$compose_file")"
	resolved=$?
	if [ "$resolved" -ne 0 ]; then
		# Compose zet waarschuwingen bovenaan op stderr. `head -1` zou dan de
		# oorzaak verhullen en een waarschuwing als foutmelding tonen, dus eerst
		# de eerste regel zoeken die géén warning is.
		reason="$(grep -v -e 'level=warning' -e '^WARN\[' -e 'is not set\. Defaulting' "$ERR" | head -1)"
		[ -n "$reason" ] || reason="$(head -1 "$ERR")"
		problems="${problems}     docker compose config faalde: ${reason}
"
	fi

	# 3. niet-gezette variabelen zijn de stilste breuk in deze repo. Compose
	#    waarschuwt hiervoor in twee formaten: kaal ("The "X" variable is not
	#    set") en verpakt in een logregel, waar de aanhalingstekens escaped zijn
	#    (msg="The \"X\" variable is not set"). De backslashes eerst weghalen,
	#    anders blijft de naam leeg en weet de leek niet wat hij moet invullen.
	if grep -q 'variable is not set' "$ERR" 2>/dev/null; then
		missing="$(sed 's/\\//g' "$ERR" |
			grep -o 'The "[^"]*" variable is not set' |
			sort -u |
			sed 's/The "//; s/" variable is not set//' |
			tr '\n' ' ')"
		[ -n "$missing" ] || missing="(naam niet te achterhalen, zie de melding hierboven)"
		problems="${problems}     niet-gezette variabele(n): ${missing}
"
	fi

	# 4. elke stack moet op hetzelfde externe netwerk hangen (alleen als 2 slaagde,
	#    anders is dit al in de foutmelding van de resolutie verwerkt)
	if [ "$resolved" -eq 0 ] && ! printf '%s\n' "$out" | grep -q 'name: infra-net'; then
		problems="${problems}     verwijst niet naar het externe netwerk 'infra-net'
"
	fi

	# 5. elke image op tag + digest. Gecontroleerd op het bronbestand en niet op
	#    de resolutie, want Compose zet bij een build-only service zelf een
	#    image: met de servicenaam erin - die mag je niet pinnen.
	unpinned="$(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "$compose_file" |
		grep -v '@sha256:' || true)"
	if [ -n "$unpinned" ]; then
		while IFS= read -r image; do
			problems="${problems}     image zonder digest (moet image:tag@sha256:... zijn): ${image}
"
		done <<EOF
$unpinned
EOF
	fi

	# 6. een container_name maakt 'docker logs <naam>' mogelijk en voorkomt
	#    project-afhankelijke containerdieren. Alle stacks hebben er nu een
	#    (traefik incl.); een nieuwe stack die hem vergeet moet hier op vallen.
	if ! grep -q 'container_name:' "$compose_file"; then
		problems="${problems}     geen container_name op deze stack
"
	fi

	if [ -z "$problems" ]; then
		green "OK   ${stack}"
	else
		red "FAIL ${stack}"
		printf '%s' "$problems"
		fail=$((fail + 1))
	fi
done < "$LIST"

# Varianten apart melden: die worden niet gevalideerd maar kunnen wel conflicteren
echo
variants="$(find "$REPO_ROOT" -name 'docker-compose*.yml' -not -name 'docker-compose.yml' -not -path '*/.git/*' | sort)"
if [ -n "$variants" ]; then
	info "Niet-gevalideerde varianten (bewust overgeslagen):"
	printf '%s\n' "$variants" | sed 's/^/  /'
	info "Controleer of ze nog in sync zijn, of verwijder ze."
	echo
fi

echo "=== ${checked} stacks gecontroleerd, ${fail} met problemen ==="
if [ "$fail" -gt 0 ]; then
	exit 1
fi
green "Alles valideert. Starten kan met:  make up SVC=<stack>"
