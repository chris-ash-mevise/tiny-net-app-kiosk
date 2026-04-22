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
./start.sh

# 3. Connect via RDP
#    Open Remote Desktop Connection (mstsc) on Windows
#    Host:  <docker-host-ip>:3389
#    User:  kioskuser
#    Pass:  (whatever you set in .env)
```

> **First build is slow** — Mono, Xorg, and DOSBox-X are large. Subsequent builds use the layer cache and are fast.

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

## Managing the container

```bash
./start.sh      # build (if needed) and start detached
./stop.sh       # stop and remove the container
./restart.sh    # stop, rebuild, and start — use after any code or config change
```

---

## Project layout

```
.
├── Dockerfile            # Multi-stage image: build (mono-complete) → runtime (mono-runtime)
├── docker-compose.yml    # Ports, volume, env, restart policy
├── entrypoint.sh         # Runtime init: password, SSH keys, seed home dir, start services
├── openbox-autostart     # Openbox hook: disables blanking, starts idesk, launches app
├── HelloWorld.cs         # Sample Windows Forms application (Mono)
├── HelloWorld.lnk        # iDesk icon — relaunches the app
├── Terminal.lnk          # iDesk icon — opens xterm
├── DOSBox.lnk            # iDesk icon — launches DOSBox-X
├── setup-kiosk.sh        # Bare-metal / VM provisioning script
├── start.sh              # Convenience wrapper: docker-compose up -d --build
├── stop.sh               # Convenience wrapper: docker-compose down
├── restart.sh            # Convenience wrapper: stop + start
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

## SSH access and file transfer

The container runs an SSH server on port **2222** (mapped from internal port 22).

```bash
# Open a shell
ssh -p 2222 kioskuser@<host>

# Copy a file to the container
scp -P 2222 myfile.txt kioskuser@<host>:~

# Copy an entire folder to the container
scp -P 2222 -r /local/folder kioskuser@<host>:~

# Copy a file from the container
scp -P 2222 kioskuser@<host>:~/file.txt .
```

SSH host keys are generated fresh on each container start — accept the host key warning on first connect.

---

## File persistence

The kiosk user's home directory (`/home/kioskuser`) is stored in a Docker named volume (`kiosk-home`) so files survive container restarts and rebuilds.

| Action | Files survive? |
|---|---|
| `./restart.sh` (rebuild image) | **Yes** |
| `docker-compose down` + `up` | **Yes** |
| `docker volume rm kiosk-home` | **No** — explicitly wipes the volume |

On first start the entrypoint seeds the volume with the baked-in defaults (`HelloWorld.exe`, desktop icons, `.xsession`, Openbox config). After that, files you upload via `scp` are never overwritten by a rebuild.

---

## Desktop icons

Three clickable icons appear on the Openbox desktop via **iDesk**:

| Icon | Color | Action |
|---|---|---|
| **HW** | Blue | Relaunch `HelloWorld.exe` |
| **>_** | Green | Open `xterm` terminal |
| **DOS** | Gold | Launch DOSBox-X |

---

## Replacing the app

Swap `HelloWorld.cs` for your own `.cs` file before building. The Dockerfile compiles whatever source is provided:

```bash
# In Dockerfile — update the mcs compile flags if you have additional references
mcs -r:System.Windows.Forms.dll -r:System.Drawing.dll YourApp.cs -out:...
```

If you already have a compiled `.exe`, upload it via `scp` and update `HelloWorld.lnk` and `openbox-autostart` to point to it. No rebuild required.

---

## Architecture notes

| Component | Choice | Reason |
|---|---|---|
| Base image | `debian:trixie-slim` | Required for DOSBox-X (needs libc6 ≥ 2.38, libstdc++6 ≥ 13) |
| Build stage | `mono-complete` + `imagemagick` | Compile .cs and generate icons; not carried into runtime image |
| Runtime stage | `mono-runtime` + specific cil libs | Strips compiler/debugger/MSBuild from the running container |
| Window manager | Openbox | ~4 MB RAM; no compositor, no panels |
| Desktop icons | iDesk | Lightweight icon renderer; no file manager needed |
| RDP server | xrdp + xorgxrdp | Native Linux RDP; works with `mstsc` out of the box |
| Terminal | xterm | ~3 MB RAM; sufficient for `top`, `scp`, general use |
| Color depth | 16-bit | Halves pixel bandwidth vs 32-bit |
| Encryption | `crypt_level=low` | Reduces CPU overhead on LAN; raise to `high` for WAN |

### Password security

`KIOSK_PASS` is set by `entrypoint.sh` at container start, not during `docker build`. This prevents the password from appearing in `docker history` or being cached in an intermediate image layer.

### Session lifetime

When `mono HelloWorld.exe` exits (the user closes the window), Openbox exits, terminating the X session. The RDP client disconnects. The container keeps running — a new RDP login starts a fresh session.

---

## Troubleshooting

**Black screen after RDP login**
Verify `.xsession` contains `exec openbox-session` and is owned by the kiosk user:
`docker exec -it <name> cat /home/kioskuser/.xsession`

**"Authentication failed" on RDP connect**
Check that `KIOSK_PASS` is set in `.env` and the container was restarted after changing it.

**App does not appear / desktop is empty**
Check the Openbox autostart: `docker exec -it <name> cat /home/kioskuser/.config/openbox/autostart`. If the volume was just created, confirm the seed ran: `docker exec -it <name> ls /home/kioskuser`.

**SSH connection refused**
Confirm port 2222 is mapped: `docker ps`. Check sshd started: `docker exec -it <name> pgrep sshd`.

**High CPU from Mono on first launch**
Expected — Mono JIT-compiles on first run. Subsequent launches in the same session are faster.
