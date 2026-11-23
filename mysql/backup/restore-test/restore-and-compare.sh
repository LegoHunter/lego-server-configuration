#!/bin/bash
# Restore test, step 2 of 2 (HOMELAB-125): load each dump into a throwaway MySQL and compare it with
# the live schema it came from.
#
# Runs in the official mysql image as the main container of the Job mysql-backup/mysql-restore-test.
# The throwaway server lives inside this pod (no network, data in a scratch volume) and is gone
# when the pod ends. Nothing is written to rasppi5-01: the live server is only read, with the
# backup account.
#
# For each schema it prints: the binary log position the dump was taken at, how many tables the
# live schema and the restored copy have, and every table whose row count differs.
#
# The test FAILS when a dump does not load, or when the restored copy does not have exactly the
# live schema's tables. A different ROW COUNT does not fail it: the live schema keeps changing
# after the dump was taken, so tables that are written to all day (sync runs, locks, crawl
# attempts) are expected to differ. Lookup and catalog tables should match exactly; read the list.
#
# Environment: MYSQL_HOST, MYSQL_PORT, SCHEMAS from the ConfigMap mysql-backup-settings;
# MYSQL_USER, MYSQL_PASSWORD from the Secret mysql-backup-db.
set -uo pipefail

DATADIR=/restore/data
SOCKET=/tmp/mysql.sock

CLIENT_CNF=/tmp/client.cnf
( umask 077; : > "$CLIENT_CNF" )
cat > "$CLIENT_CNF" <<CNF
[client]
host=${MYSQL_HOST}
port=${MYSQL_PORT}
user=${MYSQL_USER}
password="${MYSQL_PASSWORD}"
CNF

restored() { mysql --protocol=socket --socket="$SOCKET" -uroot -N -B "$@"; }
live()     { mysql --defaults-extra-file="$CLIENT_CNF" -N -B "$@"; }

echo "restore_test.starting_throwaway_server"
if ! mysqld --initialize-insecure --datadir="$DATADIR" > /tmp/initialize.log 2>&1; then
    echo "restore_test.server_failed step=initialize"; tail -n 20 /tmp/initialize.log; exit 1
fi
mysqld --datadir="$DATADIR" --socket="$SOCKET" --pid-file=/tmp/mysqld.pid --skip-networking \
    --mysqlx=OFF --skip-log-bin --innodb-buffer-pool-size=256M --log-error=/tmp/mysqld.log &
for _ in $(seq 1 60); do
    restored -e "SELECT 1" > /dev/null 2>&1 && break
    sleep 2
done
if ! restored -e "SELECT 1" > /dev/null 2>&1; then
    echo "restore_test.server_failed step=start"; tail -n 20 /tmp/mysqld.log; exit 1
fi

# Prints "<table> <rows>" for every base table of a schema, sorted by table name.
counts() {
    side="$1"; schema="$2"
    statement="$($side -e "SET SESSION group_concat_max_len = 4000000;
        SELECT GROUP_CONCAT(CONCAT('SELECT ''', table_name, ''', COUNT(*) FROM \`', table_schema, '\`.\`', table_name, '\`')
                            ORDER BY table_name SEPARATOR ' UNION ALL ')
          FROM information_schema.tables
         WHERE table_schema = '$schema' AND table_type = 'BASE TABLE'")"
    if [ -z "$statement" ] || [ "$statement" = "NULL" ]; then
        return 0
    fi
    $side -e "$statement" | sort
}

failed=0
for schema in $SCHEMAS; do
    echo
    echo "=== $schema"
    dump="/dumps/$schema.sql.gz"
    echo "dump taken at: $(zcat "$dump" | grep -m 1 'CHANGE REPLICATION SOURCE TO' | sed 's/^-- //')"

    restored -e "CREATE DATABASE \`$schema\`"
    if ! zcat "$dump" | mysql --protocol=socket --socket="$SOCKET" -uroot "$schema" 2> "/tmp/$schema.load.err"; then
        echo "restore_test.load_failed schema=$schema message=$(tr '\n' ' ' < "/tmp/$schema.load.err" | cut -c1-500)"
        failed=1
        continue
    fi

    counts live "$schema" > "/tmp/$schema.live"
    counts restored "$schema" > "/tmp/$schema.restored"
    live_tables=$(wc -l < "/tmp/$schema.live")
    restored_tables=$(wc -l < "/tmp/$schema.restored")
    live_rows=$(awk '{ n += $2 } END { print n + 0 }' "/tmp/$schema.live")
    restored_rows=$(awk '{ n += $2 } END { print n + 0 }' "/tmp/$schema.restored")
    echo "tables: live $live_tables, restored $restored_tables"
    echo "rows:   live $live_rows, restored $restored_rows"

    if [ "$live_tables" -eq 0 ] || ! diff <(cut -f1 "/tmp/$schema.live") <(cut -f1 "/tmp/$schema.restored") > "/tmp/$schema.tables.diff"; then
        echo "restore_test.tables_differ schema=$schema (< live only, > restored only)"
        cat "/tmp/$schema.tables.diff" 2>/dev/null
        failed=1
        continue
    fi

    different="$(join -t "$(printf '\t')" "/tmp/$schema.live" "/tmp/$schema.restored" | awk -F '\t' '$2 != $3 { printf "  %-45s live %s, restored %s\n", $1, $2, $3 }')"
    if [ -n "$different" ]; then
        echo "tables whose row count differs (expected for tables written to since the dump):"
        echo "$different"
    else
        echo "every table has the same row count"
    fi
    echo "restore_test.restored schema=$schema"
done

mysqladmin --protocol=socket --socket="$SOCKET" -uroot shutdown > /dev/null 2>&1
echo
if [ "$failed" = "0" ]; then
    echo "restore_test.passed"
else
    echo "restore_test.failed"
fi
exit "$failed"
