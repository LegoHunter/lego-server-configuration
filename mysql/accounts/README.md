# MySQL accounts (HOMELAB-126)

Who may do what on the MySQL server on rasppi5-01, and the scripts that set it up. The reasoning,
the inventory of what connects, and the alternatives that were considered are in
[ANALYSIS.md](ANALYSIS.md).

## The accounts

All accounts connect from `10.0.%` (homelab LAN and VPN) unless noted.

| Account | Rights | Used by | Password kept in |
|---|---|---|---|
| `tvattima` | Everything, every schema | The owner | The owner |
| `legomgr` (from any address) | `ALL` on `lego_prod_legacy` only | Legacy command-line tools (`lego-command`) | `D:\dev\config\database-configuration.yml`, key `rasppi5-01-lego-prod-legacy` |
| `lcms_sandbox_app` | Data rights on `lego_sandbox`; pricing rights | SANDBOX services; services run from IntelliJ | Infisical Sandbox and `D:\dev\config`, key `rasppi5-01-lego-sandbox` |
| `lcms_dev_app` | Data rights on `lego_dev`; pricing rights | DEV services | Infisical Development, key `rasppi5-01-lego-dev` |
| `lcms_prod_app` | Data rights on `lego_prod`; pricing rights | PROD services | Infisical Production, key `rasppi5-01-lego-prod` |
| `lcms_pricing_crawler` | Data rights on `marketplace_pricing` | The price crawler (inside the SANDBOX ingress today) | Infisical Sandbox, key `rasppi5-01-marketplace-pricing-crawler` |
| `lcms_sandbox_deployer` | `ALL` on `lego_sandbox` | Deployer, profile `sandbox` | `D:\dev\config`, key `rasppi5-01-lego-sandbox-deployer` |
| `lcms_dev_deployer` | `ALL` on `lego_dev` | Deployer, profile `dev` | `D:\dev\config`, key `rasppi5-01-lego-dev-deployer` |
| `lcms_prod_deployer` | `ALL` on `lego_prod` | Deployer, profile `prod` | `D:\dev\config`, key `rasppi5-01-lego-prod-deployer` |
| `lcms_pricing_deployer` | `ALL` on `marketplace_pricing` and `marketplace_pricing_scratch` | Deployer, pricing profiles | `D:\dev\config`, keys `rasppi5-01-marketplace-pricing` and `-scratch` |
| `lcms_backup` | Read-only on the backed-up schemas | Nightly backup ([../backup](../backup/README.md)) | Infisical Production |
| `claude_ro`, `claude_rw`, `claude_legacy_ro` | See the workspace repository, `00-workspace/ops/claude-access` | Claude | The owner's PC |

- **Data rights** are `SELECT`, `INSERT`, `UPDATE`, `DELETE`: no table changes, no granting.
- **Pricing rights** of an application account: `SELECT` on `marketplace_pricing`; `INSERT`,
  `UPDATE`, `DELETE` on `want_list_item`; `INSERT` on `canonical_item`.
- The keys are entries under `lego.databases` in `database-configuration.yml`. Each holds a JDBC
  URL, a user name and a password. A service or the deployer names the key it uses.
- `lcms_prod_app` and `lcms_prod_deployer` are created by `setup-lego-prod.sh` in the workspace
  repository (`00-workspace/ops/lego-prod`).

## Scripts

The owner runs them on rasppi5-01. Each has `DRY_RUN=1`, and none prints an existing password.

| Script | What it does |
|---|---|
| `inventory-mysql-accounts.sh` | Read-only. Every account, its grants, and connections per account and address since MySQL started. |
| `setup-mysql-accounts.sh` | Creates the `lcms_*` application, deployer and crawler accounts for SANDBOX, DEV and pricing with exactly their rights. Does not touch `legomgr` or `tvattima`. Safe to re-run. |
| `narrow-accounts.sh legomgr` | Leaves `legomgr` with `lego_prod_legacy` only. Saves its old grants as SQL first. |
| `narrow-accounts.sh tvattima-host` | `tvattima` connects from `10.0.%` instead of from anywhere. |
| `narrow-accounts.sh drop-codex` | Drops `codex_sandbox_ro`. |

Copy them over with:

```
scp mysql/accounts/*.sh rasppi5-01:~/
```

## Rollout

Each step can be undone on its own. Nothing is taken away before step 8.

