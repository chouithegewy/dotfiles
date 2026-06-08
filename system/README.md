# System Config Snapshot

This directory records local `/etc` configuration from the current Arch machine.
It is reference material for rebuilds and audits, not something `bootstrap.sh`
applies automatically.

Review these files before copying them to another install. In particular,
`etc/fstab` contains machine-specific UUIDs, `etc/mkinitcpio.conf` depends on
the boot setup for this machine, and `etc/shells` reflects the shells installed
locally.
