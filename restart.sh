#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker-compose down
docker-compose up -d --build
echo "Kiosk restarted — connect via RDP on port 3389"
