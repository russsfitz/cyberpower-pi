# CyberPower EC850LCD on Raspberry Pi with NUT

A guide to replacing CyberPower's PowerPanel software with **NUT (Network UPS Tools)** on a Raspberry Pi — giving you full UPS monitoring, remote notifications, and shutdown control.

---

## Why NUT?

The EC850LCD connects via **USB HID**, the same interface PowerPanel uses. NUT supports this natively via the `usbhid-ups` driver and runs perfectly on Raspberry Pi (Linux ARM).

**What you get with NUT:**
- Real-time UPS status monitoring (load, battery %, runtime, voltage)
- Automatic safe shutdown of connected devices on power loss
- Remote monitoring via NUT's network protocol
- Web UI via NUT Monitor, Uptime Kuma, or Grafana
- Email / webhook notifications
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

# Option A: Email
echo "UPS Alert: $1" | mail -s "UPS Alert" you@example.com

# Option B: Webhook (e.g. ntfy.sh, Slack, Pushover)
curl -d "$1" ntfy.sh/your-ups-topic
```

Make it executable:

```bash
sudo chmod +x /etc/nut/notify.sh
```

---

## Web Dashboard — Uptime Kuma

Uptime Kuma is a self-hosted monitoring tool with a clean UI and native NUT support. It runs well on a Raspberry Pi and lets you view UPS status and set up alerts from any browser.

### Install Docker (if not already installed)

Uptime Kuma is easiest to run via Docker:

```bash
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker pi
# Log out and back in for the group change to take effect
```

### Run Uptime Kuma

```bash
docker run -d \
  --restart=always \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  --name uptime-kuma \
  louislam/uptime-kuma:1
```

Uptime Kuma will now be accessible in your browser at:

```
http://<pi-ip-address>:3001
```

### First-Time Setup

1. Open the URL above in your browser
2. Create an admin username and password when prompted

### Add a NUT UPS Monitor

1. Click **Add New Monitor**
2. Set **Monitor Type** to `DNS` — then change it to **NUT (Network UPS Tools)** from the dropdown
3. Fill in the fields:
   - **Friendly Name**: CyberPower EC850LCD (or anything you like)
   - **Host**: `localhost` (or the Pi's IP if accessing remotely)
   - **Port**: `3493`
   - **UPS Name**: `cyberpower` (must match the name in your `ups.conf`)
   - **Username**: `monitor`
   - **Password**: `monitorpass` (as set in `upsd.users`)
4. Click **Save**

Uptime Kuma will now poll your UPS and display its status on the dashboard.

### Set Up Notifications (Optional)

Uptime Kuma supports a wide range of notification channels — email, Slack, Discord, Telegram, Pushover, ntfy, and more.

1. Go to **Settings → Notifications**
2. Click **Setup Notification**
3. Choose your preferred channel and follow the prompts
4. Assign the notification to your UPS monitor

### Keep Uptime Kuma Running After Reboot

The `--restart=always` flag in the Docker run command means Uptime Kuma will automatically restart if the Pi reboots — no extra steps needed.

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
| Permission denied on USB device | Add `pi` user to `nut` group: `sudo usermod -aG nut pi` |
| Services won't start | Check logs with `journalctl -u nut-server -xe` |
| Wrong vendor/product ID | Re-run `lsusb` and update `ups.conf` accordingly |
