# CyberPower EC850LCD — Raspberry Pi & Homebridge

A guide to replacing CyberPower's PowerPanel software with **NUT (Network UPS Tools)** on a Raspberry Pi, paired with a PeaNUT web dashboard, HomeKit integration via Homebridge, and push notifications via ntfy.

---

## Architecture Overview

| Component | Runs On | Purpose |
|---|---|---|
| NUT | Raspberry Pi | Talks to UPS over USB, exposes data on port 3493 |
| PeaNUT | Raspberry Pi (Docker) | Web dashboard — battery %, load, voltage, runtime |
| ntfy | Raspberry Pi | Push notifications to iPhone on power events |
| homebridge-ups | Mac Mini (Homebridge) | Exposes UPS to Apple HomeKit and the Home app |
| Tailscale | Pi + iPhone | Secure remote access to PeaNUT from anywhere |

---

## Part 1 — Raspberry Pi: NUT Setup

### Step 1 — Install NUT

```bash
sudo apt update && sudo apt install nut nut-client nut-server
```

### Step 2 — Connect the UPS and Find the Device

Plug in the EC850LCD via USB, then verify it's detected:

```bash
lsusb | grep -i cyber
# Expected output: ID 0764:0501 Cyber Power System

sudo nut-scanner -U
```

### Step 3 — Configure the Driver

Edit `/etc/nut/ups.conf`:

```ini
[cyberpower]
  driver = usbhid-ups
  port = auto
  desc = "CyberPower EC850LCD"
  vendorid = 0764
  productid = 0501
```

### Step 4 — Set NUT Mode

Edit `/etc/nut/nut.conf`:

```ini
MODE=netserver
```

### Step 5 — Configure Network Access

Edit `/etc/nut/upsd.conf`:

```ini
LISTEN 0.0.0.0 3493
```

### Step 6 — Set Users

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

### Step 7 — Configure Monitoring & Shutdown

Edit `/etc/nut/upsmon.conf`:

```ini
MONITOR cyberpower@localhost 1 monitor monitorpass master
SHUTDOWNCMD "/sbin/shutdown -h now"
NOTIFYFLAG ONBATT SYSLOG+WALL+EXEC
NOTIFYFLAG LOWBATT SYSLOG+WALL+EXEC
NOTIFYCMD /etc/nut/notify.sh
```

### Step 8 — Start Services

```bash
sudo systemctl enable nut-server nut-monitor
sudo systemctl start nut-server nut-monitor

# Verify it's working
upsc cyberpower
```

A successful `upsc` response will show live UPS data like battery charge, load, and runtime.

---

## Part 2 — Raspberry Pi: Push Notifications via ntfy

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

Install the **ntfy** app on your iPhone (free, iOS/Android) and subscribe to your chosen topic. You'll receive instant push notifications on power loss, low battery, and other UPS events.

> Pick an unguessable topic name like `myhouse-ups-4829` — this is your only security on the public ntfy.sh server.

---

## Part 3 — Raspberry Pi: PeaNUT Web Dashboard

PeaNUT is a lightweight web dashboard purpose-built for NUT, showing real-time battery percentage, load, voltage, and estimated runtime.

### Install Docker

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

Access the dashboard at `http://<pi-ip-address>:8080`.

### Connect PeaNUT to NUT

1. Open the dashboard in your browser
2. Click the **cog icon** to open Settings
3. Click **+** to add a new NUT server
4. Fill in the fields:
   - **Name**: anything you like (e.g. `rpi`)
   - **Server Address**: your Pi's local IP (e.g. `192.168.1.175`) — do not use `localhost`, as PeaNUT runs inside Docker
   - **Port**: `3493`
   - **Username**: `monitor`
   - **Password**: `monitorpass`
5. Click **Apply**

---

## Part 4 — Remote Access via Tailscale

Tailscale creates a private, encrypted tunnel between your devices so you can access PeaNUT from anywhere without exposing anything to the public internet.

### Install on the Pi

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### Setup

1. Create a free account at [tailscale.com](https://tailscale.com)
2. Run `sudo tailscale up` on the Pi and authenticate
3. Install the **Tailscale** app on your iPhone and sign into the same account
4. Access PeaNUT remotely at `http://<pi-tailscale-ip>:8080`

---

## Part 5 — HomeKit Integration via Homebridge

This exposes your UPS as a native accessory in the Apple Home app, showing battery level, charging state, and on-battery status.

### Prerequisites

- Homebridge already running (e.g. on a Mac Mini on the same network)
- NUT running on the Pi and accessible at port 3493

### Install the Plugin

In the Homebridge UI, go to **Plugins** and search for `homebridge-ups`. Install it.

Alternatively, install via the command line:

```bash
npm install -g homebridge-ups
```

### Configure the Plugin

Add the following to your Homebridge `config.json` under `platforms`:

```json
{
  "platform": "Ups",
  "name": "UPS",
  "hosts": [
    {
      "host": "192.168.1.175",
      "port": 3493,
      "username": "monitor",
      "password": "monitorpass"
    }
  ]
}
```

> Replace `192.168.1.175` with your Pi's local IP address.

Restart Homebridge. Your CyberPower UPS will appear in the Home app as an accessory with battery and outlet status.

---

## Stable IP Address

Since both PeaNUT and Homebridge connect to the Pi by IP, it's important the IP doesn't change. Set a **DHCP reservation** in your router — find the Pi in your router's client list and reserve its current IP against its MAC address. This is easier than configuring a static IP on the Pi itself and survives OS reinstalls.

---

## Protecting Additional Machines

Other computers on your network can shut down safely when the UPS runs low. On each machine, install `nut-client` and configure `/etc/nut/upsmon.conf`:

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
| NUT services won't start | Check logs with `journalctl -u nut-server -xe` |
| Wrong vendor/product ID | Re-run `lsusb` and update `ups.conf` accordingly |
| PeaNUT can't connect to NUT | Ensure `LISTEN 0.0.0.0 3493` is in `upsd.conf`; use Pi's IP, not `localhost` |
| Homebridge plugin can't connect | Verify NUT is reachable from Mac Mini: `nc -zv 192.168.1.175 3493` |
| UPS not appearing in Home app | Restart Homebridge after plugin config; check Homebridge logs for errors |
