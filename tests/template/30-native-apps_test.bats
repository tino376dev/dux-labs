#!/usr/bin/env bats
# Unit tests for build/30-native-apps.sh.

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SRC="${REPO_ROOT}/build/30-native-apps.sh"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/30-native-apps.${BATS_TEST_NUMBER:-0}.$$"
	CTX="${TEST_ROOT}/ctx"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	SCRIPT="${TEST_ROOT}/30-native-apps.sh"
	NATIVE_APPS_REPO_DIR="${TEST_ROOT}/repos"
	DNF5_LOG="${TEST_ROOT}/dnf5.log"
	RPM_LOG="${TEST_ROOT}/rpm.log"

	mkdir -p "${STUB_BIN}" "${CTX}/build"
	cp "${REPO_ROOT}/build/copr-helpers.sh" "${CTX}/build/copr-helpers.sh"
	sed -e "s#/ctx/#${CTX}/#g" "${BUILD_SRC}" >"${SCRIPT}"

	export PATH="${STUB_BIN}:${PATH}"
	export DNF5_LOG RPM_LOG NATIVE_APPS_REPO_DIR

	cat >"${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >>"${DNF5_LOG}"
exit 0
EOF
	cat >"${STUB_BIN}/rpm" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >>"${RPM_LOG}"
if [[ "${1:-}" == "-E" && "${2:-}" == "%fedora" ]]; then
	printf '%s\n' "${RPM_FEDORA:-44}"
	 exit 0
fi
exit 0
EOF
	chmod +x "${STUB_BIN}/dnf5" "${STUB_BIN}/rpm"
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "30-native-apps: installs Zen, Zed, Edge and VS Code natively" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]

	mapfile -t calls <"${DNF5_LOG}"
	[ "${calls[0]}" = "-y copr enable scottames/zen-browser" ]
	[ "${calls[1]}" = "-y copr disable scottames/zen-browser" ]
	[ "${calls[2]}" = "-y install --enablerepo=copr:copr.fedorainfracloud.org:scottames:zen-browser zen-browser" ]
	[ "${calls[3]}" = "install -y --nogpgcheck --repofrompath terra,https://repos.fyralabs.com/terra44 terra-release terra-gpg-keys" ]
	[ "${calls[4]}" = "install -y zed" ]
	[ "${calls[5]}" = "config-manager setopt terra.enabled=0" ]
	[ "${calls[6]}" = "install -y microsoft-edge-stable code" ]
}

@test "30-native-apps: verifies Microsoft RPMs and removes temporary repos" {
	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]

	grep -Fx -- "--import https://packages.microsoft.com/keys/microsoft.asc" "${RPM_LOG}"
	[ ! -e "${NATIVE_APPS_REPO_DIR}/microsoft-edge.repo" ]
	[ ! -e "${NATIVE_APPS_REPO_DIR}/vscode.repo" ]
}

@test "30-native-apps: rejects non-Fedora bases clearly" {
	RPM_FEDORA=centos run bash "${SCRIPT}"
	[ "${status}" -ne 0 ]
	[[ "${output}" == *"require a Fedora-based image"* ]]
	[ ! -e "${NATIVE_APPS_REPO_DIR}/microsoft-edge.repo" ]
}