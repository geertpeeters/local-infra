#!/usr/bin/env bash
#
# backup.sh - archiveer alle stateful persist-directories van deze repo.
#
# Read-only voor de data: er wordt niets verwijderd, herschreven of verplaatst.
# Elke run maakt een nieuwe map met een tijdstempel, dus een eerdere backup
# blijft altijd staan.
#
# Gebruik:
#   ./scripts/backup.sh              live kopie, geen downtime (snelst)
#   ./scripts/backup.sh --stop       stacks eerst stoppen, daarna herstarten
#   ./scripts/backup.sh --with-env   de centrale .env ook meeback-uppen (0600)
#
# Let op bij een live kopie: Trilium (SQLite) en de Omniroute-Redis (RDB)
# schrijven tijdens het kopiëren door. Gebruik --stop vlak voor een
# image-upgrade of een restore-test, anders kan een database in de archive
# inconsistent zijn.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CENTRAL_ENV="${CENTRAL_ENV:-${REPO_ROOT}/../.env}"
BACKUP_ROOT="${BACKUP_ROOT:-$(dirname "$CENTRAL_ENV")/backups}"

# Zelfde pinned image als de rest van de repo: alleen een busybox-tar nodig.
HELPER_IMAGE="${HELPER_IMAGE:-alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc}"

# Vaste volgorde, zodat de output vergelijkbaar blijft tussen runs.
STACKS="hermes trilium-notes omniroute portainer homepage opencode"

# env-var -> archiefnaam. De naam is het contract met de restore-stap.
TARGETS="HERMES_PERSIST_DIR:hermes TRILIUM_DATA_DIR:trilium-notes OMNIROUTE_PERSIST_DIR:omniroute PORTAINER_PERSIST_DIR:portainer HOMEPAGE_PERSIST_DIR:homepage OPENCODE_PERSIST_DIR:opencode"

# De enige named volume die echt los staat van de persist-directories.
# `hermes-home` staat hier met opzet NIET bij: het is `type: none, o: bind,
# device: ${HERMES_PERSIST_DIR}`, dus een bind in een verpakking. De data is
# al gedekt door hermes.tar.gz; nogmaals archiveren zou alleen dubbel werk zijn.
# `hermes-agent-src` is een echte lokale volume met de broncode-cache, en die
# overschrijft een image-upgrade juist niet - vandaar dat hij apart moet.
#
# De compose-projectnaam is niet vast te leggen in de repo: Compose rekent hem af
# van de map waar je `docker compose` aanroept, dus het volume wordt op label
# gezocht in plaats van op naam.
VOLUMES="hermes-agent-src"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[2m%s\033[0m\n' "$*"; }
warn()  { printf '\033[33m%s\033[0m\n' "$*"; }

usage() {
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

STOP=0
WITH_ENV=0
for arg in "$@"; do
	case "$arg" in
	--stop)     STOP=1 ;;
	--with-env) WITH_ENV=1 ;;
	-h|--help)  usage; exit 0 ;;
	*)          red "FOUT onbekend argument: ${arg}"; usage; exit 1 ;;
	esac
done

