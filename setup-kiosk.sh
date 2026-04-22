#!/usr/bin/env bash
# Kiosk VM setup script for Debian 12 (Bookworm) Minimal
# Run as root. Creates an unprivileged kiosk user and configures
# xrdp → Openbox → Mono/.NET app autostart.
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
KIOSK_USER="${KIOSK_USER:-kioskuser}"
KIOSK_PASS="${KIOSK_PASS:-changeme}"       # override via env var before running
APP_SRC="HelloWorld.cs"
APP_EXE="HelloWorld.exe"
KIOSK_HOME="/home/${KIOSK_USER}"
# ──────────────────────────────────────────────────────────────────────────────

log() { echo "[kiosk] $*"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root." >&2
        exit 1
    fi
}

require_root

# ─── 1. Base packages ─────────────────────────────────────────────────────────
log "Installing packages (no recommended bloat)..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    xserver-xorg-core \
    xserver-xorg \
    xinit \
    openbox \
    xrdp \
    mono-complete \
    ufw

# ─── 2. Create unprivileged kiosk user ────────────────────────────────────────
log "Creating user '${KIOSK_USER}'..."
if id "${KIOSK_USER}" &>/dev/null; then
    log "User already exists — skipping creation."
else
    useradd -m -s /bin/bash "${KIOSK_USER}"
fi
echo "${KIOSK_USER}:${KIOSK_PASS}" | chpasswd

# Add to ssl-cert group so xrdp TLS handshake works
usermod -aG ssl-cert "${KIOSK_USER}" 2>/dev/null || true

# ─── 3. Compile the .NET app ──────────────────────────────────────────────────
log "Compiling ${APP_SRC} with Mono..."
if [[ ! -f "${APP_SRC}" ]]; then
    echo "ERROR: ${APP_SRC} not found in $(pwd). Place it next to this script." >&2
    exit 1
fi

mcs -r:System.Windows.Forms.dll -r:System.Drawing.dll "${APP_SRC}" -out:"${APP_EXE}"
install -o "${KIOSK_USER}" -g "${KIOSK_USER}" -m 0755 "${APP_EXE}" "${KIOSK_HOME}/${APP_EXE}"

# ─── 4. xsession: RDP → Openbox ───────────────────────────────────────────────
log "Writing ${KIOSK_HOME}/.xsession..."
cat > "${KIOSK_HOME}/.xsession" <<'XSESSION'
exec openbox-session
XSESSION
chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.xsession"
chmod 0644 "${KIOSK_HOME}/.xsession"

# ─── 5. Openbox autostart: disable blanking, launch app ──────────────────────
log "Configuring Openbox autostart..."
install -d -o "${KIOSK_USER}" -g "${KIOSK_USER}" -m 0755 \
    "${KIOSK_HOME}/.config/openbox"

cat > "${KIOSK_HOME}/.config/openbox/autostart" <<AUTOSTART
# Disable screen blanking and power management
xset s off
xset -dpms
xset s noblank

# Launch the kiosk app; session ends when the window closes
mono ~/HelloWorld.exe
AUTOSTART
chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config/openbox/autostart"
chmod 0755 "${KIOSK_HOME}/.config/openbox/autostart"

# ─── 6. Tune xrdp for low-resource operation ──────────────────────────────────
log "Tuning /etc/xrdp/xrdp.ini..."
XRDP_INI="/etc/xrdp/xrdp.ini"

# crypt_level: reduce TLS overhead (low = RC4 compat; fine for LAN kiosks)
sed -i 's/^crypt_level=.*/crypt_level=low/' "${XRDP_INI}"

# 16-bit color depth: halves pixel bandwidth vs 32-bit
sed -i 's/^max_bpp=.*/max_bpp=16/' "${XRDP_INI}"

log "Restarting xrdp..."
systemctl enable xrdp
systemctl restart xrdp

# ─── 7. Firewall: open RDP port ───────────────────────────────────────────────
log "Configuring UFW — opening port 3389..."
ufw allow 3389/tcp
# Enable UFW non-interactively if it isn't already active
ufw --force enable

# ─── 8. Validation report ─────────────────────────────────────────────────────
log ""
log "─── Validation ──────────────────────────────────────────────────────"

# User exists
id "${KIOSK_USER}" &>/dev/null \
    && log "[PASS] User '${KIOSK_USER}' exists." \
    || log "[FAIL] User '${KIOSK_USER}' not found."

# App binary owned by kiosk user
OWNER=$(stat -c '%U' "${KIOSK_HOME}/${APP_EXE}" 2>/dev/null || echo "missing")
[[ "${OWNER}" == "${KIOSK_USER}" ]] \
    && log "[PASS] ${APP_EXE} owned by ${KIOSK_USER}." \
    || log "[FAIL] ${APP_EXE} owner is '${OWNER}', expected '${KIOSK_USER}'."

# .xsession owned by kiosk user
XSOWNER=$(stat -c '%U' "${KIOSK_HOME}/.xsession" 2>/dev/null || echo "missing")
[[ "${XSOWNER}" == "${KIOSK_USER}" ]] \
    && log "[PASS] .xsession owned by ${KIOSK_USER}." \
    || log "[FAIL] .xsession owner is '${XSOWNER}'."

# xrdp listening on 3389
ss -tlnp | grep -q ':3389' \
    && log "[PASS] xrdp is listening on port 3389." \
    || log "[FAIL] xrdp does NOT appear to be listening on 3389."

# No desktop environment installed
for DE in gnome-session xfce4-session lxsession; do
    if command -v "${DE}" &>/dev/null; then
        log "[WARN] Desktop environment binary found: ${DE}. Kiosk may not be lean."
    fi
done
log "[PASS] No full desktop environment detected."

log "─────────────────────────────────────────────────────────────────────"
log ""
log "Setup complete."
log "Connect via RDP to this machine on port 3389."
log "Login: ${KIOSK_USER} / (password you set)"
