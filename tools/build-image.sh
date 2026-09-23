#!/usr/bin/env bash
# build-image.sh — (optional, later) bake GopForge-Live into a GRML live image.
#
# The primary/supported path today is install-to-usb.sh onto an existing
# GRML-FLASH USB. This script is a placeholder for the eventual grml2usb-based
# remaster so the whole wizard auto-launches on boot. It is NOT yet tested.
#
# Outline (per the GRML-FLASH README's own build path):
#   1. write the GRML-FLASH release .img to USB (Balena Etcher / dd)
#   2. mount the data/persistence partition
#   3. ./tools/install-to-usb.sh <mountpoint>
#   4. optionally add an autostart hook (e.g. ~/.zlogin) to run bin/gopwizard.sh
#   5. optionally rebuild with grml2usb for a persistent custom image
set -Eeuo pipefail
echo "build-image.sh is a stub — use tools/install-to-usb.sh for now."
echo "See docs/INSTALL.md for the manual grml2usb remaster steps."
exit 0
