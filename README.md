# tiny-net-app-kiosk

An ultra-lean RDP kiosk that boots directly into a Mono/.NET Windows Forms application — nothing else. No taskbar, no file manager, no desktop environment.

```
RDP client (mstsc)
      │  port 3389
      ▼
   xrdp
      │  starts X session
      ▼
  Openbox (window manager)
      │  autostart
      ▼
 mono HelloWorld.exe   ← your app
```

**Idle RAM target:** < 200 MB

---

## Quick start (Docker)

```bash
# 1. Copy the example env file and set your password
cp .env.example .env
#    edit .env — change KIOSK_PASS

# 2. Build and run
docker compose up -d

# 3. Connect
#    Open Remote Desktop Connection (mstsc) on Windows
#    Host:  <docker-host-ip>:3389
#    User:  kioskuser
#    Pass:  (whatever you set in .env)
```

> **First build is slow** — Mono and Xorg are large. Subsequent builds use the layer cache and are fast.

---

## Quick start (bare metal / VM)

Place `setup-kiosk.sh` and `HelloWorld.cs` in the same directory on a fresh **Debian 12 Minimal** install, then:

```bash
export KIOSK_USER=kioskuser
export KIOSK_PASS=your_secure_password
sudo bash setup-kiosk.sh
```

The script prints a validation report when it finishes.

---

## Project layout

```
.
├── Dockerfile            # Container image definition
├── docker-compose.yml    # Service definition (port, env, restart policy)
├── entrypoint.sh         # Container startup: sets password, starts xrdp
├── openbox-autostart     # Openbox hook: disables blanking, launches app
├── HelloWorld.cs         # Sample Windows Forms application (Mono)
├── setup-kiosk.sh        # Bare-metal / VM provisioning script
├── .env.example          # Copy to .env and set KIOSK_PASS
└── .dockerignore
```

---

## Environment variables

| Variable | Default | Notes |
|---|---|---|
| `KIOSK_USER` | `kioskuser` | Set at **build time** via `--build-arg`. Changing it requires a rebuild. |
| `KIOSK_PASS` | `changeme` | Set at **runtime** via `.env` or `-e`. Never baked into image layers. |

---

## Replacing the app

Swap `HelloWorld.cs` for your own `.cs` file before building. The Dockerfile compiles whatever source is provided:

```bash
# In Dockerfile — update the mcs compile flags if you have additional references
mcs -r:System.Windows.Forms.dll -r:System.Drawing.dll YourApp.cs -out:...
```

If you already have a compiled `.exe`, skip the `mcs` step and `COPY` the binary directly into `/home/kioskuser/HelloWorld.exe`.

---

## Architecture notes

| Component | Choice | Reason |
|---|---|---|
| Base image | `debian:12-slim` | Minimal attack surface; no systemd in container |
| Window manager | Openbox | ~4 MB RAM; no compositor, no panels |
| RDP server | xrdp | Native Linux RDP; works with `mstsc` out of the box |
| Runtime | Mono-Complete | .NET 4.x compatible; no Wine required |
| Color depth | 16-bit | Halves pixel bandwidth vs 32-bit |
| Encryption | `crypt_level=low` | Reduces CPU overhead on LAN; raise to `high` for WAN |

### Password security

`KIOSK_PASS` is intentionally set by `entrypoint.sh` at container start, not during `docker build`. This prevents the password from appearing in `docker history` or being cached in an intermediate image layer.

### Session lifetime

When `mono HelloWorld.exe` exits (i.e., the user closes the window), Openbox exits, which terminates the X session. The RDP client disconnects. The container itself keeps running — a new RDP login starts a fresh session.

---

## Troubleshooting

**Black screen after RDP login**
Verify that `.xsession` contains `exec openbox-session` and is owned by the kiosk user. Inside the container: `docker exec -it <name> cat /home/kioskuser/.xsession`

**"Authentication failed" on RDP connect**
The password is set by the entrypoint at startup. Check that `KIOSK_PASS` is set correctly in `.env` and that the container restarted after you changed it.

**App does not appear / gray screen only**
Check the Openbox autostart log: `docker exec -it <name> cat /home/kioskuser/.config/openbox/autostart` — ensure `mono ~/HelloWorld.exe` is the last line and there are no syntax errors above it.

**High CPU from Mono on first launch**
Expected — Mono JIT-compiles on first run. Subsequent launches in the same container session are faster.
