#!/usr/bin/env bats
# Tests for the inactive build examples: build/*.sh.example.
#
# These files are the only shell in the repository that nothing else
# checks. `just lint` and pr-validation.yml both resolve their scope from
# `git ls-files '*.sh'`, which does not match a `.sh.example` suffix, and the
# Containerfile never runs them. A contributor activates one by renaming it,
# so a syntax error or a broken instruction in one of them reaches a user's
# build unreviewed by any gate.
#
# The assertions here are the rules build/README.md states for a build script,
# plus the claims each example makes about itself and about 90-cleanup.sh.

BUILD_DIR="${BATS_TEST_DIRNAME}/../../build"
README="${BUILD_DIR}/README.md"
CLEANUP="${BUILD_DIR}/90-cleanup.sh"
CONTAINERFILE="${BATS_TEST_DIRNAME}/../../Containerfile"
NVIDIA_SCRIPT="${BUILD_DIR}/50-nvidia.sh"

_examples() {
    find "${BUILD_DIR}" -maxdepth 1 -type f -name '*.sh.example' | sort
}

setup() {
    mapfile -t EXAMPLES < <(_examples)
    # An empty subject list would pass every loop below silently.
    [ "${#EXAMPLES[@]}" -gt 0 ]
}

@test "every example is syntactically valid bash" {
    for example in "${EXAMPLES[@]}"; do
        run bash -n "${example}"
        [ "${status}" -eq 0 ] || {
            echo "${example}: ${output}" >&2
            return 1
        }
    done
}

@test "every example declares the bash shebang and strict mode" {
    for example in "${EXAMPLES[@]}"; do
        run head -n 1 "${example}"
        [ "${output}" = "#!/usr/bin/env bash" ] || {
            echo "${example}: first line is '${output}'" >&2
            return 1
        }
        grep -qx 'set -euo pipefail' "${example}" || {
            echo "${example}: no 'set -euo pipefail'" >&2
            return 1
        }
    done
}

@test "no example calls dnf or yum instead of dnf5" {
    # build/README.md: "Use dnf5, never dnf or yum".
    for example in "${EXAMPLES[@]}"; do
        run grep -nE '(^|[^[:alnum:]_/-])(dnf|yum)[[:space:]]' "${example}"
        [ "${status}" -ne 0 ] || {
            echo "${example}: ${output}" >&2
            return 1
        }
    done
}

@test "every dnf5 transaction is non-interactive" {
    # build/README.md: "always -y". A transaction without it hangs the build.
    for example in "${EXAMPLES[@]}"; do
        while IFS= read -r line; do
            [ -n "${line}" ] || continue
            case "${line}" in
                *" -y"*) ;;
                *)
                    echo "${example}: missing -y: ${line}" >&2
                    return 1
                    ;;
            esac
        done < <(grep -E '^[[:space:]]*dnf5[[:space:]]+(install|remove|upgrade|swap|group)' "${example}")
    done
}

@test "every example names the filename it is activated as" {
    # Each header tells the reader what to rename the file to. A file renamed
    # without its header updated sends the reader to a path that does not exist.
    for example in "${EXAMPLES[@]}"; do
        local activated
        activated="$(basename "${example}" .example)"
        grep -qF "${activated}" "${example}" || {
            echo "${example}: header never mentions '${activated}'" >&2
            return 1
        }
    done
}

@test "build/README.md lists exactly the examples that exist" {
    for example in "${EXAMPLES[@]}"; do
        local name
        name="$(basename "${example}")"
        grep -qF "\`${name}\`" "${README}" || {
            echo "build/README.md does not list ${name}" >&2
            return 1
        }
    done

    # And the reverse: README must not advertise an example that was deleted.
    while IFS= read -r name; do
        [ -f "${BUILD_DIR}/${name}" ] || {
            echo "build/README.md lists ${name}, which does not exist" >&2
            return 1
        }
    done < <(grep -oE '`[0-9]+-[a-z-]+\.sh\.example`' "${README}" | tr -d '`' | sort -u)
}

@test "every repository file an example drops into /etc/yum.repos.d is removed by it" {
    # A third-party repository is a build-time source only. Leaving the .repo
    # behind ships a live third-party source in the image.
    for example in "${EXAMPLES[@]}"; do
        while IFS= read -r repo_file; do
            grep -qE "rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*${repo_file}([[:space:]]|$)" "${example}" || {
                echo "${example}: ${repo_file} is written but never removed" >&2
                return 1
            }
        done < <(grep -ohE '/etc/yum\.repos\.d/[A-Za-z0-9_.-]+\.repo' "${example}" | sort -u)
    done
}

@test "90-cleanup.sh still disables tailscale.repo as the documented backstop" {
    # 30-tailscale.sh tells the reader that 90-cleanup.sh disables
    # tailscale.repo as a backstop. Dropping tailscale from that loop makes the
    # phase's promise false without touching the phase.
    grep -qF "90-cleanup.sh also disables tailscale.repo" \
        "${BUILD_DIR}/30-tailscale.sh"
    grep -qE '^for repo_name in .*[[:space:]]tailscale([[:space:]]|;)' "${CLEANUP}"
}

