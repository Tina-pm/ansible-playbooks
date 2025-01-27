# Development tips and howtos

## Plugging your development copy into another repository

Ansible repositories may import collections in a variety of ways (for example,
a requirements file, or a Git submodule). During development, it can be useful
to use _your_ development copy of `tina_pm.playbooks` (or some other
collection).

**TL;DR:** List in `$ANSIBLE_COLLECTIONS_PATH` a directory which contains
your modified version under `ansible_collections/tina_pm/playbooks`.

### Detailed instructions

1.  Create an “override directory” that can be used as a
    `collection_path`. (A _per-collection_ override directory is recommended.
    As an example, I use `~/work/tinapm/.ansible_collections/<fqcn>`).

  - Inside override directories, create an `ansible_collections` subdirectory,
    and symlink your Git repository into it using nested directories for FQCN.
    As an example, this is what I have:

      $ cd ~/work/tinapm; ls -A1
      .ansible_collections
      tina-roles.repo
      tina-sysadm.repo
      tina-playbooks.repo

      $ cd .ansible_collections/tina_pm.playbooks
      $ ls -l ansible_collections/tina_pm
      lrwxr-xr-x  ...  playbooks -> ../../../../tina-playbooks.repo

  - For every collection you want to override, place the override directory
    in the colon-separated `ANSIBLE_COLLECTIONS_PATH` environment variable:

      $ export ANSIBLE_COLLECTIONS_PATH=\
      $HOME/work/tinapm/.ansible_collections/tina_pm.playbooks

  - Beware of not removing access to collections you're not overriding. For
    this, ensure you append to `$ANSIBLE_COLLECTIONS_PATH` the collection
    locations shown by running `ansible --version` in your repository.
