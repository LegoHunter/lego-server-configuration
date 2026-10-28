#!/bin/bash
# node-baseline: the per-node settings every homelab Raspberry Pi needs, in
# one source-controlled place, so a repaved or rebuilt node gets them back.
#
#   bash node-baseline.sh check [HOST...]           read-only drift report (default: all hosts)
#   bash node-baseline.sh apply HOST...             dry run: show what would change
#   bash node-baseline.sh apply HOST... --execute   change only what differs
#
# Run from the workstation; HOST is an SSH alias (rasppi5-01 .. rasppi5-10)
# that logs in as an account with passwordless sudo.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/files"
ALL_HOSTS="rasppi5-01 rasppi5-02 rasppi5-03 rasppi5-04 rasppi5-05 rasppi5-06 rasppi5-07 rasppi5-08 rasppi5-09 rasppi5-10"
HPM_HOST_IP=10.0.1.71   # the HPM key is only accepted from the hpm host

# rasppi5-01: admin host (MySQL, primary DNS), not a k3s node.
# rasppi5-02..04: k3s servers (unit k3s). rasppi5-05..10: k3s agents (unit k3s-node).
role_of() {
	case "$1" in
		rasppi5-01) echo admin ;;
		rasppi5-0[2-4]) echo server ;;
		rasppi5-0[5-9] | rasppi5-10) echo agent ;;
		*) echo unknown ;;
	esac
}

# Managed files: name|roles|local file|remote path|owner:group|mode
FILES="kubelet-graceful-shutdown|server agent|kubelet-50-graceful-shutdown.conf|/var/lib/rancher/k3s/agent/etc/kubelet.conf.d/50-graceful-shutdown.conf|root:root|600
logind-inhibit-delay|server agent|logind-zz-kubelet-graceful-shutdown.conf|/etc/systemd/logind.conf.d/zz-kubelet-graceful-shutdown.conf|root:root|644
macb-workaround-unit|admin server agent|rpi5-macb-workaround.service|/etc/systemd/system/rpi5-macb-workaround.service|root:root|644
net-watchdog-script|admin server agent|rpi5-net-watchdog.sh|/usr/local/sbin/rpi5-net-watchdog|root:root|755
net-watchdog-service|admin server agent|rpi5-net-watchdog.service|/etc/systemd/system/rpi5-net-watchdog.service|root:root|644
net-watchdog-timer|admin server agent|rpi5-net-watchdog.timer|/etc/systemd/system/rpi5-net-watchdog.timer|root:root|644
hpm-node-sudoers|admin server agent|hpm-node.sudoers|/etc/sudoers.d/90-hpm-node|root:root|440"
UNITS="rpi5-macb-workaround.service rpi5-net-watchdog.timer"
LEGACY_UNITS="raspberry-pi-macb-workaround.service"
HPM_HOME=/var/lib/hpm-node