@test "NVIDIA drivers are an active build phase before native apps" {
    [ -x "${NVIDIA_SCRIPT}" ]
    [ ! -f "${BUILD_DIR}/50-nvidia.sh.example" ]

    local nvidia_line native_apps_line
    nvidia_line="$(grep -nF '/ctx/build/50-nvidia.sh' "${CONTAINERFILE}" | cut -d: -f1)"
    native_apps_line="$(grep -nF '/ctx/build/30-native-apps.sh' "${CONTAINERFILE}" | cut -d: -f1)"
    [ -n "${nvidia_line}" ]
    [ -n "${native_apps_line}" ]
    [ "${nvidia_line}" -lt "${native_apps_line}" ]
}

@test "NVIDIA build uses signed kernel-matched modules and rebuilds initramfs" {
    grep -qF 'skopeo --policy /tmp/akmods-policy/policy.json' "${NVIDIA_SCRIPT}"
    grep -qF 'AKMODS_TAG="${AKMODS_FLAVOR}-$(rpm -E %fedora)-$(rpm -q kernel-core' "${NVIDIA_SCRIPT}"
    grep -qF 'IMAGE_NAME="${BASE_IMAGE_NAME%-main}"' "${NVIDIA_SCRIPT}"
    grep -qF 'dracut --no-hostonly --kver "${KERNEL_VERSION}" --reproducible --add ostree' "${NVIDIA_SCRIPT}"
}

_prepare_nvidia_initramfs_test() {
    export NVIDIA_TEST_ROOT="${BATS_TEST_TMPDIR}"
    mkdir -p "${NVIDIA_TEST_ROOT}/bin" "${NVIDIA_TEST_ROOT}/modules"
    # Run only the rebuild section, with its output confined to the test root.
    sed -n '/^KERNEL_VERSION=/,/^chmod 0600/p' "${NVIDIA_SCRIPT}" |
        sed "s#/usr/lib/modules/#${NVIDIA_TEST_ROOT}/modules/#g" \
        >"${NVIDIA_TEST_ROOT}/rebuild.sh"
    [ -s "${NVIDIA_TEST_ROOT}/rebuild.sh" ]

    cat >"${NVIDIA_TEST_ROOT}/bin/rpm" <<'EOF'
#!/usr/bin/env bash
printf 'test-kernel\n'
EOF
    cat >"${NVIDIA_TEST_ROOT}/bin/dnf5" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAIL_ZSTD_UPGRADE:-0}" == "1" ]]; then
    echo "zstd upgrade failed" >&2
    exit 1
fi
if [[ "$1" == "upgrade" && " $* " == *" zstd "* && " $* " == *" libzstd "* ]]; then
    touch "${NVIDIA_TEST_ROOT}/zstd-aligned"
fi
EOF
    cat >"${NVIDIA_TEST_ROOT}/bin/dracut" <<'EOF'
#!/usr/bin/env bash
touch "${NVIDIA_TEST_ROOT}/dracut-called"
if [[ ! -f "${NVIDIA_TEST_ROOT}/zstd-aligned" ]]; then
    echo "incorrect library version" >&2
    exit 1
fi
mkdir -p "$(dirname "${@: -1}")"
printf 'initramfs\n' >"${@: -1}"
EOF
    chmod +x "${NVIDIA_TEST_ROOT}/bin/rpm" \
        "${NVIDIA_TEST_ROOT}/bin/dnf5" "${NVIDIA_TEST_ROOT}/bin/dracut"
    export PATH="${NVIDIA_TEST_ROOT}/bin:${PATH}"
}

@test "NVIDIA rebuild aligns zstd before compressing the initramfs" {
    _prepare_nvidia_initramfs_test
    run bash -euo pipefail "${NVIDIA_TEST_ROOT}/rebuild.sh"
    [ "${status}" -eq 0 ]
    [ -s "${NVIDIA_TEST_ROOT}/modules/test-kernel/initramfs.img" ]
}

@test "NVIDIA rebuild stops when zstd package alignment fails" {
    _prepare_nvidia_initramfs_test
    FAIL_ZSTD_UPGRADE=1 run bash -euo pipefail "${NVIDIA_TEST_ROOT}/rebuild.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"zstd upgrade failed"* ]]
    [ ! -e "${NVIDIA_TEST_ROOT}/dracut-called" ]
}

@test "shellcheck is clean on every example" {
    # `just lint` cannot reach these files: its scope is `git ls-files '*.sh'`.
    command -v shellcheck >/dev/null || skip "shellcheck is not installed"
    for example in "${EXAMPLES[@]}"; do
        run shellcheck --shell=bash "${example}"
        [ "${status}" -eq 0 ] || {
            echo "${example}: ${output}" >&2
            return 1
        }
    done
}
