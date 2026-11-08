#!/usr/bin/env bats
# Unit tests for build/40-niri-dms.sh.

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SRC="${REPO_ROOT}/build/40-niri-dms.sh"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/40-niri-dms.${BATS_TEST_NUMBER:-0}.$$"
	CTX="${TEST_ROOT}/ctx"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	SCRIPT="${TEST_ROOT}/40-niri-dms.sh"
	DNF5_LOG="${TEST_ROOT}/dnf5.log"
	SYSTEMCTL_LOG="${TEST_ROOT}/systemctl.log"
	NIRI_USER_UNIT_DIR="${TEST_ROOT}/user-units"

	mkdir -p "${STUB_BIN}" "${CTX}/build"
	cp "${REPO_ROOT}/build/copr-helpers.sh" "${CTX}/build/copr-helpers.sh"
	sed -e "s#/ctx/#${CTX}/#g" "${BUILD_SRC}" >"${SCRIPT}"

	export PATH="${STUB_BIN}:${PATH}"
	export DNF5_LOG SYSTEMCTL_LOG NIRI_USER_UNIT_DIR

	for tool in dnf5 systemctl; do
		local log_var
		log_var="$(printf '%s' "${tool}" | tr '[:lower:]' '[:upper:]')_LOG"
		local log_file="${!log_var}"
		cat >"${STUB_BIN}/${tool}" <<EOF
#!/usr/bin/bash
printf '%s\\n' "\$*" >>"${log_file}"
exit 0
EOF
		chmod +x "${STUB_BIN}/${tool}"
	done
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "40-niri-dms: installs Niri and DMS from the selected Dux Labs COPRs" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]

	mapfile -t calls <"${DNF5_LOG}"
	[ "${calls[0]}" = "-y copr enable yalter/niri" ]
	[ "${calls[1]}" = "-y copr disable yalter/niri" ]
	[ "${calls[2]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:yalter:niri niri" ]
	[ "${calls[3]}" = "-y copr enable duxlabs/dux-repo" ]
	[ "${calls[4]}" = "-y copr disable duxlabs/dux-repo" ]
	[ "${calls[5]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:duxlabs:dux-repo cliphist dux-calendar-git dux-search dux-gop dux-files dux-greeter material-symbols-fonts matugen quickshell-git" ]
	[ "${calls[6]}" = "-y copr enable duxlabs/dms" ]
	[ "${calls[7]}" = "-y copr disable duxlabs/dms" ]
	[ "${calls[8]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:duxlabs:dms dms" ]
}

@test "40-niri-dms: installs portals and enables the greeter and shell services" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]

	[[ "$(<"${DNF5_LOG}")" == *"xdg-desktop-portal-gnome"* ]]
	[[ "$(<"${DNF5_LOG}")" == *"xdg-desktop-portal-gtk"* ]]
	[[ "$(<"${DNF5_LOG}")" == *"gvfs"* ]]
	[[ "$(<"${DNF5_LOG}")" == *"udisks2"* ]]
	[[ "$(<"${REPO_ROOT}/custom/files/usr/share/applications/mimeapps.list")" == *"inode/directory=dev.duxlabs.files.desktop;"* ]]
	mapfile -t calls <"${SYSTEMCTL_LOG}"
	[ "${calls[0]}" = "enable greetd.service" ]
	[ "${calls[1]}" = "enable power-profiles-daemon.service" ]
	[ "${#calls[@]}" -eq 2 ]
	[ "$(readlink "${NIRI_USER_UNIT_DIR}/niri.service.wants/dms.service")" = "../dms.service" ]
	[ "$(readlink "${NIRI_USER_UNIT_DIR}/niri.service.wants/dsearch.service")" = "../dsearch.service" ]
}

@test "40-niri-dms: ships the Dux Files, greetd, and keyring defaults" {
	local files_dir="${REPO_ROOT}/custom/files"
	local overlay_script="${REPO_ROOT}/build/10-overlay.sh"

	grep -qF 'inode/directory=dev.duxlabs.files.desktop;' \
		"${files_dir}/usr/share/applications/mimeapps.list"
	grep -qF 'command = "dms-greeter --command niri"' \
		"${files_dir}/etc/greetd/config.toml"
	grep -qF 'pam_gnome_keyring.so' "${files_dir}/usr/lib/pam.d/greetd"
	grep -qF 'pam_gnome_keyring.so auto_start' \
		"${files_dir}/usr/lib/pam.d/greetd"
	grep -qF 'session    include      greetd' \
		"${files_dir}/usr/lib/pam.d/greetd-spawn"
	grep -qF 'rsync -rvKl --exclude=/README.md /ctx/custom/files/ /' \
		"${overlay_script}"
}