# Waarde uit de centrale .env, zonder de file te sourcen: een .env is data,
# geen shell-script, en die twee zijn per definitie niet hetzelfde.
env_value() {
	[ -f "$CENTRAL_ENV" ] || return 0
	sed -n "s/^[[:space:]]*\\(export[[:space:]]\{1,\\}\)\{0,1\}${1}[[:space:]]*=[[:space:]]*//p" "$CENTRAL_ENV" |
		head -1 |
		sed -e 's/[[:space:]]*#.*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# Docker Compose-semantiek: de echte omgeving wint van de .env.
resolve() {
	eval "_cur=\${$1:-}"
	if [ -n "$_cur" ]; then
		printf '%s' "$_cur"
	else
		env_value "$1"
	fi
}

# '~/data' -> '/home/gebruiker/data'. De tilde staat in een variabele, want een
# '~' rechtstreeks in het patroon van ${var#...} wordt door de shell zelf
# uitgeklapt en matcht dan niet.
expand_home() {
	tilde='~'
	case "$1" in
	"$tilde")    printf '%s' "$HOME" ;;
	"$tilde"/*)  printf '%s' "${HOME}/${1#"$tilde"/}" ;;
	*)            printf '%s' "$1" ;;
	esac
}

if ! command -v docker >/dev/null 2>&1; then
	red "FOUT docker niet gevonden op PATH"
	exit 2
fi

umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${BACKUP_ROOT}/${STAMP}"

STOPPED_LIST="$(mktemp)"
TAB="$(printf '\t')"
RESTARTED=0

# Precies een keer draaien, en ook bij een vroegtijdige exit of een signaal:
# anders blijft de hele infra stil na een mislukte back-up.
restart_stopped() {
	[ "$RESTARTED" -eq 1 ] && return 0
	[ -s "$STOPPED_LIST" ] || return 0
	RESTARTED=1
	echo
	info "gestopte stacks weer starten..."
	while IFS="$TAB" read -r stack services; do
		# Alleen de services die er ook echt draaiden. Een kale 'start' zou
		# ook de services oppakken die al voor deze run uitgezet waren.
		if docker compose --project-directory "${REPO_ROOT}/${stack}" \
			-f "${REPO_ROOT}/${stack}/docker-compose.yml" start $services >/dev/null 2>&1; then
			green "OK   ${stack} weer gestart: ${services//$TAB/ }"
		else
			red "FOUT kon ${stack} niet herstarten"
		fi
	done < "$STOPPED_LIST"
}

trap 'restart_stopped; rm -f "$STOPPED_LIST"' EXIT
trap 'restart_stopped; exit 130' INT TERM

if [ "$STOP" -eq 1 ]; then
	echo "=== stacks stoppen voor een consistente kopie ==="
	for stack in $STACKS; do
		compose_file="${REPO_ROOT}/${stack}/docker-compose.yml"
		[ -f "$compose_file" ] || continue
		# Servicenamen, geen container-id's: die zijn nodig om na afloop
		# precies dezelfde subset weer te starten.
		running="$(docker compose --project-directory "${REPO_ROOT}/${stack}" \
			-f "$compose_file" ps --services --status running 2>/dev/null | tr '\n' "$TAB")"
		[ -n "$running" ] || continue
		if docker compose --project-directory "${REPO_ROOT}/${stack}" \
			-f "$compose_file" stop $running >/dev/null 2>&1; then
			printf '%s%s%s\n' "$stack" "$TAB" "$running" >> "$STOPPED_LIST"
			green "STOP ${stack}: ${running//$TAB/ }"
		else
			red "FOUT kon ${stack} niet stoppen; live kopie kan inconsistent zijn"
		fi
	done
	[ -s "$STOPPED_LIST" ] || info "stond al niets aan"
else
	echo
	warn "Live kopie: draaiende databases kunnen inconsistent worden vastgelegd."
	info "Gebruik --stop voor een snapshot die je kunt terugzetten na een upgrade."
fi

echo
info "back-upmap: ${DEST}"
if ! mkdir -p "$DEST"; then
	red "FOUT kon ${DEST} niet aanmaken"
	exit 1
fi
chmod 700 "$DEST"

fail=0
created=0
skipped=0

echo
echo "=== persist-directories ==="
for target in $TARGETS; do
	var="${target%%:*}"
	label="${target##*:}"
	dir="$(expand_home "$(resolve "$var")")"

	if [ -z "$dir" ]; then
		warn "SKIP ${label}: ${var} is niet gezet"
		skipped=$((skipped + 1))
		continue
	fi
	if [ ! -d "$dir" ]; then
		warn "SKIP ${label}: ${dir} bestaat niet"
		skipped=$((skipped + 1))
		continue
	fi
	if [ ! -r "$dir" ]; then
		red "FOUT ${label}: geen leesrechten op ${dir}"
		skipped=$((skipped + 1))
		fail=1
		continue
	fi

	# -C zodat het archief geen absoluet pad bevat: unpacken landt dan in de
	# map die je zelf kiest, niet in /home/... op de herstellende host.
	if tar -czf "${DEST}/${label}.tar.gz" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null; then
		green "OK   ${label}.tar.gz  <- ${dir}"
		created=$((created + 1))
	else
		red "FOUT kon ${label} niet archiveren (${dir})"
		fail=1
	fi
done

# Named volumes staan buiten elk persist-dir, dus die worden apart gepakt met
# een korte helper-image die alleen tar heeft.
echo
echo "=== docker volumes ==="
for logical in $VOLUMES; do
	volumes="$(docker volume ls -q \
		--filter "label=com.docker.compose.volume=${logical}" 2>/dev/null)"
	if [ -z "$volumes" ]; then
		warn "SKIP ${logical}: geen volume gevonden (stack draait nog nooit)"
		skipped=$((skipped + 1))
		continue
	fi
	count="$(printf '%s\n' "$volumes" | grep -c .)"
	for vol in $volumes; do
		project="$(docker volume inspect -f \
			'{{ index .Labels "com.docker.compose.project" }}' "$vol" 2>/dev/null)"
		[ -n "$project" ] || project="onbekend"
		# Eén match is de normale situatie; het project alleen meenemen als
		# er meerdere zijn, zodat de bestandsnaam leesbaar blijft.
		if [ "$count" -gt 1 ]; then
			name="${logical}__${project}.tar.gz"
		else
			name="${logical}.tar.gz"
		fi
		if docker run --rm --user "$(id -u):$(id -g)" \
			-v "${vol}:/src:ro" -v "${DEST}:/out" \
			"$HELPER_IMAGE" tar -czf "/out/${name}" -C /src . 2>/dev/null; then
			green "OK   ${name}  <- volume ${vol} (project ${project})"
			created=$((created + 1))
		else
			red "FOUT kon volume ${vol} niet archiveren"
			fail=1
		fi
	done
done

if [ "$WITH_ENV" -eq 1 ]; then
	echo
	if [ -f "$CENTRAL_ENV" ]; then
		cp "$CENTRAL_ENV" "${DEST}/centrale.env"
		chmod 600 "${DEST}/centrale.env"
		green "OK   centrale.env  <- ${CENTRAL_ENV}"
		created=$((created + 1))
	else
		warn "SKIP --with-env: ${CENTRAL_ENV} ontbreekt"
		skipped=$((skipped + 1))
	fi
else
	info "de centrale .env staat NIET in deze back-up; gebruik --with-env als je hem nodig hebt"
fi

# Manifest: wat er precies in zit, met checksums, plus de images die op dat
# moment geconfigureerd waren. Zonder dit is een restore gissen.
echo
info "manifest schrijven..."
{
	echo "backup:    ${STAMP}"
	echo "repo:      ${REPO_ROOT}"
	echo "host:      $(uname -srm)"
	echo "created:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo
	echo "images:"
	for stack in $STACKS; do
		compose_file="${REPO_ROOT}/${stack}/docker-compose.yml"
		[ -f "$compose_file" ] || continue
		images="$(docker compose --project-directory "${REPO_ROOT}/${stack}" \
			-f "$compose_file" config --images 2>/dev/null | sort -u)"
		[ -n "$images" ] || continue
		printf '%s\n' "$images" | while IFS= read -r image; do
			printf '  %-14s %s\n' "$stack" "$image"
		done
	done
	echo
	echo "checksums:"
	if command -v sha256sum >/dev/null 2>&1; then
		( cd "$DEST" && sha256sum -- *.tar.gz 2>/dev/null )
	else
		echo "  sha256sum ontbreekt op deze host; checksums niet vastgelegd"
	fi
} > "${DEST}/MANIFEST.txt"
chmod 600 "${DEST}/MANIFEST.txt"
green "OK   MANIFEST.txt"

restart_stopped

echo
echo "=== samenvatting ==="
info "map:        ${DEST}"
info "aangemaakt: ${created}"
if [ "$skipped" -gt 0 ]; then
	info "overgeslagen: ${skipped}"
fi
size="$(du -sh "$DEST" 2>/dev/null | awk '{print $1}')"
[ -n "$size" ] && info "grootte:    ${size}"

if [ "$fail" -ne 0 ]; then
	red "Back-up afgerond met fouten; zie de FOUT-regels hierboven."
	exit 1
fi

green "Back-up klaar."
echo
info "Terugzetten:"
info "  1. zet de stack stil:   docker compose -f <stack>/docker-compose.yml down"
info "  2. pak het archief uit: tar -xzf <label>.tar.gz -C <doelmap>"
info "  3. herstart:            docker compose -f <stack>/docker-compose.yml up -d"
exit 0
