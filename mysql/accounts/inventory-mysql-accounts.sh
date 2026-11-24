#!/usr/bin/env bash
# Read-only inventory of the MySQL accounts on rasppi5-01 (HOMELAB-126). Changes nothing.
#
# Prints:
#   1. every account: name, host, whether it is locked, when its password last changed
#   2. the grants of every account that is not a MySQL system account
#   3. connections per account and client address since MySQL started. This is how to see what
#      still connects as legomgr before its rights are narrowed.
#   4. routines, triggers, events and views in the application schemas, and who they run as
#
# No password or password hash is printed.
#
# Run on rasppi5-01 as a user that can `sudo mysql` (root via auth_socket):
#   bash inventory-mysql-accounts.sh
#   bash inventory-mysql-accounts.sh > inventory.txt     # to send the result
#
# Optional:
#   MYSQL_CMD   command used to run SQL as root (default: sudo mysql)
set -euo pipefail

MYSQL_CMD="${MYSQL_CMD:-sudo mysql}"
SYSTEM_ACCOUNTS="'mysql.sys','mysql.session','mysql.infoschema','debian-sys-maint'"
SCHEMAS="'lego_prod_legacy','lego_prod','lego_sandbox','lego_dev','marketplace_pricing','marketplace_pricing_scratch'"

table() {
  $MYSQL_CMD --table -e "$1"
}

echo "=== 1. Accounts"
table "SELECT User, Host, plugin, account_locked AS locked, password_last_changed, max_user_connections AS max_conn
         FROM mysql.user ORDER BY User, Host"

echo
echo "=== 2. Grants"
$MYSQL_CMD -N -B -e "SELECT CONCAT(QUOTE(User), '@', QUOTE(Host)) FROM mysql.user
                      WHERE User NOT IN (${SYSTEM_ACCOUNTS}) ORDER BY User, Host" |
while read -r account; do
  echo "--- ${account}"
  $MYSQL_CMD -N -B -e "SHOW GRANTS FOR ${account}" | sed 's/^/  /'
done

echo
echo "=== 3. Connections per account and address since MySQL started"
table "SELECT NOW() - INTERVAL (SELECT VARIABLE_VALUE FROM performance_schema.global_status
                                 WHERE VARIABLE_NAME = 'Uptime') SECOND AS mysql_started, NOW() AS now"
table "SELECT USER AS user, HOST AS address, CURRENT_CONNECTIONS AS open_now, TOTAL_CONNECTIONS AS total_since_start
         FROM performance_schema.accounts
        WHERE USER IS NOT NULL
        ORDER BY USER, HOST"
echo "Addresses: 10.0.2.x = homelab machines and cluster nodes, 10.0.3.x = trusted PCs, 10.0.10.x = VPN."

echo
echo "=== 4. Routines, triggers, events and views in the application schemas"
table "SELECT ROUTINE_SCHEMA AS schema_name, ROUTINE_TYPE AS kind, ROUTINE_NAME AS name, DEFINER AS runs_as, SECURITY_TYPE AS security
         FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA IN (${SCHEMAS})
       UNION ALL
       SELECT TRIGGER_SCHEMA, 'TRIGGER', TRIGGER_NAME, DEFINER, 'DEFINER'
         FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA IN (${SCHEMAS})
       UNION ALL
       SELECT EVENT_SCHEMA, 'EVENT', EVENT_NAME, DEFINER, 'DEFINER'
         FROM information_schema.EVENTS WHERE EVENT_SCHEMA IN (${SCHEMAS})
       UNION ALL
       SELECT TABLE_SCHEMA, 'VIEW', TABLE_NAME, DEFINER, SECURITY_TYPE
         FROM information_schema.VIEWS WHERE TABLE_SCHEMA IN (${SCHEMAS})
       ORDER BY 1, 2, 3"
echo "(no rows above means there are none)"
