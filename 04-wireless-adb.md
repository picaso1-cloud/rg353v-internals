# 04 — Wireless adb: why it fails out of the box, and the fix

## Symptom

`adb connect <device-ip>:5555` → **connection refused**. Nmap shows port 5555
closed while the device is otherwise reachable on the network.

## Root cause

GammaOS_Lite ships **adbd in USB-only mode**: the property
`service.adb.tcp.port` is **empty**, so adbd never opens a TCP listener.
USB debugging works (that's the authorized USB device); wireless never starts.

Note: Android 11+ "Wireless debugging" in developer options uses a
**random port + pairing flow** — it is not the stable `:5555` adb-tcpip mode,
and it resets its port every boot. For a fixed, always-on remote adb, use the
classic tcpip property.

## The fix (root, one-shot)

Over USB (or any working adb):

```sh
adb -s <serial> shell
su -c "setprop service.adb.tcp.port 5555; setprop ctl.restart adbd"
```

adbd restarts (USB session drops — expected) and re-opens `:5555`:

```
tcp6  0 0 [::]:5555  [::]:*  LISTEN
adb connect <device-ip>:5555   → device
```

Verified: console connected at `192.168.1.148:5555` after this.

## Persistence (GammaOS_Lite has no adb-wifi toggle)

GammaOS_Lite v1.5 ships no property toggle for adb-tcpip, and the property is
**volatile** — it resets every boot. Persistent fix = Magisk late-start script:

```sh
su -c 'mkdir -p /data/adb/service.d && cat > /data/adb/service.d/adb-wifi.sh << S
#!/system/bin/sh
sleep 20
setprop service.adb.tcp.port 5555
setprop ctl.restart adbd
S
chmod 755 /data/adb/service.d/adb-wifi.sh'
```

`/data/adb/service.d/*.sh` runs as root at every boot (Magisk late_start), so
`<device-ip>:5555` is always available ~20 s after boot completes.

## IP note

The device keeps `192.168.1.148/24` on wlan0 (DHCP). If the IP "changes",
it is DHCP reassignment — pin it in the router's DHCP reservations, or rely
on mDNS (the device responds to `<hostname>.local`).
