#!/usr/bin/env bash
# Build rosimbot-gateway and install/update it as a systemd service.
# Safe to re-run: use it for the first install and for every update.
#
#   ./install.sh            build, install, restart
#   ./install.sh --env      also replace /etc/rosimbot-gateway.env with ./.env
#   ./install.sh --uninstall
set -euo pipefail

NAME=rosimbot-gateway
BIN=/usr/local/bin/$NAME
ENV_FILE=/etc/$NAME.env
UNIT=/etc/systemd/system/$NAME.service

cd "$(dirname "$0")"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user (it uses sudo where needed), so cargo builds with your toolchain." >&2
  exit 1
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  sudo systemctl disable --now "$NAME" 2>/dev/null || true
  sudo rm -f "$UNIT" "$BIN"
  sudo systemctl daemon-reload
  echo "Uninstalled. Left $ENV_FILE in place; delete it yourself if you want."
  exit 0
fi

echo "==> Building release binary"
cargo build --release

echo "==> Installing binary to $BIN"
sudo install -m 755 "target/release/$NAME" "$BIN"

if [[ ! -f "$ENV_FILE" || "${1:-}" == "--env" ]]; then
  if [[ ! -f .env ]]; then
    echo "No .env found. Copy .env.example to .env, fill it in, and re-run." >&2
    exit 1
  fi
  echo "==> Installing secrets to $ENV_FILE"
  sudo install -m 600 .env "$ENV_FILE"
  grep -q '^NO_COLOR=' "$ENV_FILE" 2>/dev/null || echo 'NO_COLOR=1' | sudo tee -a "$ENV_FILE" >/dev/null
fi

# NixOS manages /etc/systemd/system itself, so the unit lives in configuration.nix.
if [[ -e /etc/NIXOS ]]; then
  if ! systemctl cat "$NAME" >/dev/null 2>&1; then
    echo "NixOS detected: add the systemd.services.$NAME block to configuration.nix," >&2
    echo "run 'sudo nixos-rebuild switch', then re-run this script." >&2
    exit 1
  fi
  echo "==> Restarting service"
  sudo systemctl restart "$NAME"
  sleep 2
  sudo systemctl --no-pager --lines=5 status "$NAME" || true
  echo
  echo "Done. Follow logs with: journalctl -u $NAME -f"
  exit 0
fi

echo "==> Writing $UNIT"
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=rosimbot Discord gateway
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$BIN
EnvironmentFile=$ENV_FILE
Restart=on-failure
RestartSec=5

# SIGINT triggers the clean gateway close in main.rs
KillSignal=SIGINT
TimeoutStopSec=10

DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

echo "==> Starting service"
sudo systemctl daemon-reload
sudo systemctl enable "$NAME" >/dev/null 2>&1
sudo systemctl restart "$NAME"

sleep 2
sudo systemctl --no-pager --lines=5 status "$NAME" || true
echo
echo "Done. Follow logs with: journalctl -u $NAME -f"