| # | Step | Who | Check | Undo |
|---|---|---|---|---|
| 1 | `bash inventory-mysql-accounts.sh > inventory.txt` | Owner | Send the file. It holds no passwords. | |
| 2 | `DRY_RUN=1 ROTATE=lcms_pricing_crawler bash setup-mysql-accounts.sh`, then the same without `DRY_RUN=1` | Owner | Six accounts with the grants in the table above. Passwords are shown once. | Drop the new accounts |
| 3 | **Crawler key.** In Infisical Sandbox, `database-configuration.yml`: add the key `rasppi5-01-marketplace-pricing-crawler` (copy the shape of `rasppi5-01-lego-sandbox`; schema in the URL `marketplace_pricing`, user `lcms_pricing_crawler`). | Owner | | Remove the key |
| 4 | **Deploy the ingress change** that gives the crawler its own connection (push of the `lego-data-ingress` branch deploys to SANDBOX). | Claude | Pod log: `The price crawler uses its own connection … user=lcms_pricing_crawler` | Redeploy the previous image |
| 5 | **SANDBOX.** In the same Infisical file, key `rasppi5-01-lego-sandbox`: user `lcms_sandbox_app` and its password. Restart the two SANDBOX services. | Owner; Claude restarts on authorization | Pod logs: `user=lcms_sandbox_app`; no `command denied`; the want-list and crawl jobs run | Put `legomgr` back, restart |
| 6 | **DEV.** Infisical Development, key `rasppi5-01-lego-dev`: user `lcms_dev_app`. Restart the two DEV services. | as step 5 | as step 5, with `lcms_dev_app` | as step 5 |
| 7 | **The PC**, `D:\dev\config\database-configuration.yml`: | Owner | Deployer `STATUS` run on `sandbox`, `dev` and `marketplace-pricing` | Restore the file |
| | - key `rasppi5-01-lego-sandbox` → `lcms_sandbox_app` | | | |
| | - new keys `rasppi5-01-lego-sandbox-deployer` and `rasppi5-01-lego-dev-deployer` | | | |
| | - keys `rasppi5-01-marketplace-pricing` and `-scratch` → `lcms_pricing_deployer` | | | |
| | - new key `rasppi5-01-marketplace-pricing-crawler`, only if the `sandbox` profile is run on the PC | | | |
| | - key `rasppi5-01-lego-dev` → remove, or `lcms_dev_app` if DEV is ever run from the PC | | | |
| | - key `rasppi5-01-lego-prod-legacy`: **do not change** | | | |
| | - IntelliJ data source "lego_sandbox (rasppi5-01)" → `tvattima` | | | |
| 8 | **Watch**, at least one full day after step 7: `bash inventory-mysql-accounts.sh`, section 3. | Owner runs, Claude reads | `legomgr` has no open connections from `10.0.2.x` | |
| 9 | `DRY_RUN=1 bash narrow-accounts.sh legomgr`, then without `DRY_RUN=1`. Not while an order is being processed. | Owner | `legomgr` has one grant: `lego_prod_legacy` | `sudo mysql < ~/legomgr-grants-before-<time>.sql` |
| 10 | One read-only `lego-command` command. | Owner | It works | Step 9's undo |
| 11 | `bash narrow-accounts.sh tvattima-host` and `bash narrow-accounts.sh drop-codex` | Owner | | Printed by the script |
| 12 | `bash setup-lego-prod.sh`, answering `keep` twice | Owner | Other accounts reaching `lego_prod`: `tvattima` (by design) and read-only accounts | |

After step 5, delete the Infisical Sandbox secret `marketplace-pricing-crawler-password`: step 2
gave the crawler a new password, which now lives in the key from step 3.

Steps 5 and 6 need a restart because a service reads its account only when it starts.

## Later changes

- **A new schema or account:** add it to `ACCOUNTS` in `setup-mysql-accounts.sh` and re-run.
- **A new password for one account:** `ROTATE="<account>" bash setup-mysql-accounts.sh`, put it
  where the table says, restart what uses it.
- **The crawler moves to PROD:** give `lcms_pricing_crawler` a new password (`ROTATE`), put the key
  in Infisical Production, and move `lego.marketplace-pricing.crawler.database-key-name` together
  with `crawl.enabled` in `lego-data-ingress`. Remove the key from Infisical Sandbox.
- **`setup-claude-mysql-users.sh` and `setup-lego-prod.sh`** revoke and re-grant their own accounts.
  They do not affect the accounts here, and this script does not affect theirs, except that it
  adds `INSERT` on `canonical_item` to `lcms_prod_app` (also in `setup-lego-prod.sh` since
  HOMELAB-126).
