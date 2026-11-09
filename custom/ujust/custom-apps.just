# vim: set ft=make :
####################
### custom-apps.just
####################
## Homebrew shortcuts.
##
## The combined Brewfile in custom/brew/ is copied to
## /usr/share/ublue-os/homebrew/ at build time.
##
## See custom/brew/README.md.

# Install Homebrew applications
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    echo "Installing applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
