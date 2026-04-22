#!/usr/bin/env bash
set -euo pipefail

# Set password at runtime so it is never baked into an image layer
echo "${KIOSK_USER:-kioskuser}:${KIOSK_PASS:-changeme}" | chpasswd

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
