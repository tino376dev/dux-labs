#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# NVIDIA driver and container toolkit
###############################################################################
# Provisions NVIDIA support on UBlue's minimal base from signed, pre-built
# akmods matching the exact kernel in the base image.
#
# Nothing is compiled here. ublue-os/akmods publishes the modules as a container
# image whose tag carries the exact kernel version, so the akmod and the kernel
# it was built against are always taken together.
#
# Hardware-verified only: a container build can install the driver but cannot
# prove it loads or that Wayland comes up. Check `nvidia-smi` on a real GPU.
###############################################################################

# Stock Fedora kernels use the "main" flavor.
AKMODS_FLAVOR="${AKMODS_FLAVOR:-main}"
AKMODS_TAG="${AKMODS_FLAVOR}-$(rpm -E %fedora)-$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

echo "::group:: Pull the pre-built kernel modules"

# The tag has to match the base image's kernel exactly. akmods is built daily
# and the base weekly, so there is a window where this pull has nothing to fetch.
dnf5 install -y skopeo jq

# The image carries kernel modules and driver RPMs. Only accept content signed
# by ublue-os/akmods. The signature names the floating `main-NN` reference while
# the pull uses the kernel-exact tag, so match the repository rather than tag.
AKMODS_IMAGE="ghcr.io/ublue-os/akmods-nvidia-open"
mkdir -p /tmp/akmods-policy/registries.d
cat >/tmp/akmods-policy/policy.json <<EOF
{
  "default": [{"type": "reject"}],
  "transports": {
    "docker": {
      "${AKMODS_IMAGE}": [
        {
          "type": "sigstoreSigned",
          "keyPath": "/ctx/build/akmods-cosign.pub",
          "signedIdentity": {"type": "matchRepository"}
        }
      ]
    }
  }
}
EOF
cat >/tmp/akmods-policy/registries.d/ghcr.yaml <<'EOF'
docker:
  ghcr.io:
    use-sigstore-attachments: true
EOF
skopeo --policy /tmp/akmods-policy/policy.json \
	--registries.d /tmp/akmods-policy/registries.d \
	copy --retry-times 3 \
	"docker://${AKMODS_IMAGE}:${AKMODS_TAG}" dir:/tmp/akmods-rpms

# The image carries its payload in a single layer. Unpack it, then move the RPMs
# in with it so nvidia-install.sh finds them.
tarball="$(jq -r '.layers[0].digest' /tmp/akmods-rpms/manifest.json | cut -d: -f2)"
tar -xzf "/tmp/akmods-rpms/${tarball}" -C /tmp
mv /tmp/rpms/* /tmp/akmods-rpms/

echo "::endgroup::"

echo "::group:: Install the driver"

# Fedora ships a Go rewrite of the container toolkit that conflicts with the C
# implementation nvidia-install.sh expects.
dnf5 config-manager setopt excludepkgs=golang-github-nvidia-container-toolkit

# The installer expects the base family, not the derived image name.
rpm --import "https://download.copr.fedorainfracloud.org/results/ublue-os/staging/pubkey.gpg"
IMAGE_NAME="${BASE_IMAGE_NAME%-main}" \
	AKMODNV_PATH=/tmp/akmods-rpms \
	MULTILIB=0 \
	/tmp/akmods-rpms/ublue-os/nvidia-install.sh

KERNEL_VERSION="$(rpm -q --queryformat='%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
export DRACUT_NO_XATTR=1
dracut --no-hostonly --kver "${KERNEL_VERSION}" --reproducible --add ostree \
	-f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

# Mesa's nouveau Vulkan driver would otherwise advertise a device the NVIDIA
# driver already owns.
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so

echo "::endgroup::"

echo "::group:: Configure kernel arguments"

# nvidia-drm modeset is required for Wayland.
cat >/usr/lib/bootc/kargs.d/00-nvidia.toml <<'EOF'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

echo "::endgroup::"

echo "::group:: Install the NVIDIA container toolkit"

# CDI is how rootless Podman sees the GPU. The addons package enables
# nvidia-cdi-refresh.service, which generates /run/cdi/nvidia.yaml at boot, so no
# device list is baked into the image.
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
	-o /etc/yum.repos.d/nvidia-container-toolkit.repo
dnf5 install -y nvidia-container-toolkit-base
nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place
rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo

echo "::endgroup::"

echo "::group:: Verify the install"

# The same three packages Bluefin asserts in its test phase.
for package in libnvidia-container-tools kmod-nvidia nvidia-driver-cuda; do
	rpm -q "${package}" >/dev/null || {
		echo "Missing NVIDIA package: ${package}" >&2
		exit 1
	}
done

echo "::endgroup::"
