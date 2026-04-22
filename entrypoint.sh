#!/usr/bin/env bash
set -euo pipefail

# Set password at runtime so it is never baked into an image layer
echo "${KIOSK_USER:-kioskuser}:${KIOSK_PASS:-changeme}" | chpasswd

# xrdp requires these runtime directories
mkdir -p /var/run/xrdp /var/run/sesman
chmod 0755 /var/run/xrdp /var/run/sesman

# Start the session manager in the background
/usr/sbin/xrdp-sesman

# Run xrdp in the foreground — this keeps the container alive
exec /usr/sbin/xrdp --nodaemon
