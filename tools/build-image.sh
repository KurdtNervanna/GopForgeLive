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
echo "build-image.sh is a stub for a single auto-launching remastered image."
echo "For now, make the USB with the cross-platform writers:"
echo "  ./flash-usb/get-base-image.sh"
echo "  sudo ./flash-usb/write-image-linux.sh <image.img> /dev/sdX   (or macos/windows)"
echo "or drop the bundle onto an existing GRML-FLASH USB:"
echo "  ./tools/install-to-usb.sh <mountpoint>"
echo "See flash-usb/README.md and docs/INSTALL.md."
exit 0
