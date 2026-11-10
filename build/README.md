# Build scripts

Scripts that run during image assembly. The Containerfile names each one in its
own `RUN` block, so the order is whatever the Containerfile says — there is no
prefix auto-discovery. The numbers communicate intent.

## Phases

| Script | Does |
|---|---|
| `00-image-info.sh` | Writes image identity into `os-release` and `image-info.json` early, then writes the version into `os-release` after package installation. |
| `10-overlay.sh` | Overlays `projectbluefin/common`'s shared layer and the Brew integration, copies this template's declarations (Brewfiles, ujust recipes, Flatpak preinstalls, `/etc/skel` seeds), and enables the units that consume them. Installs no packages. |
| `20-packages-and-services.sh` | Installs the default RPM and COPR packages and enables their services. Packages live here, not in the overlay phase, so an overlay edit cannot invalidate the package layer. |
| `50-nvidia.sh` | Installs NVIDIA open drivers and CDI support from the signed akmods image matching the base kernel, then rebuilds the initramfs. |
| `30-native-apps.sh` | Installs the native Edge, Zen Browser, and VS Code RPMs. Their RPM metadata lets the rechunker identify each app as a package component. |
| `40-niri-dms.sh` | Installs Niri, the Dux Modular Shell stack, and Dux Files as the default folder manager, plus greetd, portals, and desktop support packages. |

Dux Files' open/save portal chooser is available but remains a per-user opt-in:
enable it in Settings → General → Use Dux Files for open and save dialogs, or
run `dfiles portal install`. The existing portal backends stay installed for
other portal interfaces.
| `90-cleanup.sh` | Finalises package and Flatpak sources, prunes build artifacts, and prepares for `bootc container lint`. |

Helpers, not phases: `copr-helpers.sh` (sourced), `validate-brewfiles.sh`, and
`validate-flatpaks.sh` (called by the Justfile and CI).

## Examples

Inactive until you activate them:

- `30-tailscale.sh.example` — a third-party RPM repository done safely
- `40-gnome-extensions.sh.example` — GNOME Shell extensions with a dconf override
- `60-desktop-swap.sh.example` — replacing the GNOME desktop

NVIDIA support is active in the Containerfile. It uses UBlue's signed
`nvidia-open` akmods image for the base image's exact kernel. After installing
the image, Secure Boot users should run `ujust enroll-secure-boot-key` if the
UBlue kernel-signing key is not already enrolled, then complete enrollment at
reboot.

To activate one, rename it off `.example` and add a `RUN` block to the
Containerfile after the package phase and before the cleanup phase. Copy the
shape below and substitute your script's path:

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/NN-example.sh
```

Deactivating is the reverse: delete the block, rename the file back.

## Writing one

```bash
#!/usr/bin/env bash
set -euo pipefail

dnf5 install -y package-name
```

- Scripts run as root, with the build context at `/ctx`.
- Use `dnf5`, never `dnf` or `yum`, and always `-y`.
- Disable any repository you enable. `copr_install_isolated` does it for COPRs.
- Keep one purpose per script, and name it for that purpose.