rsh() { timeout 60 ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" "$2"; }

# The hpm public key comes from the hpm host (files/hpm-node.pub). Its
# authorized_keys line is restricted: no forwarding or pty, hpm host only.
authorized_keys_line() {
	[ -s "$F/hpm-node.pub" ] || return 1
	printf 'restrict,from="%s" %s' "$HPM_HOST_IP" "$(tr -d '\r\n' < "$F/hpm-node.pub")"
}

local_sha() { sha256sum "$1" | cut -d' ' -f1; }

# One SSH round trip: prints "path|sha|owner:group|mode" (or "path|absent"),
# "unit|name|enabled|active", "user|...", "logind|...".
inspect() {
	local paths="" p
	while IFS='|' read -r _ _ _ p _ _; do paths="$paths $p"; done <<< "$FILES"
	rsh "$1" "set +e
for p in $paths $HPM_HOME/.ssh/authorized_keys; do
  if sudo -n test -f \"\$p\"; then echo \"\$p|\$(sudo -n sha256sum \"\$p\" | cut -d' ' -f1)|\$(sudo -n stat -c '%U:%G|%a' \"\$p\")\"; else echo \"\$p|absent\"; fi
done
for u in $UNITS $LEGACY_UNITS; do e=\$(systemctl is-enabled \$u 2>/dev/null | head -1); case \"\$e\" in ''|not-found) e=absent ;; esac; echo \"unit|\$u|\$e|\$(systemctl is-active \$u 2>/dev/null | head -1)\"; done
echo \"user|\$(getent passwd hpm-node | cut -d: -f6,7)|\$(sudo -n passwd -S hpm-node 2>/dev/null | awk '{print \$2}')\"
echo \"logind|\$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager InhibitDelayMaxUSec 2>/dev/null)\"
echo \"offload|\$(ethtool -k eth0 2>/dev/null | grep -E '^(tcp-segmentation-offload|scatter-gather):' | awk '{print \$2}' | tr '\n' ' ')\""
}

# check_host HOST -> prints one line per item; returns the number of drifts.
check_host() {
	local host=$1 role out drift=0 name roles file path owner mode line want
	role=$(role_of "$host")
	if ! out=$(inspect "$host" 2>&1); then
		echo "  UNREACHABLE: $out" | head -3
		return 99
	fi
	while IFS='|' read -r name roles file path owner mode; do
		case " $roles " in *" $role "*) ;; *) continue ;; esac
		line=$(grep -F "$path|" <<< "$out" | head -1)
		want="$path|$(local_sha "$F/$file")|$owner|$mode"
		if [ "$line" = "$want" ]; then echo "  ok     $name"; else echo "  DRIFT  $name ($path: ${line#"$path|"})"; drift=$((drift + 1)); fi
	done <<< "$FILES"
	for u in $UNITS; do
		line=$(grep "^unit|$u|" <<< "$out")
		if [ "$line" = "unit|$u|enabled|active" ]; then echo "  ok     $u enabled and active"; else echo "  DRIFT  $u (${line#"unit|$u|"})"; drift=$((drift + 1)); fi
	done
	for u in $LEGACY_UNITS; do
		grep -q "^unit|$u|absent|" <<< "$out" || { echo "  DRIFT  legacy $u still installed"; drift=$((drift + 1)); }
	done
	line=$(grep '^offload|' <<< "$out")
	if [ "$line" = "offload|off off " ]; then echo "  ok     eth0 TSO and scatter-gather off"; else echo "  DRIFT  eth0 offloads (${line#offload|})"; drift=$((drift + 1)); fi
	if [ "$role" != admin ]; then
		line=$(grep '^logind|' <<< "$out")
		if [ "$line" = "logind|t 360000000" ]; then echo "  ok     logind InhibitDelayMaxSec in effect (360 s)"; else echo "  DRIFT  logind inhibit delay not in effect (${line#logind|})"; drift=$((drift + 1)); fi
	fi
	line=$(grep '^user|' <<< "$out")
	if [ "$line" = "user|$HPM_HOME:/bin/bash|L" ]; then echo "  ok     hpm-node account (locked password)"; else echo "  DRIFT  hpm-node account (${line#user|})"; drift=$((drift + 1)); fi
	if ak=$(authorized_keys_line); then
		want="$HPM_HOME/.ssh/authorized_keys|$(printf '%s\n' "$ak" | sha256sum | cut -d' ' -f1)|hpm-node:hpm-node|600"
		line=$(grep -F "$HPM_HOME/.ssh/authorized_keys|" <<< "$out" | head -1)
		if [ "$line" = "$want" ]; then echo "  ok     hpm-node authorized_keys"; else echo "  DRIFT  hpm-node authorized_keys (${line#"$HPM_HOME/.ssh/authorized_keys|"})"; drift=$((drift + 1)); fi
	else
		echo "  SKIP   hpm-node authorized_keys: files/hpm-node.pub not present yet"
	fi
	return "$drift"
}

do_check() {
	local hosts=${*:-$ALL_HOSTS} total=0 rc
	for host in $hosts; do
		echo "== $host ($(role_of "$host"))"
		check_host "$host"; rc=$?
		[ "$rc" -eq 99 ] && rc=1
		total=$((total + rc))
	done
	echo
	if [ "$total" -eq 0 ]; then echo "ALL HOSTS MATCH THE BASELINE"; else echo "$total item(s) drifted; run: bash node-baseline.sh apply HOST --execute"; fi
	[ "$total" -eq 0 ]
}

# push HOST LOCALFILE PATH OWNER:GROUP MODE [validate]
push() {
	local host=$1 src=$2 path=$3 og=$4 mode=$5 validate=${6:-}
	local check_cmd=true
	[ "$validate" = sudoers ] && check_cmd="sudo -n visudo -cf \"\$t\" >/dev/null"
	rsh "$host" "set -e; t=\$(mktemp); cat > \"\$t\"; $check_cmd; sudo -n install -d -m 0755 \"$(dirname "$path")\"; sudo -n install -o ${og%%:*} -g ${og##*:} -m $mode \"\$t\" \"$path\"; rm -f \"\$t\"" < "$src"
}

