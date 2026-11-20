#!/bin/sh
case "$1" in
  deconfig) ip addr flush dev "$interface" 2>/dev/null; ip link set "$interface" up ;;
  bound|renew)
    ip addr flush dev "$interface" 2>/dev/null
    ip addr add "$ip/$mask" dev "$interface"
    [ -n "$router" ] && ip route add default via "$router" dev "$interface" 2>/dev/null
    [ -n "$dns" ] && echo "nameserver $dns" > /etc/resolv.conf
    ;;
esac
