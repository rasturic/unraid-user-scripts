#!/bin/bash
#arrayStarted=true
#name=zfs-backups
#description=Send selected zfs sources to backup zfs pool

# WIP and subject to change.  I wrote this for myself, not for the public.  Use at your own risk.
# Expected snapshot names look like poolname@$snapshot_series-YYYY-MM-DD

set -e

function previous_snapshot() {
    # Determine most recent found on both source and dest
    # Return source named snapshot
    local source=$1
    local target=$2
    local target_snapshot snapshot_series
    snapshot_series=${snapshot_series:-daily}
    target_snapshot=$(zfs list -H -o name -t snapshot ${target}/${source} 2>/dev/null | grep @$snapshot_series | tail --lines 1 | awk -F@ '{print $2}')
    if [[ -n $target_snapshot ]]; then
	    zfs list -H -o name -t snapshot $source | grep $target_snapshot | tail --lines 1
    fi
}

function days_ago() {
    local days=${1:-0}
    date +%Y-%m-%d -d "now - $days days"
}

function today() {
    days_ago 0
}

function old_snapshots() {
    # get list of snapshots beyond number to keep
    # 1. get snapshots of root dataset
    # 2. only print snapshot names
    local dataset=$1
    local snapshot_series=${2:-daily}
    local keep=${3:-3}
    zfs list -H -o name -t snapshot $dataset | grep @$snapshot_series | head --lines -$keep
}

function destroy_old_snapshots() {
    local dataset=$1
    local keep=${2:-3}
    local snapshot_series snap
    snapshot_series=${snapshot_series:-daily}
    for snap in $(snapshot_series=$snapshot_series old_snapshots $dataset $keep); do
        zfs destroy $flags -R $snap
        echo Deleting old snapshot $snap
    done
}

function create_snapshots() {
    local dataset=$1
    local snapshot_series=$2

    local weekly_day=Mon
    local monthly_day=1

    if [[ $snapshot_series == daily ]]; then
      zfs snapshot -r $dataset@${snapshot_series}-$(today) || true
    fi
    if [[ $snapshot_series == weekly ]] && [[ $((date +%a)) == $weekly_day ]]; then
      zfs snapshot -r $dataset@${snapshot_series}-$(today) || true
    fi
    if [[ $snapshot_series == monthly ]] && [[ $((date +%a)) == $montlhy_day ]]; then
      zfs snapshot -r $dataset@${snapshot_series}-$(today) || true
    fi
}

function send_snapshots() {
    # 1. Find last snapshot on target also found on source.  The source snapshot is the previous snapshot.
    # 2. Current snapshot is the one we just took on source.
    # 3. Set mountpoint so zfs won't mount over the source.
    # 4. Set readonly on target to prevent accidental changes.
    # 5. If we have previous snapshots, send them all.

    local source_dataset
    local target_dataset
    local last_snapshot
    local target_mountpoint
    local source_args

    source_dataset=$1
    target_dataset=$2

    target_mountpoint=/mnt/$target_dataset/$source_dataset
    last_snapshot=$(previous_snapshot $source_dataset $target_dataset)
    echo "$(date) Starting $source_dataset backups"
    zfs snapshot -r $source_dataset@${snapshot_series}-$(today) || true
    if [[ -n $last_snapshot ]]; then
        source_args="-I $last_snapshot $source_dataset@${snapshot_series}-$(today)"
    else
        source_args="$source_dataset@${snapshot_series}-$(today)"
    fi
    zfs send -v $flags -R $source_args | zfs receive -v $flags -o readonly=on -o mountpoint=$target_mountpoint -e $target_dataset
    echo "$(date) $source_dataset Done"
}

function running_containers() {
    # list of running containers to manage except those found in ignore list
    local all_containers containers
    all_containers=$(docker ps --format "table {{.Names}}" | tail --lines +2)
    containers="$all_containers"
    if [[ -n $ignore_containers ]]; then
        containers=$(echo "$all_containers" | grep -vE "$ignore_containers")
    fi
    echo $containers
}

function start_stop_containers() {
    local containers=$1
    local operation=${2:-start}
    local flags=""

    if [[ $operation == stop ]]; then
        flags="-t 240"
    fi

    if [[ $stop_containers -eq 1 ]]; then
        echo Running $operation on containers $containers
        docker $operation $flags $containers
    fi

}

function main() {
    local containers
    containers=$(running_containers)

    start_stop_containers "$containers" "stop"

    # Edit to suit.  Add sources, targets, and daily snapshot retentions
    send_snapshots disk1 gattaca/zfs_snapshots

    # trim daily snapshots sent over
    destroy_old_snapshots disk1 daily 3
    destroy_old_snapshots gattaca/zfs_snapshots/disk1 daily 10

    # create long term snapshots
    create_snapshots gattaca/zfs_snapshots/disk1 weekly
    create_snapshots gattaca/zfs_snapshots/disk1 monthly

    # trim long term snapshots
    snapshot_series=weekly destroy_old_snpashots gattaca/zfs_snapshots/disk1 8
    snapshot_series=monthly destroy_old_snpashots gattaca/zfs_snapshots/disk1 6
    snapshot_series=yearly destroy_old_snpashots gattaca/zfs_snapshots/disk1 2

    start_stop_containers "$containers" "start"
}

stop_containers=1
flags=
snapshot_series=daily
ignore_containers="^(smokeping)"

main
