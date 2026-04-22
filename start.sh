#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker-compose up -d --build
echo "Kiosk is up — connect via RDP on port 3389"
