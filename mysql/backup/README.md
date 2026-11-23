# MySQL backup: a nightly dump kept off rasppi5-01 (HOMELAB-125)

The MySQL server on rasppi5-01 holds every LCMS database, including the live production one. Until
this was added it had no backup at all. Every night a job dumps each application schema and stores
the dumps in the PROD object store (`silo-prod`), which runs on other machines.

This is the simple solution the owner asked for on 2026-11-20. The long-term target is a rack
NAS (TrueNAS); when it exists, the dumps should also go there. See [Limits](#limits).

| | |
|---|---|
| What is backed up | `lego_prod_legacy`, `lego_prod`, `lego_sandbox`, `lego_dev`, `marketplace_pricing`. Not `marketplace_pricing_scratch` (trial builds). |
| When | Every night at 03:00 Eastern: CronJob `mysql-backup/mysql-backup` |
| How | `mysqldump --single-transaction`, one gzip file per schema, each with the binary log position it was taken at |
| Where | Bucket `mysql-backups` in `silo-prod` (console: https://console.silo.prod.internal.legohunter.io) |
| Kept for | `daily/` 14 days, `weekly/` (the Sunday copy) 8 weeks, `latest/` overwritten each night |
| MySQL account | `lcms_backup`, read-only |
| Alerts | `MysqlBackupMissing`, `MysqlBackupNotReporting`, to Pushover |

## Files

| File | What it is |
|---|---|
| `setup-mysql-backup-account.sh` | Creates the read-only account `lcms_backup`. The owner runs it on rasppi5-01. |
| `01-namespace.yaml` | Namespace `mysql-backup`. |
| `02-external-secrets.yaml` | The account's password and the bucket user's key, from Infisical Production. |
| `03-bucket-expiry-job.yaml` | Sets the bucket's expiry rules. Run once. |
| `job/` | The nightly CronJob: `dump.sh` (step 1) and `upload.sh` (step 2). |
| `restore-test/` | A Job that loads the stored dumps into a throwaway MySQL and compares them with the live schemas. |

The bucket, its user and the user's policy are in `../../silo/silo-prod/03-silo-prod-values.yaml`.
The alert rules are in `../../prometheus/prometheus-alerting-values.yaml`.

## How a night goes

1. **Dump.** For each schema, `mysqldump` takes one consistent snapshot without locking the tables
   (they are InnoDB) and writes a gzip file. A dump counts only when it is complete. One schema
   failing does not stop the others.
2. **Upload.** Each complete dump is put in the bucket as `daily/<schema>/<schema>-<UTC time>.sql.gz`
   and as `latest/<schema>.sql.gz`, and on Sundays also under `weekly/`. Each upload is checked
   against the MD5 the store answers with.
3. **Report.** For each schema stored, the job tells Prometheus when, how big and how long
   (`mysql_backup_last_success_timestamp_seconds`, `mysql_backup_size_bytes`,
   `mysql_backup_dump_duration_seconds`, each with a `schema` label).
4. The job fails when any schema was not stored. The store deletes old dumps by its own rules; the
   job's user cannot delete.

The job runs in the cluster, so it does not run while the cluster is down. If the cluster comes
back within six hours of 03:00, that night's run still starts.

## Runbook

### A backup is missing

`MysqlBackupMissing` names the schema. `MysqlBackupNotReporting` means fewer than five schemas have
reported for over a day.

```
kubectl get cronjob,jobs -n mysql-backup
kubectl logs -n mysql-backup job/<the latest mysql-backup job> -c dump
kubectl logs -n mysql-backup job/<the latest mysql-backup job> -c upload
```

| Log line | Meaning |
|---|---|
| `mysql_backup.dump_failed schema=… message=…` | `mysqldump` failed; the message is its error. `Access denied`: the password in Infisical does not match the account, or a schema was added without re-running `setup-mysql-backup-account.sh`. `Can't connect`: MySQL or the network is down. |
| `mysql_backup.upload_failed key=…` | The object store refused the file or answered with a different MD5. Check `silo-prod` is healthy and the Secret `mysql-backup-s3` is synced. |
| `mysql_backup.report_failed` | The dump is stored, but the Pushgateway could not be told. The alert will fire although the backup exists. |
| no job at all for last night | The cluster was down at 03:00 and for six hours after, or the CronJob is suspended. |

To run a backup now: `kubectl create job --from=cronjob/mysql-backup mysql-backup-manual -n mysql-backup`.

### Restore one schema

Restore into a **new schema name** first, check it, and only then put it in place. Never load a
dump straight over a schema that is in use.

1. Get the dump: in the Silo console, bucket `mysql-backups`, download
   `daily/<schema>/<schema>-<time>.sql.gz` (or `latest/<schema>.sql.gz`), and copy it to rasppi5-01.
2. Load it into a new schema (the dump has no `CREATE DATABASE` or `USE`, so it goes where you
   point it):
   ```
   sudo mysql -e "CREATE DATABASE lego_prod_restore DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"
   gunzip -c lego_prod-<time>.sql.gz | sudo mysql lego_prod_restore
   ```
3. Check it: table count and the row counts of the tables that matter.
4. Stop the services that use the schema, then swap the restored tables in (rename the tables, or
   drop the damaged schema and reload the dump under the real name), and start the services.

### Restore to a point in time

A dump is the state at 03:00. The binary logs on rasppi5-01 (kept 30 days) hold every change
since, so the two together can rebuild a schema as it was at a later moment, for example just
before a mistake. This procedure has not been rehearsed.

1. Restore the last dump **before** that moment into a new schema, as above.
2. Read the position the dump was taken at (it is a comment near the top of the dump):
   ```
   gunzip -c lego_prod-<time>.sql.gz | grep -m 1 'CHANGE REPLICATION SOURCE TO'
   ```
   It gives `SOURCE_LOG_FILE` (for example `binlog.000123`) and `SOURCE_LOG_POS`.
3. Replay the binary logs from that position up to just before the moment, for that schema only,
   into the restored schema:
   ```
   sudo mysqlbinlog --start-position=<SOURCE_LOG_POS> --stop-datetime="2026-12-01 14:29:00" \
       --database=lego_prod --rewrite-db='lego_prod->lego_prod_restore' \
       /var/lib/mysql/<SOURCE_LOG_FILE> /var/lib/mysql/<every later binlog file, in order> \
     | sudo mysql
   ```
   `--start-position` applies to the first file only. `--stop-datetime` is in the server's time
   zone (Eastern).

This needs the binary logs, which are on rasppi5-01's own disk. If that disk is lost, the newest
state that can be restored is the last dump.

### Restore test

Proves the stored dumps load. Run it after setting the backup up, and from time to time:

```
kubectl delete job mysql-restore-test -n mysql-backup --ignore-not-found
kubectl apply -k mysql/backup/restore-test
kubectl logs -n mysql-backup job/mysql-restore-test -f
```

It starts a throwaway MySQL inside its own pod, loads `latest/<schema>.sql.gz` of every schema, and
compares each with the live schema: it fails when a dump does not load or the tables are not the
same. Row counts are listed where they differ; tables written to all day are expected to differ,
because the live schema has moved on since 03:00. Nothing is written to rasppi5-01.

## Install

### 1. MySQL account (owner, on rasppi5-01)

```
DRY_RUN=1 bash setup-mysql-backup-account.sh     # prints the SQL, changes nothing
bash setup-mysql-backup-account.sh               # press Enter to generate the password
```

### 2. Infisical, environment Production (owner)

- `mysql-backup`: the line the script prints, `{"username": "lcms_backup", "password": "…"}`
- `silo-prod-mysql-backup`: `{"access_key": "lcms-mysql-backup", "secret_key": "<long random>"}`.
  `access_key` must be exactly `lcms-mysql-backup`. For the secret key, 40 random letters and
  digits, for example from `openssl rand -hex 20`.

### 3. Cluster (`lcms-admin`, on the owner's authorization)

```
kubectl apply -f mysql/backup/01-namespace.yaml
kubectl apply -f mysql/backup/02-external-secrets.yaml
kubectl get externalsecret -n mysql-backup          # expect: SecretSynced, twice
kubectl get externalsecret silo-prod-mysql-backup-user -n silo-prod

# The bucket, its user and policy: the silo-prod Helm upgrade (see ../../silo/silo-prod/README.md, step 4).
# Then the bucket's expiry rules:
kubectl apply -f mysql/backup/03-bucket-expiry-job.yaml
kubectl logs -n silo-prod job/mysql-backups-expiry

# The nightly job, a first run by hand, and the restore test:
kubectl apply -k mysql/backup/job
kubectl create job --from=cronjob/mysql-backup mysql-backup-first -n mysql-backup
kubectl logs -n mysql-backup job/mysql-backup-first -c dump
kubectl logs -n mysql-backup job/mysql-backup-first -c upload

# The alert rules: the prometheus Helm upgrade (see ../../prometheus/README.md).
```

### Adding a schema to the backup

Add it to `SCHEMAS` in `job/kustomization.yaml` and in `setup-mysql-backup-account.sh`, re-run that
script (type `keep` at the prompt), apply the job again, and change the `5` in the rule
`MysqlBackupNotReporting`.

## Limits

- **Same rack.** `silo-prod` is on other machines than rasppi5-01 but in the same rack. This covers
  losing rasppi5-01's disk or the host. It does not cover losing the rack. An off-site or NAS copy
  is part of the later, broader solution.
- **Not encrypted.** The dumps hold everything in the databases, including customer names and
  addresses from orders. They are readable by the backup user and the store's root user only.
- **Up to a day of changes.** Without the binary logs, a restore gives the state at 03:00.
- **The cluster must be up at night.** Nothing runs on rasppi5-01 itself.
- **A moment of read lock.** Recording the binary log position takes a global read lock for an
  instant at the start of each dump. On databases of this size it is not noticeable.
