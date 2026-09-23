#!/usr/bin/env bash
# autostart.sh — launch the wizard automatically at boot, safely.
#
# Installed into the bundle and invoked by the boot hook that build-image.sh
# sets up (GRML `startup=` bootoption, or a persistence zsh-login snippet).
# It deliberately does nothing over SSH or on a non-interactive stream, so a
# headless/remote operator keeps a normal shell.
set -u

BUNDLE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Never hijack an SSH session or a non-tty.
case "${SSH_CONNECTION:-}${SSH_TTY:-}" in ?*) exit 0 ;; esac
[ -t 0 ] && [ -t 1 ] || exit 0

clear 2>/dev/null || true
cat <<BANNER
  GopForge-Live — auto-start
  The GOP boot-screen wizard is about to launch.
  Press Ctrl-C in the next 3 seconds to stay at a shell instead.
BANNER
# Give the operator a chance to bail out to a plain shell.
if ! sleep 3; then echo "…staying at shell."; exit 0; fi

# root needed for flashrom/amdvbflash/nvflash.
if [ "$(id -u)" = 0 ]; then exec bash "$BUNDLE/bin/gopwizard.sh"
else exec sudo bash "$BUNDLE/bin/gopwizard.sh"; fi
