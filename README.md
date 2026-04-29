# CyberPower EC850LCD on Raspberry Pi with NUT

A guide to replacing CyberPower's PowerPanel software with **NUT (Network UPS Tools)** on a Raspberry Pi — giving you full UPS monitoring, remote notifications, and shutdown control.

---

## Why NUT?

The EC850LCD connects via **USB HID**, the same interface PowerPanel uses. NUT supports this natively via the `usbhid-ups` driver and runs perfectly on Raspberry Pi (Linux ARM).

**What you get with NUT:**
- Real-time UPS status monitoring (load, battery %, runtime, voltage)
- Automatic safe shutdown of connected devices on power loss
- Remote monitoring via NUT's network protocol
- Web UI via PeaNUT
- Push notifications via ntfy.sh
- SNMP export (optional)
- Monitor multiple machines from a single UPS

---

## Step 1 — Install NUT

```bash
sudo apt update && sudo apt install nut nut-client nut-server
```

---

## Step 2 — Connect the UPS and Find the Device

Plug in the EC850LCD via USB, then verify it's detected:

```bash
lsusb | grep -i cyber
# Expected output: ID 0764:0501 Cyber Power System

sudo nut-scanner -U
```

---

## Step 3 — Configure the Driver

Edit `/etc/nut/ups.conf`:

```ini
[cyberpower]
  driver = usbhid-ups
  port = auto
  desc = "CyberPower EC850LCD"
  vendorid = 0764
  productid = 0501
```

---

## Step 4 — Set NUT Mode

Edit `/etc/nut/nut.conf`:

```ini
MODE=netserver
```

---

## Step 5 — Configure Network Access

Edit `/etc/nut/upsd.conf`:

```ini
LISTEN 0.0.0.0 3493
```

---

## Step 6 — Set Users

Edit `/etc/nut/upsd.users`:

```ini
[admin]
  password = yourpassword
  actions = SET
  instcmds = ALL

[monitor]
  password = monitorpass
  upsmon master
```

> ⚠️ Replace `yourpassword` and `monitorpass` with strong passwords.

---

## Step 7 — Configure Monitoring & Shutdown

Edit `/etc/nut/upsmon.conf`:

```ini
MONITOR cyberpower@localhost 1 monitor monitorpass master
SHUTDOWNCMD "/sbin/shutdown -h now"
NOTIFYFLAG ONBATT SYSLOG+WALL+EXEC
NOTIFYFLAG LOWBATT SYSLOG+WALL+EXEC
NOTIFYCMD /etc/nut/notify.sh
```

---

## Step 8 — Start Services

```bash
sudo systemctl enable nut-server nut-monitor
sudo systemctl start nut-server nut-monitor

# Verify it's working
upsc cyberpower
```

A successful `upsc` response will show live UPS data like battery charge, load, and runtime.

---

## Remote Notifications

Create a notification script at `/etc/nut/notify.sh`:

```bash
#!/bin/bash
# $1 = message passed by NUT

curl -d "UPS Alert: $1" ntfy.sh/your-ups-topic
```

Make it executable:

```bash
sudo chmod +x /etc/nut/notify.sh
```

Install the **ntfy** app on your phone (iOS or Android) and subscribe to your chosen topic to receive push notifications instantly when UPS events occur.

---

## Web Dashboard — PeaNUT

PeaNUT is a lightweight, self-hosted UPS dashboard purpose-built for NUT. It displays real-time stats like battery percentage, load, voltage, and estimated runtime.

### Install Docker (if not already installed)

```bash
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker <your-username>
# Log out and back in for the group change to take effect
```

### Run PeaNUT

```bash
docker run -d \
  --name PeaNUT \
  --restart unless-stopped \
  -v /opt/peanut/config:/config \
  -p 8080:8080 \
  --env WEB_PORT=8080 \
  brandawg93/peanut:latest
```

PeaNUT will now be accessible in your browser at:

```
http://<pi-ip-address>:8080
```

### Connect PeaNUT to NUT

1. Open the URL above in your browser
2. Click the **cog icon** to open Settings
3. Click the **+** button to add a new NUT server
4. Fill in the fields:
   - **Name**: anything you like (e.g. `rpi`)
   - **Server Address**: your Pi's local IP address (e.g. `192.168.1.175`) — do not use `localhost`, as PeaNUT runs inside Docker
   - **Port**: `3493`
   - **Username**: `monitor`
   - **Password**: `monitorpass` (as set in `upsd.users`)
5. Click **Apply**

PeaNUT will now poll your UPS and display live stats on the dashboard.

### Keep PeaNUT Running After Reboot

The `--restart unless-stopped` flag in the Docker run command means PeaNUT will automatically restart if the Pi reboots — no extra steps needed.

### Avoiding IP Address Changes

Since PeaNUT connects to NUT via IP address, it's recommended to assign your Pi a static IP. The easiest way is a **DHCP reservation** in your router — find the Pi in your router's client list and reserve its current IP against its MAC address.

---

## Protecting Additional Machines

Other computers on your network can shut down safely when the UPS runs low. On each machine, install `nut-client` and configure `/etc/nut/upsmon.conf` to point at the Pi:

```ini
MONITOR cyberpower@<pi-ip-address> 1 monitor monitorpass slave
SHUTDOWNCMD "/sbin/shutdown -h now"
```

---

## Troubleshooting

| Issue | Fix |
|---|---|
| `upsc` shows no data | Check USB connection; run `sudo upsdrvctl start` manually |
| Permission denied on USB device | Add your user to `nut` group: `sudo usermod -aG nut <your-username>` |
| Services won't start | Check logs with `journalctl -u nut-server -xe` |
| Wrong vendor/product ID | Re-run `lsusb` and update `ups.conf` accordingly |
| PeaNUT can't connect to NUT | Ensure `LISTEN 0.0.0.0 3493` is set in `upsd.conf` and use the Pi's IP, not `localhost` |
