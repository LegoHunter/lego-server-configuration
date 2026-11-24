#!/usr/bin/env bash
# Takes rights away from existing MySQL accounts on rasppi5-01 (HOMELAB-126). Three separate
# actions; each asks for confirmation and each can be undone.
#
#   bash narrow-accounts.sh legomgr
#       legomgr keeps its name, host and password and ends up with ALL on lego_prod_legacy and
#       nothing else: no other schema, no server-wide right, no GRANT OPTION. The legacy
#       command-line tools keep working unchanged. Its grants as they were are saved first, as SQL
#       that restores them, in ~/legomgr-grants-before-<time>.sql (grants hold no password).
#       Undo:  sudo mysql < ~/legomgr-grants-before-<time>.sql
#
#   bash narrow-accounts.sh tvattima-host
#       tvattima may connect from the homelab LAN and VPN (10.0.%) instead of from any address.
#       Its rights and password do not change.
#       Undo:  sudo mysql -e "RENAME USER 'tvattima'@'10.0.%' TO 'tvattima'@'%'"
#
#   bash narrow-accounts.sh drop-codex
#       Drops codex_sandbox_ro (Codex is no longer used).
#       Undo:  create it again with setup-claude-mysql-users.sh's pattern; nothing depends on it.
#
# Do `legomgr` only after nothing but the legacy tools connects as legomgr: check section 3 of
# inventory-mysql-accounts.sh first. The action shows those connections again before it asks.
#
# Run on rasppi5-01 as a user that can `sudo mysql` (root via auth_socket).
#
# Optional:
#   LEGACY_SCHEMA   the schema legomgr keeps (default: lego_prod_legacy)
#   ADMIN_HOST      the host pattern tvattima gets (default: 10.0.%)
#   MYSQL_CMD       command used to run SQL as root (default: sudo mysql)
#   DRY_RUN=1       print the SQL and change nothing
set -euo pipefail

ACTION="${1:-}"
LEGACY_USER="legomgr"
LEGACY_SCHEMA="${LEGACY_SCHEMA:-lego_prod_legacy}"
ADMIN_USER="tvattima"
ADMIN_HOST="${ADMIN_HOST:-10.0.%}"
CODEX_USER="codex_sandbox_ro"
MYSQL_CMD="${MYSQL_CMD:-sudo mysql}"
DRY_RUN="${DRY_RUN:-0}"

[[ "$LEGACY_SCHEMA" =~ ^[A-Za-z0-9_]{1,64}$ ]] || { echo "Not a plain schema name: $LEGACY_SCHEMA" >&2; exit 1; }
[[ "$ADMIN_HOST" =~ ^[A-Za-z0-9.%_-]{1,255}$ ]] || { echo "Not a plain host pattern: $ADMIN_HOST" >&2; exit 1; }

query() {
  $MYSQL_CMD -N -B -e "$1"
}

hosts_for() {
  query "SELECT Host FROM mysql.user WHERE User = '$1' ORDER BY Host"
}

confirm() {
  local word="$1" answer
  read -rp "Type \"${word}\" to go ahead: " answer </dev/tty
  [[ "$answer" == "$word" ]] || { echo "Not confirmed; nothing changed." >&2; exit 1; }
}

run_sql() {
  local sql="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY RUN: nothing is changed. The SQL that would run:"
    echo
    printf '%s\n' "$sql"
    exit 0
  fi
  $MYSQL_CMD <<<"$sql"
}

