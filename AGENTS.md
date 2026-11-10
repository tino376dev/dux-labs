# AGENTS.md

Working notes for agents in this repository. `overview` maps how the image is
assembled and says which skill covers what; the procedures live under
`.agents/skills/`.

## Gates

These hold for every change:

- **Conventional Commits** — `<type>[scope]: <description>`.
- **Validate before committing.** `just lint` shellchecks every tracked shell
  script, `just check` verifies Justfile syntax, and `just test-unit` runs the
  suite. `just validate-brewfiles` and `just validate-flatpaks` cover those
  files. The `validate` status check runs shellcheck and hadolint on a pull
  request.
- **Confirm before pushing** — show the diff and wait.

## Branches and releases

`main` is the testing branch: pushes publish `:stable-testing`. `stable` is
production, and it never rebuilds — `execute-release.yml` promotes the digest
currently at `:testing` after signature verification. The promotion gate does
not bind that digest to the exact commit being promoted; see the README's
release limitations. Promotion is `main` → `stable` through the auto-opened
squash PR, and `stable` hotfixes sync back to `main`. `stable` takes no direct
commits. The README owns the release table and current gate limits.

## Pull request comments

One comment per PR event; fold new findings into the existing one. Report what
ran, whether it passed, and what blocked — nothing else. When the only finding
is "tests pass", post nothing. Mention someone only to ask for a specific
action, and do it inside the combined comment.

## Attribution

End every commit with:

    Assisted-by: <Model> via <Tool>

## Self-improvement

Ship the work and update the owning skill in the same PR, not a follow-up. A
skill is the home for durable learning; a changelog, a session note, or an
"append here" section is not. When a workaround or convention surprised you,
the next agent needs it.

## Desktop

- The image uses digest-pinned `ghcr.io/ublue-os/base-main:N`; Renovate advances the digest within the manually selected Fedora major. NVIDIA open modules come from UBlue's signed akmods image for the exact base kernel. Major updates require manual base and akmods validation; `just build` derives the version from the tag.
- Niri is a compositor, not a complete desktop. Follow its [integration](https://niri-wm.github.io/niri/Integrating-niri.html), [portal](https://niri-wm.github.io/niri/Important-Software.html), and [NVIDIA](https://niri-wm.github.io/niri/Nvidia.html) guidance when changing session startup, portals, or driver settings.
- Use the [DMS installation](https://duxlabs.dev/docs/dms/installation) and [compositor setup](https://duxlabs.dev/docs/dms/compositors) docs for configuration guidance. DMS packages come from the [Dux Labs DMS](https://copr.fedorainfracloud.org/coprs/duxlabs/dms/) and [Dux repository](https://copr.fedorainfracloud.org/coprs/duxlabs/dux-repo/) COPRs; development builds use [Dux Labs DMS Git](https://copr.fedorainfracloud.org/coprs/duxlabs/dms-git/). Existing installations from AvengeMedia COPRs migrate with `dms migrate dux`. Niri packages come from [yalter/niri](https://copr.fedorainfracloud.org/coprs/yalter/niri/).

## Ownership

Humans triage and approve; agents work only on assigned or `3-clanker-queue`
issues. Keep changes to this repository: `ublue-os/*` is read-only. The shared
lifecycle and labels are in
[projectbluefin/common's label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
