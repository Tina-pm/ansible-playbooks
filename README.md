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

For the reusable variable definitions to be useful, the user needs to be able
to override them when necessary. The default Ansible configuration does not
allow this, as this collection ships variables in playbook context, which have
higher precedence than other context.

So to use this collection properly you need to change the (group) variable
precedence rules, so that variables defined in the inventory or in inventory
context override variables defined in playbook context.

NOTE: Ansible does not allow changing host (as opposed to group) variable
precedence, so those follow the default rules: playbook host\_vars override
inventory host\_vars, which override inventory-file host variables. Avoid
re-defining host variables in multiple contexts.

Sample `ansible.cfg` snippet:

```
# Change the *group* variable precedence rules so that inventory file group
# variables override inventory-context group_vars, and those override
# playbook-context group_vars.
precedence = all_plugins_play, all_plugins_inventory, all_inventory,
    groups_plugins_play, groups_plugins_inventory, groups_inventory

# Set the playbook context for non-playbook CLIs, to load group variables
# defined alongside playbooks.
playbook_dir = .collections/ansible_collections/tina_pm/playbooks/playbooks/
```

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