narrow_legomgr() {
  local hosts host sql="" before restore
  hosts="$(hosts_for "$LEGACY_USER")"
  [[ -n "$hosts" ]] || { echo "No MySQL user named ${LEGACY_USER}." >&2; exit 1; }
  [[ "$(query "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '${LEGACY_SCHEMA}'")" == "1" ]] \
    || { echo "Schema ${LEGACY_SCHEMA} does not exist on this server." >&2; exit 1; }

  # Grants as they are, as SQL that puts them back. SHOW GRANTS prints no password.
  before=""
  while read -r host; do
    before+="$(query "SHOW GRANTS FOR '${LEGACY_USER}'@'${host}'" | sed 's/$/;/')"$'\n'
  done <<<"$hosts"

  echo "${LEGACY_USER} today:"
  printf '%s' "$before" | sed 's/^/  /'
  echo
  echo "Connections as ${LEGACY_USER} since MySQL started (address, open now, total):"
  query "SELECT HOST, CURRENT_CONNECTIONS, TOTAL_CONNECTIONS FROM performance_schema.accounts WHERE USER = '${LEGACY_USER}'" | sed 's/^/  /'
  echo "  Cluster nodes are 10.0.2.x. If one of them still shows open connections, a service still"
  echo "  uses ${LEGACY_USER}: stop here."
  echo

  # In GRANT ... ON `db`.*, '_' is a wildcard; escape it so the grant matches the exact schema.
  local escaped
  escaped="$(printf '%s' "$LEGACY_SCHEMA" | sed 's/_/\\_/g')"
  while read -r host; do
    sql+="REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${LEGACY_USER}'@'${host}';
GRANT ALL PRIVILEGES ON \`${escaped}\`.* TO '${LEGACY_USER}'@'${host}';
"
  done <<<"$hosts"

  if [[ "$DRY_RUN" != "1" ]]; then
    echo "After this, ${LEGACY_USER} has ALL on ${LEGACY_SCHEMA} and nothing else."
    confirm "narrow"
    restore="$HOME/${LEGACY_USER}-grants-before-$(date +%Y%m%dT%H%M%S).sql"
    ( umask 077; printf '%s' "$before" > "$restore" )
    echo "Saved the grants as they were: ${restore}"
  fi
  run_sql "$sql"

  echo
  echo "Done. ${LEGACY_USER} now:"
  while read -r host; do
    query "SHOW GRANTS FOR '${LEGACY_USER}'@'${host}'" | sed 's/^/  /'
  done <<<"$hosts"
  echo
  echo "Now check the legacy tools with one read-only command."
  echo "Undo:  sudo mysql < ${restore}"
}

narrow_admin_host() {
  local hosts
  hosts="$(hosts_for "$ADMIN_USER")"
  if [[ "$hosts" == "$ADMIN_HOST" ]]; then
    echo "${ADMIN_USER} is already limited to ${ADMIN_HOST}; nothing to do."
    exit 0
  fi
  [[ "$hosts" == "%" ]] || { echo "Expected ${ADMIN_USER}@% and nothing else; found: ${hosts:-none}. Not changed." >&2; exit 1; }
  if [[ "$DRY_RUN" != "1" ]]; then
    echo "${ADMIN_USER} will connect from ${ADMIN_HOST} only (homelab LAN and VPN). Rights and password stay."
    echo "From rasppi5-01 itself, use \`sudo mysql\`: 127.0.0.1 is not inside ${ADMIN_HOST}."
    confirm "narrow"
  fi
  run_sql "RENAME USER '${ADMIN_USER}'@'%' TO '${ADMIN_USER}'@'${ADMIN_HOST}';"
  echo "Done. ${ADMIN_USER} now:"
  query "SHOW GRANTS FOR '${ADMIN_USER}'@'${ADMIN_HOST}'" | sed 's/^/  /'
}

drop_codex() {
  local hosts host sql=""
  hosts="$(hosts_for "$CODEX_USER")"
  if [[ -z "$hosts" ]]; then
    echo "No MySQL user named ${CODEX_USER}; nothing to do."
    exit 0
  fi
  echo "Connections as ${CODEX_USER} since MySQL started (address, open now, total):"
  query "SELECT HOST, CURRENT_CONNECTIONS, TOTAL_CONNECTIONS FROM performance_schema.accounts WHERE USER = '${CODEX_USER}'" | sed 's/^/  /'
  while read -r host; do
    sql+="DROP USER '${CODEX_USER}'@'${host}';
"
  done <<<"$hosts"
  [[ "$DRY_RUN" == "1" ]] || confirm "drop"
  run_sql "$sql"
  echo "Done. ${CODEX_USER} is dropped."
}

case "$ACTION" in
  legomgr)       narrow_legomgr ;;
  tvattima-host) narrow_admin_host ;;
  drop-codex)    drop_codex ;;
  *) echo "Usage: bash narrow-accounts.sh legomgr | tvattima-host | drop-codex" >&2; exit 1 ;;
esac
