#!/usr/bin/env bash
# Prove the VPN lock actually holds. Run on the host:
#   bash ~/.local/share/qbit-vpn/verify.sh              # non-destructive checks
#   bash ~/.local/share/qbit-vpn/verify.sh --killswitch # also stops the VPN to prove qbit goes dark
set -uo pipefail

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILED=1; }
info() { printf '  ....  %s\n' "$1"; }
FAILED=0

# Fetch a URL from inside the qBittorrent container itself - not gluetun.
# It is qBittorrent's view of the network that matters.
in_qbit() { podman exec qbittorrent "$@" 2>/dev/null; }
qbit_ip() { in_qbit curl -s --max-time 15 https://ipinfo.io/ip; }

echo
echo "== containers =="
for c in gluetun qbittorrent; do
  if [[ "$(podman inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" == "true" ]]; then
    pass "$c is running"
  else
    fail "$c is NOT running"
  fi
done
[[ $FAILED -eq 1 ]] && { echo; echo "Start them:  systemctl --user start qbittorrent"; exit 1; }

echo
echo "== network namespace =="
# qBittorrent must have no interface other than loopback and the tunnel.
# Not "ip -br link": the container ships BusyBox ip, which has no -br and just
# prints usage to stderr, so the check silently saw no interfaces and always
# failed. Parse "ip link" numbered lines instead, which BusyBox does support.
ifaces=$(in_qbit ip link | sed -n 's/^[0-9]\+: \([^:@]*\).*/\1/p' | tr '\n' ' ')
info "interfaces visible to qBittorrent: ${ifaces:-<none>}"
if grep -qE 'tun0|wg0' <<<"$ifaces"; then
  pass "tunnel interface present"
else
  fail "no tunnel interface - qBittorrent is not behind the VPN"
fi

echo
echo "== exit IP =="
host_ip=$(curl -s --max-time 15 https://ipinfo.io/ip)
vpn_ip=$(qbit_ip)
info "this machine's real IP : ${host_ip:-unknown}"
info "qBittorrent's exit IP  : ${vpn_ip:-unknown}"
if [[ -z "$vpn_ip" ]]; then
  fail "qBittorrent has no internet at all"
elif [[ "$vpn_ip" == "$host_ip" ]]; then
  fail "LEAK: qBittorrent is exiting on your real IP"
else
  pass "qBittorrent exits on a different IP than this machine"
  org=$(in_qbit curl -s --max-time 15 "https://ipinfo.io/${vpn_ip}/org")
  info "exit belongs to: ${org:-unknown}"
  grep -qi proton <<<"$org" && pass "exit is ProtonVPN" || info "(could not confirm Proton by ASN name)"
fi

echo
echo "== port forwarding =="
fwd=$(cat ~/.local/share/qbit-vpn/gluetun/forwarded_port 2>/dev/null)
if [[ -n "$fwd" ]]; then
  pass "Proton forwarded port: $fwd"
  listen=$(in_qbit curl -s --max-time 10 \
    "http://127.0.0.1:8080/api/v2/app/preferences" | grep -oE '"listen_port":[0-9]+' | cut -d: -f2)
  if [[ "$listen" == "$fwd" ]]; then
    pass "qBittorrent is listening on the forwarded port ($listen)"
  else
    fail "qBittorrent listen_port=${listen:-?} does not match forwarded port $fwd"
  fi
else
  fail "no forwarded port yet (Proton NAT-PMP may still be negotiating)"
fi

if [[ "${1:-}" == "--killswitch" ]]; then
  echo
  echo "== kill switch (stopping the VPN on purpose) =="
  systemctl --user stop gluetun.service
  sleep 3
  if podman inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null | grep -q true; then
    leak=$(qbit_ip)
    if [[ -n "$leak" ]]; then
      fail "LEAK: qBittorrent still reached the internet as $leak with the VPN down"
    else
      pass "qBittorrent has no route out while the VPN is down"
    fi
  else
    pass "qBittorrent went down with the VPN (its namespace disappeared)"
  fi
  echo
  info "restarting..."
  systemctl --user start qbittorrent.service
  sleep 10
  podman inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null | grep -q true \
    && pass "both back up" || fail "restart failed - check: journalctl --user -u gluetun -u qbittorrent"
fi

echo
[[ $FAILED -eq 0 ]] && echo "All checks passed." || echo "Some checks FAILED (see above)."
exit $FAILED
