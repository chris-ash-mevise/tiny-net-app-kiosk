#!/usr/bin/env bash
set -euo pipefail

USER="${KIOSK_USER:-kioskuser}"
HOME_DIR="/home/${USER}"

# Set password at runtime so it is never baked into an image layer
echo "${USER}:${KIOSK_PASS:-changeme}" | chpasswd

# Seed the home directory from the image on first run.
# The volume mounts over /home/$USER making it empty initially,
# so we copy the baked-in files if they are missing.
for f in HelloWorld.exe .xsession .config .idesktop; do
    src="/home/${USER}-seed/${f}"
    dst="${HOME_DIR}/${f}"
    if [ -e "${src}" ] && [ ! -e "${dst}" ]; then
        cp -a "${src}" "${dst}"
        chown -R "${USER}:${USER}" "${dst}"
    fi
done

# Generate SSH host keys if this is a fresh container (keys are not baked in)
ssh-keygen -A

# sshd needs this directory at runtime
mkdir -p /run/sshd

# xrdp requires these runtime directories
mkdir -p /var/run/xrdp /var/run/sesman
chmod 0755 /var/run/xrdp /var/run/sesman

# Start SSH and xrdp session manager in the background
/usr/sbin/sshd
/usr/sbin/xrdp-sesman

# Run xrdp in the foreground — this keeps the container alive
exec /usr/sbin/xrdp --nodaemon
