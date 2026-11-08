#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Niri and Dux Modular Shell desktop
###############################################################################
# Keep desktop packages in the image so the compositor, greeter, portals, and
# hardware integration are available before first login.
###############################################################################

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

NIRI_USER_UNIT_DIR="${NIRI_USER_UNIT_DIR:-/usr/lib/systemd/user}"

echo "::group:: Install Niri"
copr_install_isolated "yalter/niri" niri
echo "::endgroup::"

echo "::group:: Install Dux Modular Shell"
copr_install_isolated "duxlabs/dux-repo" \
	cliphist \
	dux-calendar-git \
	dux-search \
	dux-gop \
	dux-files \
	dux-greeter \
	material-symbols-fonts \
	matugen \
	quickshell-git
copr_install_isolated "duxlabs/dms" dms
echo "::endgroup::"

echo "::group:: Install desktop integration"
dnf5 install -y \
	alacritty \
	brightnessctl \
	greetd \
	gvfs \
	gnome-keyring \
	gnome-keyring-pam \
	power-profiles-daemon \
	qt6-qtimageformats \
	udisks2 \
	xdg-desktop-portal \
	xdg-desktop-portal-gnome \
	xdg-desktop-portal-gtk \
	xwayland-satellite

systemctl enable greetd.service
systemctl enable power-profiles-daemon.service

# Bind the shell and its search service to Niri only. This avoids starting DMS
# outside the compositor session if another desktop is added later.
install -d "${NIRI_USER_UNIT_DIR}/niri.service.wants"
ln -sfn ../dms.service "${NIRI_USER_UNIT_DIR}/niri.service.wants/dms.service"
ln -sfn ../dsearch.service "${NIRI_USER_UNIT_DIR}/niri.service.wants/dsearch.service"

echo "::endgroup::"

echo "Niri and Dux Modular Shell installation complete!"