# unraid-user-scripts

Here are a few user scripts I use on Unraid

## zfs-backups.sh

A _User Scripts_ tool to send snapshots from zfs-formatted array disks to a zfs pool, intended to be executed daily.

### What it does

1. Stops running containers
2. Determines if there are previous snapshots 
3. If no previous snapshots, send a full over to the target
4. If a snapshot is found on the target and the snapshot name matches the source, send over all snapshots up to the latest one.
5. Trims older snapshots on the source dataset
6. Starts the containers it stopped
