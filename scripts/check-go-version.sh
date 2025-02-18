#!/bin/bash

version_regex='[0-9]\.[0-9][0-9]'
update=false
verbose=false

while getopts "uvd" opt; do
    case $opt in
        u) update=true ;;
        v) verbose=true ;;
        x) set -x ;;
        *) echo "Usage: $0 [-u] [-v] [-d]" >&2
           exit 1
           ;;
    esac
done

# Fetch latest go release version
go_latest_version=$(curl -s https://go.dev/dl/?mode=json | jq -r '.[0].version' | awk -F'.' '{gsub("go", ""); print $1"."$2}')
go_previous_version="${go_latest_version%.*}.$((10#${go_latest_version#*.} - 1))"

files_to_update=0

function update() {
    local file=$1
    local pattern=$2
    local current=$3
    local target=$4

    newfile=$(mktemp)
    old_IFS=$IFS
    IFS=''
    while read -r line; do
        match=$(echo $line | grep -e "$pattern")
        if [[ "$match" != "" ]]; then
            line=$(echo "$line" | sed "s/${current}/${target}/g")
        fi
        echo $line >> $newfile
    done < $file
    IFS=$old_IFS

    if [ $verbose = true ]; then
        diff $file $newfile
    fi

    mv $newfile $file
}

function check() {
    local file=$1
    local pattern=$2
    local target=$3

    go_version=$(grep -e "$pattern" $file | head -1 | sed "s/^.*\($version_regex\).*$/\1/")

    if [ "$go_version" = "$target" ]; then
        mismatch=''
    else
        mismatch='*** needs update ***'
        files_to_update=$((files_to_update+1))
    fi

    if [[ $update = true && "$mismatch" != "" ]]; then
        update "$file" "$pattern" "$go_version" "$target"
        mismatch="*** => $target ***"
    fi

    printf "%-50s Go version: %s %s\n" "$file" "$go_version" "$mismatch"
}

check go.mod "^go\s\+$version_regex" $go_previous_version

check docker/Makefile "^.*golang:$version_regex" $go_latest_version

gha_workflows=$(grep -rl go-version .github)
for gha_workflow in ${gha_workflows[@]}; do
    check $gha_workflow "^\s*go-version:\s\+$version_regex" $go_latest_version
done

check .golangci.yml "go:\s\+\"$version_regex\"" $go_previous_version

if [ $files_to_update -eq 0 ]; then
    echo "All files are up to date."
else
    if [[ $update = true ]]; then
        echo "$files_to_update file(s) updated."
    else
        echo "$files_to_update file(s) must be updated. Rerun this script with -u argument."
        exit 1
    fi
fi
