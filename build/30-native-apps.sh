#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Native desktop applications
###############################################################################
# Keep these applications as RPMs so they have normal host filesystem access
# and are visible as package components to the OCI rechunker.
###############################################################################

NATIVE_APPS_REPO_DIR="${NATIVE_APPS_REPO_DIR:-/etc/yum.repos.d}"
FEDORA_MAJOR="$(rpm -E '%fedora')"

if [[ ! "${FEDORA_MAJOR}" =~ ^[0-9]+$ ]]; then
	echo "Native desktop applications require a Fedora-based image" >&2
	exit 1
fi

mkdir -p "${NATIVE_APPS_REPO_DIR}"

# Zen Browser is distributed as a Fedora RPM by this COPR.
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Install Zen Browser"
copr_install_isolated "scottames/zen-browser" zen-browser
echo "::endgroup::"

echo "::group:: Install Zed"
terra_repo_file="${NATIVE_APPS_REPO_DIR}/terra.repo"
curl -fsSL \
	"https://raw.githubusercontent.com/terrapkg/packages/f${FEDORA_MAJOR}/anda/terra/release/terra.repo" \
	-o "${terra_repo_file}"
dnf5 install -y zed
rm -f "${terra_repo_file}"
echo "::endgroup::"

echo "::group:: Install Microsoft Edge and VS Code"
rpm --import https://packages.microsoft.com/keys/microsoft.asc

cat >"${NATIVE_APPS_REPO_DIR}/microsoft-edge.repo" <<'EOF'
[microsoft-edge]
name=Microsoft Edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

cat >"${NATIVE_APPS_REPO_DIR}/vscode.repo" <<'EOF'
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf5 install -y microsoft-edge-stable code
rm -f \
	"${NATIVE_APPS_REPO_DIR}/microsoft-edge.repo" \
	"${NATIVE_APPS_REPO_DIR}/vscode.repo"
echo "::endgroup::"