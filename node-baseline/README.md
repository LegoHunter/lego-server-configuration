# Node baseline (Raspberry Pi 5 fleet)

Every per-node setting the homelab Pis need, kept in one place so a repaved
or rebuilt node gets all of it back. `node-baseline.sh` is idempotent: `check`
reports drift read-only, and `apply` changes only what differs.

```bash
bash node-baseline.sh check                          # all 10 hosts, read-only
bash node-baseline.sh check rasppi5-06               # one host
bash node-baseline.sh apply rasppi5-06               # dry run: what would change
bash node-baseline.sh apply rasppi5-06 --execute     # make it so
```

Run from the workstation. Hosts are SSH aliases (`rasppi5-01` … `rasppi5-10`)
logging in as an account with passwordless sudo (`sysadmin`).

## After repaving or rebuilding a node

1. Install Ubuntu, create `sysadmin` with passwordless sudo, and (for k3s
   nodes) join the cluster as before.
2. `bash node-baseline.sh apply rasppi5-NN --execute`
3. On a k3s node, reboot it once so the kubelet loads the graceful-shutdown
   drop-in.
4. `bash node-baseline.sh check rasppi5-NN` must show no drift.
5. If the node's SSH host key changed, update its pinned
   `ssh_host_key` in the homelab-power-manager config (the HPM shutdown
   refuses a host whose key doesn't match).

## What it manages

| Item | Hosts | Why |
|---|---|---|
| `kubelet.conf.d/50-graceful-shutdown.conf` (`shutdownGracePeriod` 360 s / critical 60 s) | k3s nodes 02–10 | The kubelet stops pods gracefully on `systemctl poweroff`; HPM relies on this instead of draining |
| `logind.conf.d/zz-kubelet-graceful-shutdown.conf` (`InhibitDelayMaxSec=360`) | k3s nodes 02–10 | Lets the kubelet hold shutdown for its grace period; `zz-` sorts after Ubuntu's 30 s unattended-upgrades file |
| `rpi5-macb-workaround.service` (`ethtool tso off sg off`) | all | Reduces the Pi 5 `macb` Ethernet TX stall. Replaces rasppi5-01's older `raspberry-pi-macb-workaround.service` |
| `rpi5-net-watchdog` (script, service, 30 s timer) | all | Recovers from the TX stall when it happens anyway (below) |
| `hpm-node` account, `/etc/sudoers.d/90-hpm-node`, `authorized_keys` | all | homelab-power-manager's poweroff identity: a locked system account whose only sudo right is `/usr/bin/systemctl poweroff`, reachable only with HPM's key from the hpm host (10.0.1.71), with no forwarding or pty |

`files/hpm-node.pub` is HPM's **public** key, generated on the hpm host. Until
it is committed, `check` and `apply` skip `authorized_keys`.

## rpi5-net-watchdog

On 2026-10-28 rasppi5-06 dropped off the network for 20 minutes: the switch
showed a live link and normal PoE draw, the OS and k3s kept running, but no
frame left the NIC, not even ARP, and the kernel logged nothing. That is the
Pi 5 `macb` TX stall, and it happened with the offload workaround in place.

Every 30 s the watchdog pings the gateway and three peers (10.0.2.1, .51, .52,
.55, skipping its own address):

- **Healthy** if any of them answers.
- **No carrier, no action.** A switch or cable outage drops carrier on the
  node, and the fleet must not reboot together because of it. The TX stall
  keeps carrier up.
- **3 minutes** of failure: bounce `eth0` and re-apply the offload workaround.
- **5 minutes**, still failing: graceful `systemctl reboot`, at most **once
  per hour** per node (a clock that jumped backwards counts as recent).
- Nothing happens in the first 5 minutes after boot.

Logs: `journalctl -t rpi5-net-watchdog`. To test the decision logic without
touching the network, run the script with `DRY_RUN=1` and the
`CARRIER_FILE`/`UPTIME_FILE`/`STATE_DIR`/`STAMP_DIR`/`PING` overrides.
