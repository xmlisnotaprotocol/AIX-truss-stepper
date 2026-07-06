#!/bin/bash

# Usage: ./parse_aix_truss.sh < truss_output.txt

declare -A pid_tree   # Maps child_pid -> parent_pid
declare -A exec_map   # Maps pid -> exec name
declare -A seen_pid   # Helps avoid redundant output

function print_fork() {
    local parent=$1
    local child=$2
    echo "[FORK] Parent PID: $parent => Child PID: $child"
}

function print_exec() {
    local pid=$1
    local cmd=$2
    echo "[EXEC] PID: $pid => Executing: $cmd"
}

function print_exit() {
    local pid=$1
    echo "[EXIT] PID: $pid exited"
}

while read -r line; do
    # AIX truss line example:
    #   8192196:       kfork()                              = 12845268
    #   12845268:       kfork()         (returning as child ...) = 0
    #   13107408:       45744221: _getpid()                  = 13107408
    #   13107408:       45744221: execve(...)                argc: N
    #   13107408:       45744221: _exit(0)

    # Extract the leftmost PID and sub-PID (optional)
    if [[ "$line" =~ ^([0-9]+):([[:space:]]+([0-9]+):)?[[:space:]]+(.*)$ ]]; then
        main_pid="${BASH_REMATCH[1]}"
        thread_pid="${BASH_REMATCH[3]}"
        content="${BASH_REMATCH[4]}"
        pid="${thread_pid:-$main_pid}"
    else
        continue
    fi

    # Match kfork() result lines (parent sees child PID)
    if [[ "$content" =~ kfork\(\)[[:space:]]+=\ ([0-9]+) ]]; then
        child_pid="${BASH_REMATCH[1]}"
        pid_tree["$child_pid"]="$pid"
        print_fork "$pid" "$child_pid"

    # Match kfork() returning as child (child sees 0)
    elif [[ "$content" =~ kfork\(\)[[:space:]]+\(returning\ as\ child\ \.\.\.\)[[:space:]]+=\ 0 ]]; then
        # No action needed here for mapping, child_pid will appear in parent kfork
        :  # no-op

    # Match execve call
    elif [[ "$content" =~ execve\(\"([^\"]+)\" ]]; then
        cmd="${BASH_REMATCH[1]}"
        exec_map["$pid"]="$cmd"
        print_exec "$pid" "$cmd"

    # Match _exit() or exit()
    elif [[ "$content" =~ _?exit\([0-9]+\) ]]; then
        print_exit "$pid"
        seen_pid["$pid"]=1
    fi

done
