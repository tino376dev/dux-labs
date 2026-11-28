#!/usr/bin/env bats
# Unit tests for the active Tailscale image phase.

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SRC="${REPO_ROOT}/build/30-tailscale.sh"

setup() {
	REPOS_DIR="${BATS_TEST_TMPDIR}/repos"
	CALLS="${BATS_TEST_TMPDIR}/calls"
	STUB_BIN="${BATS_TEST_TMPDIR}/bin"
	SCRIPT="${BATS_TEST_TMPDIR}/30-tailscale.sh"

	mkdir -p "${REPOS_DIR}" "${STUB_BIN}"
	sed "s#/etc/yum.repos.d/#${REPOS_DIR}/#g" "${BUILD_SRC}" >"${SCRIPT}"
	export REPOS_DIR CALLS
	export PATH="${STUB_BIN}:${PATH}"

	cat >"${STUB_BIN}/dnf5" <<'EOF'
#!/usr/bin/env bash
printf 'dnf5 %s\n' "$*" >>"${CALLS}"
if [[ "$1" == "config-manager" && "$2" == "addrepo" ]]; then
	printf '[tailscale-stable]\nenabled=1\n' >"${REPOS_DIR}/tailscale.repo"
elif [[ "$1" == "install" ]]; then
	[[ -f "${REPOS_DIR}/tailscale.repo" ]] || exit 1
	if [[ "${FAIL_INSTALL:-0}" == "1" ]]; then
		echo "Tailscale install failed" >&2
		exit 1
	fi
fi
EOF
	cat >"${STUB_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"${CALLS}"
EOF
	for command in tailscale tailscaled; do
		cat >"${STUB_BIN}/${command}" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"${CALLS}"
exit 1
EOF
	done
	chmod +x "${STUB_BIN}/dnf5" "${STUB_BIN}/systemctl" \
		"${STUB_BIN}/tailscale" "${STUB_BIN}/tailscaled"
}

@test "Tailscale is an executable build phase after packages and before cleanup" {
	[ -x "${BUILD_SRC}" ]
	[ ! -e "${BUILD_SRC}.example" ]

	local package_line tailscale_line cleanup_line
	package_line="$(grep -nF '/ctx/build/20-packages-and-services.sh' "${REPO_ROOT}/Containerfile" | cut -d: -f1)"
	tailscale_line="$(grep -nF '/ctx/build/30-tailscale.sh' "${REPO_ROOT}/Containerfile" | cut -d: -f1)"
	cleanup_line="$(grep -nF '/ctx/build/90-cleanup.sh' "${REPO_ROOT}/Containerfile" | cut -d: -f1)"
	[ "${package_line}" -lt "${tailscale_line}" ]
	[ "${tailscale_line}" -lt "${cleanup_line}" ]
}

@test "Tailscale installs from the vendor repository and enables the daemon" {
	printf '[other]\nenabled=1\n' >"${REPOS_DIR}/other.repo"

	run bash "${SCRIPT}"
	[ "${status}" -eq 0 ]
	mapfile -t calls <"${CALLS}"
	[ "${#calls[@]}" -eq 3 ]
	[ "${calls[0]}" = "dnf5 config-manager addrepo --overwrite --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo" ]
	[ "${calls[1]}" = "dnf5 install -y --from-repo=tailscale-stable tailscale" ]
	[ "${calls[2]}" = "systemctl enable tailscaled.service" ]
	[ ! -e "${REPOS_DIR}/tailscale.repo" ]
	[ -f "${REPOS_DIR}/other.repo" ]
}

@test "Tailscale installation failure prevents daemon enablement" {
	FAIL_INSTALL=1 run bash "${SCRIPT}"
	[ "${status}" -ne 0 ]
	[[ "${output}" == *"Tailscale install failed"* ]]
	! grep -q '^systemctl ' "${CALLS}"
}
