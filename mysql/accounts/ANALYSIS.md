# MySQL accounts: analysis and target model (HOMELAB-126)

Written 2026-11-24, before any change. The owner decided the same day; see
[Decisions taken](#decisions-taken). What was built from it, and the rollout as it is carried out,
is in [README.md](README.md). Where the two differ, the README is current.

## The owner's goals

1. Take `legomgr` out of every LCMS service, job and tool in SANDBOX, DEV and PROD.
2. Keep `tvattima` as the administration account: everything, in every schema.
3. Give each environment (SANDBOX, DEV, PROD) and `marketplace_pricing` its own application
   account, with data rights only (`SELECT`, `INSERT`, `UPDATE`, `DELETE`).
4. Keep `legomgr` for `lego_prod_legacy`, so the legacy command-line tools keep working with no
   code change. A live BrickLink order must stay processable at any time.

## Summary

- **The goals fit the code as it is.** Every service picks its account from one connection key in
  `database-configuration.yml`. Changing the account is a change to that file (Infisical for the
  pods, `D:\dev\config` for the owner's PC). No service code changes.
- **Data rights are enough for the services.** No service runs DDL, calls a stored routine or uses
  a temporary table, and the schemas hold no routines, triggers or views.
- **The deployer is the exception.** It builds and changes tables, so it needs its own accounts
  with DDL. PROD already has one (`lcms_prod_deployer`); SANDBOX, DEV and `marketplace_pricing`
  use `legomgr` today.
- **Two things work today only because `legomgr` can do everything:**
  - The want-list job inserts into `marketplace_pricing.canonical_item`. The grants script gives
    environment accounts write access to `want_list_item` only.
  - The price crawler runs inside the SANDBOX ingress service, on that service's own connection,
    and writes six `marketplace_pricing` tables.
  Both would fail under a data-only account unless the new grants cover them. They would also fail
  in PROD with `lcms_prod_app` as it was created.
- **`legomgr` can be narrowed without touching the legacy tools.** They use one key,
  `rasppi5-01-lego-prod-legacy`. `legomgr` keeps its name and password and loses every schema
  except `lego_prod_legacy`.
- **The cut-over can be done with no outage and can be undone at each step:** add the new
  accounts, switch one environment at a time, watch that `legomgr` has no connections left from
  the cluster, and only then narrow it.

Six decisions were needed from the owner; see [Decisions](#decisions).

## Decisions taken

The owner, 2026-11-24:

1. **Deployers:** three new accounts, one per schema.
2. **Crawler:** its own connection now, as `lcms_pricing_crawler`, as part of this ticket. The
   environment accounts therefore get no crawler rights. Built in `lego-data` (the second
   connection) and `lego-data-ingress` (the crawler uses it).
3. **Runs from IntelliJ:** the SANDBOX key on the PC names `lcms_sandbox_app`. The deployer gets
   its own key names for `sandbox` and `dev`.
4. **`tvattima`'s host:** narrowed to `10.0.%`.
5. **`legomgr`'s host:** left as it is.
6. **`codex_sandbox_ro`:** dropped as part of this ticket.

Correction to the text below: `lcms_prod_app` already had `SELECT` on `marketplace_pricing` and
the writes on `want_list_item` (from `setup-lego-prod.sh`). It lacked only `INSERT` on
`canonical_item`.

## What was checked, and what could not be

| Checked | How |
|---|---|
| Which account key each service uses | Source: `spring.datasource.database-key-name` in every repository |
| Which keys the running pods hold | Pod logs: each pod loads exactly one key, its own environment's |
| What runs in the cluster | Workloads in `services-sandbox`, `services-dev`, `services-prod` (read-only) |
| What SQL the services run | Source: the MyBatis mappers in `lego-data`; the service repositories |
| Routines, triggers, views | `information_schema`, as `claude_ro`: none in `lego_sandbox`, `lego_dev`, `lego_prod`, `marketplace_pricing` |

| Not checked | Why | Who can |
|---|---|---|
| The exact grants of `legomgr`, `tvattima` and every other account | `claude_ro` cannot read `mysql.user` | Owner, on rasppi5-01 (step 0 below) |
| Which user each key in `D:\dev\config\database-configuration.yml` names | It is a credential file; it was not read | Owner |
| Which user each key in Infisical names | Secret values are not read | Owner |
| Whether `lcms_prod_app` has any right on `marketplace_pricing` | Needs `mysql.user` | Owner (step 0) |
| Routines, triggers, views in `lego_prod_legacy` | Outside `claude_ro` | Owner (step 0) |

What is known about the two accounts comes from the run of `setup-lego-prod.sh` on 2026-11-20:
`legomgr@%` and `tvattima@%` both hold server-wide write rights. A playbook on the owner's PC
(`ansible-files/ansible/mysql-setup.yml`, not in source control) creates `legomgr` with
`ALL` on `*.*` and `GRANT OPTION`, from any host; that is taken as the likely current state until
step 0 confirms it.

## Everything that connects to MySQL

### Kubernetes

| Namespace | Workload | Key | Account today |
|---|---|---|---|
| `services-sandbox` | `lego-data-service` | `rasppi5-01-lego-sandbox` | `legomgr` |
| `services-sandbox` | `lego-data-ingress` (also runs the price crawler) | `rasppi5-01-lego-sandbox` | `legomgr` |
| `services-dev` | `lego-data-service` | `rasppi5-01-lego-dev` | `legomgr` |
| `services-dev` | `lego-data-ingress` | `rasppi5-01-lego-dev` | `legomgr` |
| `services-prod` | `lego-data-service` | `rasppi5-01-lego-prod` | `lcms_prod_app` |
| `mysql-backup` | CronJob `mysql-backup`, Job `mysql-restore-test` | (own Secret) | `lcms_backup`, read-only |

- `bricklink-web-gateway` runs in SANDBOX and DEV and has no database connection.
- There are no CronJobs in the services namespaces. The scheduled jobs (order poll, reprice,
  want list, crawler, image sync and the rest) run inside `lego-data-ingress`.
- `lego-data-ingress` is not deployed in PROD yet.
- The accounts in the "today" column for SANDBOX and DEV are from earlier owner statements, not
  read from Infisical.

### The owner's PC

| Program | Key | Account today | After |
|---|---|---|---|
| `lego-command` (live PROD CLI) | `rasppi5-01-lego-prod-legacy` | `legomgr` (to confirm) | **unchanged** |
| `bricklink-api-example` | `rasppi5-01-lego-prod-legacy` | `legomgr` (to confirm) | **unchanged** |
| `lego-database-deployer`, profiles `sandbox`, `dev` | `rasppi5-01-lego-sandbox`, `-dev` | `legomgr` | a deployer account |
| `lego-database-deployer`, profiles `marketplace-pricing`, `-scratch` | `rasppi5-01-marketplace-pricing`, `-scratch` | `legomgr` | a deployer account |
| `lego-database-deployer`, profile `prod` | `rasppi5-01-lego-prod-deployer` | `lcms_prod_deployer` | unchanged |
| Services run from IntelliJ (`local`, `sandbox` profiles) | `rasppi5-01-lego-sandbox` | `legomgr` | see decision 3 |
| `lego-data-migration` (not deployed) | source `…-lego-prod-legacy`, target `…-lego-sandbox` | `legomgr` | see decision 3 |
| `lego-data-service` seed CLI, legacy export | its own option file | (to confirm) | unchanged |
| IntelliJ data source "lego_sandbox (rasppi5-01)" | | `legomgr` | `tvattima` |
| IntelliJ data source "CODEX-RO-lego-sandbox" | | `codex_sandbox_ro` | see decision 6 |
| Claude | option files in `D:\dev\config\claude-access` | `claude_ro`, `claude_rw`, `claude_legacy_ro` | unchanged |

One file on the PC serves the deployer, the IntelliJ runs and the legacy tools:
`D:\dev\config\database-configuration.yml`. The legacy key in it is the one entry that must not
change.

Not active, listed for completeness: `lego-job-app` and `lego-sandbox-service` name the SANDBOX
key and are not deployed.

### Accounts known to exist

`root` (socket only), `legomgr`, `tvattima`, `lcms_prod_app`, `lcms_prod_deployer`,
`lcms_pricing_crawler` (created by HOMELAB-31, not used by anything today), `lcms_backup`,
`claude_ro`, `claude_rw`, `claude_legacy_ro`, `codex_sandbox_ro`. Step 0 lists any others.

## What the services need

### In their own schema

`SELECT`, `INSERT`, `UPDATE`, `DELETE`. Checked in the source of `lego-data`, `lego-data-ingress`
and `lego-data-service`: no `CREATE`, `ALTER`, `DROP` or `TRUNCATE`, no temporary tables, no
`LOCK TABLES`, no `LOAD DATA`, no stored routine calls, no Liquibase or Flyway inside a service.
The job locks (ShedLock) are rows in an existing table.

### In `marketplace_pricing`

The services reach it through their own connection, as `marketplace_pricing.<table>`. There is no
second connection.

| Table | Every environment (want-list job) | The one service that runs the crawler |
|---|---|---|
| all tables | `SELECT` | `SELECT` |
| `want_list_item` | `INSERT`, `UPDATE`, `DELETE` | same |
| `canonical_item` | `INSERT` | `INSERT`, `UPDATE` |
| `marketplace_item` | | `INSERT`, `UPDATE` |
| `crawl_target` | | `INSERT`, `UPDATE` |
| `crawl_attempt` | | `INSERT`, `UPDATE` |
| `market_snapshot` | | `INSERT` |
| `market_listing` | | `INSERT` |

The grants script (`00-workspace/ops/marketplace-pricing/setup-marketplace-pricing-grants.sh`)
gives environment accounts `SELECT` plus writes on `want_list_item`. It lacks `INSERT` on
`canonical_item`. It has never mattered, because every environment account so far was `legomgr`.

The crawler runs in SANDBOX today and is meant to move to PROD. Its rights therefore belong to
whichever environment account runs it; see decision 2.

## Target model

Account names follow the two that exist for PROD. All new accounts connect from `10.0.%`.

| Account | Rights | Used by |
|---|---|---|
| `tvattima` | Everything, every schema, with `GRANT OPTION` (unchanged) | The owner |
| `legomgr` | `ALL` on `lego_prod_legacy` only. Same name, same password. | Legacy CLI tools |
| `lcms_sandbox_app` (new) | Data rights on `lego_sandbox`; pricing rights (table above) | SANDBOX services |
| `lcms_dev_app` (new) | Data rights on `lego_dev`; pricing rights | DEV services |
| `lcms_prod_app` | Data rights on `lego_prod` (has them); pricing rights (to add) | PROD services |
| `lcms_sandbox_deployer` (new) | `ALL` on `lego_sandbox` | Deployer, profile `sandbox` |
| `lcms_dev_deployer` (new) | `ALL` on `lego_dev` | Deployer, profile `dev` |
| `lcms_prod_deployer` | `ALL` on `lego_prod` (unchanged) | Deployer, profile `prod` |
| `lcms_pricing_deployer` (new) | `ALL` on `marketplace_pricing` and `marketplace_pricing_scratch` | Deployer, pricing profiles |
| `lcms_pricing_crawler` | Data rights on `marketplace_pricing` (unchanged) | Nothing today; see decision 2 |
| `lcms_backup`, `claude_*` | unchanged | Backup, Claude |

What this gives:

- A SANDBOX or DEV service cannot read or write `lego_prod` or `lego_prod_legacy`, and cannot
  touch the other lower environment.
- No service account can change a table's structure or grant rights.
- The legacy tools can no longer reach the new schemas, and nothing new can reach the legacy one.
- `legomgr` loses `GRANT OPTION` and every server-wide right.

Where each password lives:

| Account | Password kept in |
|---|---|
| `lcms_sandbox_app` | Infisical Sandbox, `database-configuration.yml`; and the owner's PC if decision 3 says so |
| `lcms_dev_app` | Infisical Development, `database-configuration.yml` |
| `lcms_prod_app` | Infisical Production (as today) |
| the deployer accounts | `D:\dev\config\database-configuration.yml` only |
| `legomgr` | `D:\dev\config\database-configuration.yml`, legacy key only. Removed from Infisical Sandbox and Development. |

No password is copied between environments: each account is created with its own.

## Decisions

1. **Deployer accounts for the lower environments.**
   - *Recommended:* three new accounts as in the table (`lcms_sandbox_deployer`,
     `lcms_dev_deployer`, `lcms_pricing_deployer`). Each can change one thing, as in PROD.
   - *Simpler:* the deployer's lower-environment keys use `tvattima`. No new accounts, but the
     administration password sits in a file that programs read, and a wrong profile is stopped
     only by the deployer's own schema guard.
2. **The crawler's rights.**
   - *Recommended now:* grant the crawler's table rights to `lcms_sandbox_app`, because the
     crawler runs inside the SANDBOX ingress. No code change. When the crawler moves to PROD, the
     same grants move to `lcms_prod_app` and are revoked from SANDBOX.
   - *Later, cleaner:* a second connection in `lego-data-ingress` for the crawler, as
     `lcms_pricing_crawler`. That is a code change and a new ticket. Until then
     `lcms_pricing_crawler` stays unused; it can be kept or dropped.
3. **Services run from IntelliJ, and `lego-data-migration`.** They read the SANDBOX key from
   `D:\dev\config`. Which account should that key name?
   - *Recommended:* `lcms_sandbox_app`, the same as the pods, so a local run behaves like the
     cluster. The deployer then needs its own key names for SANDBOX and DEV (as PROD has
     `…-lego-prod-deployer`): a small change to two deployer profile files.
   - *Alternative:* keep one key per schema on the PC and point it at the deployer account. No
     deployer change, but a local service run then has DDL rights.
4. **`tvattima`'s host.** It is `%` (any address). *Recommended:* `10.0.%`, like every other
   account; the VPN (`10.0.10.x`) is inside it. No rights change.
5. **`legomgr`'s host.** Also `%`. *Recommended:* leave it. Changing it is a second change to the
   one account the legacy tools depend on, for little gain once it reaches one schema only. The
   MySQL port is not open to the internet.
6. **`codex_sandbox_ro`.** Codex is no longer used. *Recommended:* drop the account and the
   IntelliJ data source, and correct the mention in `AGENTS.md`. Not needed for this ticket.

## Rollout

Each step can be undone on its own. Steps 1 to 4 add or switch; only step 6 takes anything away.

| # | Step | Who | Undo |
|---|---|---|---|
| 0 | **Inventory.** A read-only script prints every account, its grants, and how many connections each account has had from each address. It also checks `lego_prod_legacy` for routines, triggers and views. | Owner, on rasppi5-01 | Nothing to undo |
| 1 | **Create the new accounts and grants.** One script, as for PROD: generated passwords shown once, `DRY_RUN`, safe to re-run. Adds the pricing rights to `lcms_prod_app`. Nothing existing changes. | Owner, on rasppi5-01 | Drop the new accounts |
| 2 | **SANDBOX.** Put `lcms_sandbox_app` in Infisical Sandbox, restart the two services, check: services start, the want-list job and the crawler write, the order poll and sync jobs run without `denied` errors. | Owner (Infisical), Claude (restart on authorization, checks) | Put `legomgr` back in Infisical, restart |
| 3 | **DEV.** The same with `lcms_dev_app`. | as step 2 | as step 2 |
| 4 | **The PC.** Deployer keys to the deployer accounts; SANDBOX key per decision 3; IntelliJ data source to `tvattima`. Run the deployer in `STATUS` mode against each schema. | Owner | Restore the file |
| 5 | **Watch.** After at least one full day, the inventory script shows no new `legomgr` connections from the cluster nodes, only from the PC. | Claude asks, owner runs | |
| 6 | **Narrow `legomgr`.** Revoke everything, then grant `ALL` on `lego_prod_legacy`. The script prints the grants before and after and keeps the "before" as SQL that restores them. Do it when no order is being processed. | Owner, on rasppi5-01 | Run the saved "before" SQL |
| 7 | **Check the legacy tools.** One read-only `lego-command` command against `lego_prod_legacy`. | Owner | Step 6's undo |
| 8 | **Confirm.** Re-run `setup-lego-prod.sh` (answer `keep` twice): only `tvattima` (by design) and the read-only accounts reach `lego_prod`. Apply decisions 4 and 6. | Owner | |

Step 6 is where something forgotten would break. Step 5 is the protection: MySQL counts
connections per account and address (`performance_schema.accounts`), so a program still using
`legomgr` shows up before the rights are taken away. The counts start again when MySQL restarts.

## Risks

| Risk | Handling |
|---|---|
| A service needs a right the analysis missed | SANDBOX goes first; a missing right shows as `command denied` in the log. `legomgr` is still intact, so going back is one Infisical edit. |
| The legacy tools use something outside `lego_prod_legacy` | They hold one connection key. Step 0 checks the legacy schema for routines and views that reach elsewhere; step 7 tests after narrowing. |
| A live order arrives during step 6 | The step takes seconds and its undo is one command. Choose a quiet moment. |
| The crawler stops after the SANDBOX switch | Its rights are in decision 2; step 2 checks for a new `crawl_attempt` row. With BrickLink in maintenance, the check is that the job runs without a rights error. |
| The deployer is run with the wrong account | The deployer accounts reach one schema each; the schema guard stays as it is. |

## Found along the way

- **`legomgr`'s password is in a plain-text file** on the owner's PC:
  `ansible-files/ansible/mysql-setup.yml`. The folder is not in source control. The same playbook
  would re-create `legomgr` with rights on everything if it were run again. After this work,
  remove the password from the file and correct the playbook, or delete it.
- **Changing `legomgr`'s password** would be a good idea at some point, because it has been in
  Infisical Sandbox and Development and in that file. It needs one edit to the legacy key in
  `D:\dev\config\database-configuration.yml` and no code change. It is the owner's call and is
  not part of this plan.
- **`../README.md` is out of date.** It shows `legomgr` being created with `GRANT OPTION`. To be
  replaced by a pointer to the new script once it exists.
- **The pricing grants script** needs `INSERT` on `canonical_item` for environment accounts, and
  the crawler's rights as a named option. The new accounts script should take over both.

## Work this turns into

| Repository | Change |
|---|---|
| `lego-server-configuration` | `mysql/accounts/`: the inventory script, the accounts-and-grants script, the narrowing script, a README. Correct `mysql/README.md`. |
| `lego-collection-workspace` | Retire or point `ops/marketplace-pricing/setup-marketplace-pricing-grants.sh` at the new script. Update `ops/lego-prod/README.md` and `AGENTS.md` (accounts, decision 6). |
| `lego-database-deployer` | Only if decision 3 is the recommended option: deployer key names for `sandbox` and `dev`, and the README. |
| Infisical, `D:\dev\config` | The owner's edits in steps 2 to 4. |
| `lego-data-ingress` | Nothing now. A second connection for the crawler is a later ticket (decision 2). |
