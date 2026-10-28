#!/bin/bash
# rpi5-net-watchdog: recover a Raspberry Pi 5 whose macb Ethernet TX path
# stalls while the link stays up (seen on rasppi5-06, 2026-10-28: carrier up,
# PoE fine, OS and k3s running, but no frame left the NIC, not even ARP).
#
# Run every 30 s by rpi5-net-watchdog.timer. Each run:
#   - does nothing unless eth0 has carrier: a switch outage drops carrier on
#     every node, and the fleet must not reboot together because of it;
#   - is healthy if ANY target answers ping (gateway or a peer);
#   - after BOUNCE_AFTER s of failure, bounces eth0 and re-applies the macb
#     offload workaround;
#   - if still failing REBOOT_AFTER s after the failure began, reboots
#     gracefully, at most once per REBOOT_MIN_INTERVAL s.
# Every decision is logged to the journal (journalctl -t rpi5-net-watchdog).
set -u

IFACE=eth0
TARGETS="10.0.2.1 10.0.2.51 10.0.2.52 10.0.2.55"
BOOT_GRACE=300          # s after boot before acting
BOUNCE_AFTER=180        # s of failure before bouncing eth0
REBOOT_AFTER=300        # s of failure before rebooting
REBOOT_MIN_INTERVAL=3600

# Overridable for testing only.
CARRIER_FILE=${CARRIER_FILE:-/sys/class/net/$IFACE/carrier}
UPTIME_FILE=${UPTIME_FILE:-/proc/uptime}
STATE_DIR=${STATE_DIR:-/run/rpi5-net-watchdog}             # tmpfs: resets every boot
STAMP_DIR=${STAMP_DIR:-/var/lib/rpi5-net-watchdog}         # survives reboots
DRY_RUN=${DRY_RUN:-0}
PING=${PING:-ping}

log() { logger -t rpi5-net-watchdog -- "$*" 2>/dev/null || true; echo "rpi5-net-watchdog: $*"; }
act() {
	if [ "$DRY_RUN" = 1 ]; then log "DRY-RUN would: $*"; else "$@"; fi
}

mkdir -p "$STATE_DIR" "$STAMP_DIR"
up=$(cut -d. -f1 "$UPTIME_FILE")
[ "$up" -lt "$BOOT_GRACE" ] && exit 0

if [ "$(cat "$CARRIER_FILE" 2>/dev/null)" != 1 ]; then
	# No carrier: a cable, switch or power problem, not a TX stall. Not ours.
	rm -f "$STATE_DIR/fail_since" "$STATE_DIR/bounced"
	exit 0
fi

own=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{split($4, a, "/"); print a[1]}')
for target in $TARGETS; do
	[ "$target" = "$own" ] && continue
	if "$PING" -c 1 -W 2 -I "$IFACE" "$target" >/dev/null 2>&1; then
		if [ -e "$STATE_DIR/fail_since" ]; then
			log "network recovered ($target answers) after $((up - $(cat "$STATE_DIR/fail_since"))) s"
		fi
		rm -f "$STATE_DIR/fail_since" "$STATE_DIR/bounced"
		exit 0
	fi
done

[ -e "$STATE_DIR/fail_since" ] || { echo "$up" > "$STATE_DIR/fail_since"; log "no target answers ($TARGETS) with carrier up; watching"; }
elapsed=$((up - $(cat "$STATE_DIR/fail_since")))

if [ "$elapsed" -ge "$BOUNCE_AFTER" ] && [ ! -e "$STATE_DIR/bounced" ]; then
	log "TX stall suspected for ${elapsed} s: bouncing $IFACE and re-applying the offload workaround"
	act ip link set "$IFACE" down
	act sleep 2
	act ip link set "$IFACE" up
	act /usr/sbin/ethtool --features "$IFACE" tso off sg off
	echo "$up" > "$STATE_DIR/bounced"
	exit 0
fi

if [ "$elapsed" -ge "$REBOOT_AFTER" ] && [ -e "$STATE_DIR/bounced" ]; then
	now=$(date +%s)
	last=$(cat "$STAMP_DIR/last-reboot" 2>/dev/null || echo 0)
	# A clock behind the stamp (RTC lost time) counts as recent: never loop.
	if [ "$now" -lt "$last" ] || [ $((now - last)) -lt "$REBOOT_MIN_INTERVAL" ]; then
		log "still no network after ${elapsed} s, but rebooted within the last ${REBOOT_MIN_INTERVAL} s; not rebooting again"
		exit 0
	fi
	log "still no network ${elapsed} s after the stall began, even after the $IFACE bounce: rebooting"
	echo "$now" > "$STAMP_DIR/last-reboot"
	act systemctl reboot
fi
exit 0