do_apply() {
	local execute=0 hosts="" host role out changed name roles file path owner mode line
	for a in "$@"; do [ "$a" = --execute ] && execute=1 || hosts="$hosts $a"; done
	[ -n "$hosts" ] || { echo "usage: node-baseline.sh apply HOST... [--execute]" >&2; exit 2; }
	for host in $hosts; do
		role=$(role_of "$host")
		[ "$role" = unknown ] && { echo "unknown host $host" >&2; exit 2; }
		echo "== $host ($role)$([ $execute = 1 ] || echo ' [dry run]')"
		out=$(inspect "$host") || { echo "  UNREACHABLE"; continue; }
		changed=""
		while IFS='|' read -r name roles file path owner mode; do
			case " $roles " in *" $role "*) ;; *) continue ;; esac
			line=$(grep -F "$path|" <<< "$out" | head -1)
			[ "$line" = "$path|$(local_sha "$F/$file")|$owner|$mode" ] && continue
			echo "  install $name -> $path"
			if [ $execute = 1 ]; then
				local v=""; [ "$name" = hpm-node-sudoers ] && v=sudoers
				push "$host" "$F/$file" "$path" "$owner" "$mode" $v || { echo "  FAILED: $name" >&2; exit 1; }
			fi
			changed="$changed $name"
		done <<< "$FILES"
		if ! grep -q "^user|$HPM_HOME:/bin/bash|L" <<< "$out"; then
			echo "  create/lock hpm-node account (home $HPM_HOME)"
			[ $execute = 1 ] && rsh "$host" "set -e; id hpm-node >/dev/null 2>&1 || sudo -n useradd --system --create-home --home-dir $HPM_HOME --shell /bin/bash hpm-node; sudo -n usermod --shell /bin/bash hpm-node; sudo -n passwd -l hpm-node >/dev/null"
		fi
		if ak=$(authorized_keys_line); then
			line=$(grep -F "$HPM_HOME/.ssh/authorized_keys|" <<< "$out" | head -1)
			if [ "$line" != "$HPM_HOME/.ssh/authorized_keys|$(printf '%s\n' "$ak" | sha256sum | cut -d' ' -f1)|hpm-node:hpm-node|600" ]; then
				echo "  install hpm-node authorized_keys (from $HPM_HOST_IP only)"
				[ $execute = 1 ] && printf '%s\n' "$ak" | rsh "$host" "set -e; sudo -n install -d -o hpm-node -g hpm-node -m 0700 $HPM_HOME/.ssh; t=\$(mktemp); cat > \"\$t\"; sudo -n install -o hpm-node -g hpm-node -m 0600 \"\$t\" $HPM_HOME/.ssh/authorized_keys; rm -f \"\$t\""
			fi
		else
			echo "  skip hpm-node authorized_keys: files/hpm-node.pub not present yet"
		fi
		for u in $LEGACY_UNITS; do
			if ! grep -q "^unit|$u|absent|" <<< "$out"; then
				echo "  remove legacy $u (replaced by rpi5-macb-workaround.service)"
				[ $execute = 1 ] && rsh "$host" "sudo -n systemctl disable --now $u; sudo -n rm -f /etc/systemd/system/$u"
			fi
		done
		echo "  daemon-reload; enable --now $UNITS"
		[ $execute = 1 ] && rsh "$host" "set -e; sudo -n systemctl daemon-reload; sudo -n systemctl enable --now $UNITS >/dev/null 2>&1"
		case " $changed " in *" logind-inhibit-delay "*)
			echo "  reload systemd-logind (HUP) so the inhibit delay takes effect"
			[ $execute = 1 ] && rsh "$host" "sudo -n systemctl kill -s HUP systemd-logind" ;;
		esac
		case " $changed " in *" kubelet-graceful-shutdown "*)
			echo "  NOTE: the kubelet drop-in takes effect only after the k3s unit restarts (restarting it disturbs this node's pods); reboot the node when convenient" ;;
		esac
	done
	if [ $execute = 1 ]; then echo; echo "Verify with: bash node-baseline.sh check$hosts"; fi
	return 0
}

case "${1:-}" in
	check) shift; do_check "$@" ;;
	apply) shift; do_apply "$@" ;;
	*) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
