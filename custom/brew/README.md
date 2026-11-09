# Homebrew

Brewfiles declared here are copied into the image at
`/usr/share/ublue-os/homebrew/`. Users install them after boot; nothing is
installed at build time.

## Brewfile

`default.Brewfile` contains all optional Homebrew formulae, including
development tools. Install them with `ujust install-default-apps`.

The image also ships `/usr/share/ublue-os/homebrew/fonts.Brewfile`, a curated
font set from Common's shared layer, so this directory does not need its own.

## Adding one

Add formulae to `default.Brewfile`. The `install-default-apps` recipe in
`custom/ujust/custom-apps.just` installs the complete list.

## Format

A Brewfile is a Ruby DSL with three kinds of entry:

```ruby
tap "homebrew/cask"           # add a third-party repository
brew "bat"                    # a formula: a CLI tool
brew "eza"
cask "font-jetbrains-mono"    # a cask: a macOS-style package
```

- `tap` comes before anything that needs it.
- `brew` installs formulae.
- `cask` installs macOS-style packages. On Linux only some are available —
  mostly fonts and those that ship a Linux binary.

A repository Brewfile is never evaluated — that would be code execution from a
pull request. `just validate-brewfiles` checks one literally instead, and the
pre-commit hook calls the same script.

## Using them

```bash
brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
```

or, on an image built from this template:

```bash
ujust install-default-apps
```

Homebrew itself is pre-staged at build time and unpacked on first boot by
`brew-setup.service`.
