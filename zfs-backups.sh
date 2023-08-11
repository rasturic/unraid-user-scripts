#!/bin/bash
#arrayStarted=true
# WIP - not ready for use
# Send selected sources to backup zfs pool
# Expected snapshot names look like poolname@$snapshot_series-YYYY-MM-DD

set -x
set -e

function previous_snapshot() {
    # Determine most recent found on both source and dest
    # Return source named snapshot
    local source=$1
    local target=$2
    local target_snapshot
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
    local keep=${2:-3}
    zfs list -H -o name -t snapshot $dataset | grep @$snapshot_series | head --lines -$keep
}

function destroy_old_snapshots() {
    local dataset=$1
    local keep=${2:-3}
    local snap
    for snap in $(old_snapshots $dataset $keep); do
        echo zfs destroy $flags -R $snap
        echo Deleting old snapshot $snap
    done
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
    zfs send $flags -R $source_args | zfs receive $flags -o readonly=on -o mountpoint=$target_mountpoint -e $target_dataset
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

    send_snapshots disk1 gattaca/zfs_snapshots
    destroy_old_snapshots disk1 3
    destroy_old_snapshots gattaca/zfs_snapshots 10

    start_stop_containers "$containers" "start"
}

stop_containers=0
flags="-n"
snapshot_series=daily
ignore_containers="^(smokeping)"

main
