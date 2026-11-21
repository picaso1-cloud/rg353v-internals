#!/bin/sh
# udhcpc hooks for wlan0.
# - route: "replace" is idempotent. A plain add fails on renew, and the device
#   then boots with an IP but NO default route (seen live 2026-11-21: Wi-Fi
#   "connected" yet nothing reachable).
# - DNS: handed to systemd-resolved per link, never by overwriting
#   /etc/resolv.conf (resolved's stub must keep working across networks with
#   different router IPs; a pinned DNS= broke as soon as the network changed).
case "$1" in
  deconfig)
    ip addr flush dev "$interface" 2>/dev/null
    ip link set "$interface" up
    resolvectl revert "$interface" 2>/dev/null
    ;;
  bound|renew)
    ip addr flush dev "$interface" 2>/dev/null
    ip addr add "$ip/$mask" dev "$interface"
    [ -n "$router" ] && ip route replace default via "$router" dev "$interface"
    if command -v resolvectl >/dev/null 2>&1; then
      [ -n "$dns" ] && resolvectl dns "$interface" $dns 2>/dev/null
      resolvectl domain "$interface" '~.' 2>/dev/null
      resolvectl default-route "$interface" yes 2>/dev/null
    else
      [ -n "$dns" ] && echo "nameserver $dns" > /etc/resolv.conf
    fi
    ;;
esac
