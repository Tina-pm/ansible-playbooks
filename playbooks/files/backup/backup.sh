#!/usr/bin/env -S sh -e -u
#   Copyright (C) 2024 Martina Ferrari, Simó Albert i Beltran
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

BACKUP_FROM_DIR="${BACKUP_FROM_DIR:-/tmp/bk-snap}"

get_backup_location(){
  # Get backup location for loop device name
  local loop_device_name=$1
  echo $BACKUP_FROM_DIR/$(echo $loop_device_name | sed 's/--snap//')
}

get_volumes(){
  # Get LVM volumes that are not snapshots
  lvs --noheadings -o vg_name,lv_name,lv_attr | awk '$3 ~ /^[-oV]/ {print $1"/"$2}'
}

is_partition_table(){
  # Exit with 0 if the parameter is a device with a partition table, 1 otherwise.
  blkid $1 | grep -q " PTTYPE="
}

is_filesystem(){
  # Exit with 0 if the parameter is a device with a filesystem, 1 otherwise.
  # TODO(sim6): Detection should be improved to only return 0 if the filesystem can be
  # mounted.
  # TODO(sim6): Swap partition should not be detected as filesystem.
  blkid $1 | grep -q " TYPE="
}

teardown(){
  # Remove MBR and partition tables backup
  lsblk -l -o TYPE,NAME | grep "^disk " | while read _ harddrive
  do
    rm -f $BACKUP_FROM_DIR/$harddrive.mbr
    rm -f $BACKUP_FROM_DIR/$harddrive.sfdisk
  done
  # Umount boot and EFI
  for mount_point in boot boot_efi
  do
    mountpoint -q $BACKUP_FROM_DIR/$mount_point &&
      umount $BACKUP_FROM_DIR/$mount_point
  done
  # Umount filesystems and remove snapshots
  get_volumes | while read volume
  do
    test ! -b /dev/$volume-snap &&
      continue
    # The created snapshot can contain a disk with partitions that are mounted or
    # dumped. These partitions will be unmounted or dumps will be deleted.
    # Otherwise, if the created snapshot does not contain a disk with partitions, the
    # snapshot will be unmounted or dump will be deleted.
    if is_partition_table /dev/$volume-snap
    then
      kpartx -l /dev/$volume-snap | while read loop_device _
      do
        findmnt /dev/mapper/$loop_device -o TARGET | while read mount_point
        do
	  umount /dev/mapper/$loop_device
	  rmdir $mount_point
	done
	test -f $(get_backup_location $loop_device) &&
          rm -f $(get_backup_location $loop_device)
      done
      kpartx -d /dev/$volume-snap
      rm -f $BACKUP_FROM_DIR/$volume.mbr
      rm -f $BACKUP_FROM_DIR/$volume.sfdisk
    else
      mountpoint -q $BACKUP_FROM_DIR/$volume &&
        umount $BACKUP_FROM_DIR/$volume &&
	  rmdir $BACKUP_FROM_DIR/$volume
      test -f $BACKUP_FROM_DIR/$volume &&
        rm $BACKUP_FROM_DIR/$volume
    fi
    /usr/sbin/lvremove --yes $volume-snap
  done
}

test ! "${RESTIC_REPOSITORY+x}" -a ! "${RESTIC_REPOSITORY_FILE+x}" &&
  echo "ERROR: Environment variable RESTIC_REPOSITORY or RESTIC_REPOSITORY_FILE should be defined" > /dev/stderr &&
    exit 1

test ! "${RESTIC_PASSWORD+x}" -a ! "${RESTIC_PASSWORD_COMMAND+x}" -a ! "${RESTIC_PASSWORD_FILE+x}" &&
  echo "ERROR: Environment variable RESTIC_PASSWORD, RESTIC_PASSWORD_COMMAND or RESIC_PASSWORD_FILE should be defined" > /dev/stderr &&
    exit 1

trap teardown EXIT

teardown

# Backup MBR and partition tables of harddrives
mkdir -p $BACKUP_FROM_DIR
lsblk -l -o TYPE,NAME | grep "^disk " | while read _ harddrive
do
  dd if=/dev/$harddrive of=$BACKUP_FROM_DIR/$harddrive.mbr bs=512 count=1
  sfdisk -d /dev/$harddrive > $BACKUP_FROM_DIR/$harddrive.sfdisk
done
# Backup boot and EFI
mount -m $(findmnt -n -o SOURCE /boot) $BACKUP_FROM_DIR/boot
mount -m $(findmnt -n -o SOURCE /boot/efi) $BACKUP_FROM_DIR/boot_efi
# Backup filesystems
get_volumes | while read volume
do
  /usr/sbin/lvcreate --snapshot -L 1g -n $volume-snap $volume
  # The created snapshot can contain a disk with partitions or a filesystem directly.
  # If it is a disk with partitions a MBR and a partition table dump is performed.
  # Moreover, each partition in the partition table is mounted if contains a filesystem
  # or dumped if it does not contain a filesystem (BIOS boot).
  # Otherwise, if the created snapshot does not contain a disk with partitions, it is
  # assumed that contains a filesystem directly and it is mounted. If mount fails a dump
  # is created.
  if is_partition_table /dev/$volume-snap
  then
    dd if=/dev/$volume-snap of=$BACKUP_FROM_DIR/$volume.mbr bs=512 count=1
    sfdisk -d /dev/$volume-snap > $BACKUP_FROM_DIR/$volume.sfdisk
    kpartx -a /dev/$volume-snap
    kpartx -l /dev/$volume-snap | while read loop_device _
    do
      if is_filesystem /dev/mapper/$loop_device
      then
	mount -m -o ro /dev/mapper/$loop_device $(get_backup_location $loop_device)
      else
        dd if=/dev/mapper/$loop_device of=$(get_backup_location $loop_device)
      fi
    done
  else
    if is_filesystem /dev/$volume-snap
    then
      mount -m -o ro /dev/$volume-snap $BACKUP_FROM_DIR/$volume
    else
      dd if=/dev/$volume-snap of=$BACKUP_FROM_DIR/$volume
    fi
  fi
done

restic backup $BACKUP_FROM_DIR
