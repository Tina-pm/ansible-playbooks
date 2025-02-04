#!/usr/bin/env -S bash

#   Copyright (C) 2024-2025
#   Martina Ferrari, Simó Albert i Beltran, Adeodato Simó
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -e -u -o pipefail

BACKUP_FROM_DIR="${BACKUP_FROM_DIR:-/tmp/bk-snap}"

clean_mount_point(){
  # Umount if mounted and always remove the directory
  local mount_point_dir=$1
  if mountpoint -q $mount_point_dir
  then
    umount $mount_point_dir
  fi
  # Remove mount point directory but maybe nothing is mounted due to an
  # interruption
  if test -d $mount_point_dir
  then
    rmdir $mount_point_dir
  fi
}

get_backup_location(){
  # Get backup location for device name
  local device_name=$1
  echo "$BACKUP_FROM_DIR/$(
    dmsetup info -C --noheadings -o name $device_name |
      sed 's/--snap$//'
  )"
}

get_volumes(){
  # Get LVM volumes that are not snapshots
  lvs --noheadings -o vg_name,lv_name,lv_attr |
    awk '$3 ~ /^[-oV]/ {print $1"/"$2}'
}

is_partition_table(){
  # Exit with 0 if the parameter is a device with a partition table, 1
  # otherwise.
  local device=$1
  test -n "$(blkid -s PTTYPE -o value $device)"
}

is_filesystem(){
  # Exit with 0 if the parameter is a device with a supported filesystem, 1
  # otherwise.
  local device=$1
  local filesystem=$(blkid -s TYPE -o value $device)
  test -n "$filesystem" && grep -q "\b${filesystem}$" /proc/filesystems
}

teardown(){
  # Remove MBR and partition tables backup
  lsblk -l -o TYPE,NAME | grep "^disk " | while read _ harddrive
  do
    rm -f "$BACKUP_FROM_DIR/$harddrive.mbr"
    rm -f "$BACKUP_FROM_DIR/$harddrive.sfdisk"
  done
  # Umount boot and EFI
  for mount_point in boot boot_efi
  do
    clean_mount_point "$BACKUP_FROM_DIR/$mount_point"
  done
  # Umount filesystems and remove snapshots
  get_volumes | while read volume
  do
    test ! -b /dev/$volume-snap &&
      continue
    # The created snapshot can contain a disk with partitions that are mounted
    # or dumped. These partitions will be unmounted or dumps will be deleted.
    # Otherwise, if the created snapshot does not contain a disk with
    # partitions, the snapshot will be unmounted or dump will be deleted.
    if is_partition_table /dev/$volume-snap
    then
      kpartx -l /dev/$volume-snap | while read loop_device _
      do
        findmnt /dev/mapper/$loop_device -no TARGET | while read mount_point
        do
          umount /dev/mapper/$loop_device
          rmdir $mount_point
        done
        if test -f "$(get_backup_location $loop_device)"
        then
          rm -f "$(get_backup_location $loop_device)"
        fi
      done
      kpartx -d /dev/$volume-snap
      rm -f "$(get_backup_location /dev/$volume).mbr"
      rm -f "$(get_backup_location /dev/$volume).sfdisk"
    elif test -f "$(get_backup_location /dev/$volume)"
    then
      rm "$(get_backup_location /dev/$volume)"
    else
      clean_mount_point "$(get_backup_location /dev/$volume)"
    fi
    /usr/sbin/lvremove --yes $volume-snap
  done
  if test -d "$BACKUP_FROM_DIR"
  then
    rmdir "$BACKUP_FROM_DIR"
  fi
}

test ! "${RESTIC_REPOSITORY+x}" -a ! "${RESTIC_REPOSITORY_FILE+x}" &&
  cat <<EOF > /dev/stderr && exit 1
ERROR: Environment variable RESTIC_REPOSITORY or RESTIC_REPOSITORY_FILE should
be defined
EOF

test ! "${RESTIC_PASSWORD+x}" -a ! "${RESTIC_PASSWORD_COMMAND+x}" \
  -a ! "${RESTIC_PASSWORD_FILE+x}" &&
  cat <<EOF > /dev/stderr && exit 1
ERROR: Environment variable RESTIC_PASSWORD, RESTIC_PASSWORD_COMMAND or
RESIC_PASSWORD_FILE should be defined
EOF

trap teardown EXIT

teardown

# Backup MBR and partition tables of harddrives
mkdir -p "$BACKUP_FROM_DIR"
lsblk -l -o TYPE,NAME | grep "^disk " | while read _ harddrive
do
  dd if=/dev/$harddrive of="$BACKUP_FROM_DIR/$harddrive.mbr" bs=512 count=1
  sfdisk -d /dev/$harddrive > "$BACKUP_FROM_DIR/$harddrive.sfdisk"
done
# Backup boot and EFI
mount -m $(findmnt -n -o SOURCE /boot) "$BACKUP_FROM_DIR/boot"
mount -m $(findmnt -n -o SOURCE /boot/efi) "$BACKUP_FROM_DIR/boot_efi"
# Backup filesystems
get_volumes | while read volume
do
  /usr/sbin/lvcreate --snapshot -L 1g -n $volume-snap $volume
  # The created snapshot can contain a disk with partitions or a filesystem
  # directly. If it is a disk with partitions a MBR and a partition table dump
  # is performed. Moreover, each partition in the partition table is mounted if
  # contains a filesystem or dumped if it does not contain a filesystem (BIOS
  # boot). Otherwise, if the created snapshot does not contain a disk with
  # partitions, it is assumed that contains a filesystem directly and it is
  # mounted. If mount fails a dump
  # is created.
  if is_partition_table /dev/$volume-snap
  then
    dd if=/dev/$volume-snap of="$(get_backup_location /dev/$volume).mbr" \
      bs=512 count=1
    sfdisk -d /dev/$volume-snap > "$(get_backup_location /dev/$volume).sfdisk"
    kpartx -a /dev/$volume-snap
    kpartx -l /dev/$volume-snap | while read loop_device _
    do
      if is_filesystem /dev/mapper/$loop_device
      then
        mount -m -o ro /dev/mapper/$loop_device \
          "$(get_backup_location $loop_device)"
      else
        dd if=/dev/mapper/$loop_device of="$(get_backup_location $loop_device)"
      fi
    done
  elif is_filesystem /dev/$volume-snap
  then
    mount -m -o ro /dev/$volume-snap "$(get_backup_location /dev/$volume)"
  else
    dd if=/dev/$volume-snap of="$(get_backup_location /dev/$volume)"
  fi
done

restic backup $BACKUP_FROM_DIR
