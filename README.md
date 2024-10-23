Ansible collection: tina\_pm.playbooks

This is an opinionated collection of playbooks and variable templates using
roles from the tina\_pm.common collection as well as various third-party roles.

There are many strong assumptions that might not be useful for many people, but
that make life much easier if followed.

## Non-exhaustive list of assumptions

* Hosts run on Debian.
* Tools such as `cloud-init`, `systemd-networkd`, `systemd-resolved`, are
  not used.
* Network configuration uses `ifupdown`.
* Per-host firewalls use `ferm` and `iptables`.
* All hosts belong to the `site` group, where non-reusable settings are
  defined.

## Features

* Most features and functionality are enabled either by group membership (e.g.
  `apache_servers`) or by a boolean variable (e.g. `ferm__enable`).
* Templates are provided to allow cumulative definitions for many structured
  configuration variables, using commong prefixes (e.g.
  Unless overriden, `apt__packages_to_install` is constructed by concatenanting
  all variables named `apt__packages_to_install__*`).
* A simple system to define full ifupdown-based network configuration is provided.
* Whenever possible, variables are prefixed by their associated role name,
  followed by 2 underscores.

