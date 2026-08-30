#!/usr/bin/env bash
# Pull, rebuild, and restart the Taskmaster web app on this server.
#
# Run as root (or via sudo) from anywhere:
#   sudo /root/TaskMaster/deploy/deploy.sh
#
# See docs/deployment.md for what each step is doing and why.

set -euo pipefail

REPO_DIR="/root/TaskMaster"
SERVICE="taskmaster"

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root (use sudo)." >&2
  exit 1
fi

cd "$REPO_DIR"

echo "==> git pull"
git pull

echo "==> mix deps.get"
MIX_ENV=prod mix deps.get

echo "==> mix assets.deploy"
MIX_ENV=prod mix assets.deploy

echo "==> mix release --overwrite"
MIX_ENV=prod mix release --overwrite

echo "==> restarting $SERVICE"
systemctl restart "$SERVICE"

echo "==> status"
systemctl status "$SERVICE" --no-pager
