#!/bin/bash

set -euo pipefail  # Enable strict error handling

# Constants
CHROOT_BASE="/var/chroot"
VALID_NAME_PATTERN="^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"

# Helper function for error handling
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check for root privileges
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error_exit "This script must be run as root"
    fi
}

# Validate environment name
validate_env_name() {
    local env_name=$1
    if ! [[ $env_name =~ $VALID_NAME_PATTERN ]]; then
        error_exit "Invalid environment name. Use only alphanumeric characters, dots, dashes, and underscores"
    fi
}

# Helper function to copy a binary and its dependencies
copy_binary_with_deps() {
    local binary_path=$1
    local dest_in_chroot=$2
    local env_path=$3

    if [ ! -f "$binary_path" ]; then
        echo "Warning: Binary not found: $binary_path"
        return
    fi

    # Copy the binary itself to the destination
    local dest_path="$env_path$dest_in_chroot"
    mkdir -p "$(dirname "$dest_path")"
    cp "$binary_path" "$dest_path"

    # Get dependencies and copy them to their original paths
    local deps=$(ldd "$binary_path" | awk 'NF == 4 {print $3}' | grep '^/')
    for dep in $deps; do
        local dep_dest_path="$env_path$dep"
        if [ ! -e "$dep_dest_path" ]; then
            mkdir -p "$(dirname "$dep_dest_path")"
            cp "$dep" "$dep_dest_path"
        fi
    done

    # The loader is special
    local loader=$(ldd "$binary_path" | grep 'ld-linux' | awk '{print $1}')
    if [ -n "$loader" ] && [ -f "$loader" ]; then
        local loader_dest_path="$env_path$loader"
        if [ ! -e "$loader_dest_path" ]; then
            mkdir -p "$(dirname "$loader_dest_path")"
            cp "$loader" "$loader_dest_path"
        fi
    fi
}

# Function to create a new chroot environment
create_environment() {
    local env_name=$1
    validate_env_name "$env_name"
    
    local env_path="$CHROOT_BASE/$env_name"
    if [ -d "$env_path" ]; then
        error_exit "Environment $env_name already exists"
    fi

    echo "Creating chroot environment: $env_name"
    mkdir -p "$env_path"

    # A list of essential binaries to include in the chroot
    local essential_binaries=(
        "/bin/bash"
        "/bin/ls"
        "/bin/cat"
        "/bin/echo"
        "/bin/sh"
    )

    for binary in "${essential_binaries[@]}"; do
        copy_binary_with_deps "$binary" "$binary" "$env_path"
    done

    # Create necessary device nodes
    mkdir -p "$env_path/dev"
    mknod -m 666 "$env_path/dev/null" c 1 3
    mknod -m 666 "$env_path/dev/tty" c 5 0
    mknod -m 666 "$env_path/dev/zero" c 1 5
    mknod -m 666 "$env_path/dev/random" c 1 8

    echo "Successfully created chroot environment: $env_name"
}

# Function to start a chroot environment
start_environment() {
    local env_name=$1
    validate_env_name "$env_name"

    local env_path="$CHROOT_BASE/$env_name"
    if [ ! -d "$env_path" ]; then
        error_exit "Environment $env_name does not exist"
    fi

    # Mount essential filesystems
    mount -t proc proc "$env_path/proc" || error_exit "Failed to mount proc"
    mount -t sysfs sys "$env_path/sys" || error_exit "Failed to mount sysfs"

    trap 'umount "$env_path/proc" "$env_path/sys"' EXIT

    chroot "$env_path" /bin/bash || error_exit "Failed to start chroot environment"
}

# Function to run a command inside a chroot environment
run_command() {
    local env_name=$1
    validate_env_name "$env_name"
    shift

    local env_path="$CHROOT_BASE/$env_name"
    if [ ! -d "$env_path" ]; then
        error_exit "Environment $env_name does not exist"
    fi

    chroot "$env_path" "$@" || error_exit "Command execution failed"
}

# Function to build a chroot environment from a Chrootfile
build_environment() {
    local env_name=$1
    local chrootfile=$2
    validate_env_name "$env_name"

    if [ ! -f "$chrootfile" ]; then
        error_exit "Chrootfile not found: $chrootfile"
    fi

    local env_path="$CHROOT_BASE/$env_name"
    mkdir -p "$env_path" || error_exit "Failed to create environment directory"

    # Create basic directory structure and device nodes
    mkdir -p "$env_path/dev"
    mknod -m 666 "$env_path/dev/null" c 1 3
    mknod -m 666 "$env_path/dev/tty" c 5 0
    mknod -m 666 "$env_path/dev/zero" c 1 5
    mknod -m 666 "$env_path/dev/random" c 1 8

    # Copy bash and sh for RUN commands
    copy_binary_with_deps "/bin/bash" "/bin/bash" "$env_path"
    copy_binary_with_deps "/bin/sh" "/bin/sh" "$env_path"
    copy_binary_with_deps "/bin/echo" "/bin/echo" "$env_path"
    copy_binary_with_deps "/bin/cat" "/bin/cat" "$env_path"

    # Process Chrootfile
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        case "$line" in
            COPY*)
                read -r _ src dest <<< "$line"
                if [ -z "$src" ] || [ -z "$dest" ]; then
                    error_exit "Invalid COPY command: $line"
                fi

                mkdir -p "$(dirname "$env_path/$dest")"
                if [ -f "$src" ] && [ -x "$src" ]; then
                    # It's a binary file, copy with dependencies
                    copy_binary_with_deps "$src" "$dest" "$env_path"
                else
                    # It's a directory or a non-executable file, just copy it.
                    cp -a "$src" "$env_path/$dest" || error_exit "Failed to copy: $src"
                fi
                ;;
            MKDEV*)
                read -r _ dev type major minor <<< "$line"
                if [ -z "$dev" ] || [ -z "$type" ] || [ -z "$major" ] || [ -z "$minor" ]; then
                    error_exit "Invalid MKDEV command: $line"
                fi
                mknod "$env_path/$dev" "$type" "$major" "$minor" || \
                    error_exit "Failed to create device node: $dev"
                ;;
            RUN*)
                cmd=${line#RUN }
                if [ -z "$cmd" ]; then
                    error_exit "Empty RUN command"
                fi
                chroot "$env_path" /bin/bash -c "$cmd" || error_exit "Command failed: $cmd"
                ;;
            *)
                error_exit "Unknown command in Chrootfile: $line"
                ;;
        esac
    done < "$chrootfile"

    echo "Successfully built chroot environment: $env_name"
}

# Function to list chroot environments
list_environments() {
    if [ ! -d "$CHROOT_BASE" ]; then
        echo "No chroot environments found"
        return
    fi

    echo "Available chroot environments:"
    ls -1 "$CHROOT_BASE"
}

# Function to remove a chroot environment
remove_environment() {
    local env_name=$1
    validate_env_name "$env_name"

    local env_path="$CHROOT_BASE/$env_name"
    if [ ! -d "$env_path" ]; then
        error_exit "Environment $env_name does not exist"
    fi

    # Ensure no processes are using the environment
    if fuser -s "$env_path" 2>/dev/null; then
        error_exit "Environment is in use. Please stop all processes first"
    fi

    # Unmount any mounted filesystems
    while mountpoint -q "$env_path/proc" 2>/dev/null; do
        umount "$env_path/proc" || error_exit "Failed to unmount proc"
    done

    while mountpoint -q "$env_path/sys" 2>/dev/null; do
        umount "$env_path/sys" || error_exit "Failed to unmount sys"
    done

    rm -rf "$env_path" || error_exit "Failed to remove environment"
    echo "Successfully removed chroot environment: $env_name"
}

# Main script logic
check_root

case "$1" in
    create)
        [ $# -eq 2 ] || error_exit "Usage: $0 create <environment_name>"
        create_environment "$2"
        ;;
    start)
        [ $# -eq 2 ] || error_exit "Usage: $0 start <environment_name>"
        start_environment "$2"
        ;;
    run)
        [ $# -ge 3 ] || error_exit "Usage: $0 run <environment_name> <command> [args...]"
        run_command "$2" "${@:3}"
        ;;
    build)
        [ $# -eq 3 ] || error_exit "Usage: $0 build <environment_name> <chrootfile>"
        build_environment "$2" "$3"
        ;;
    ps)
        list_environments
        ;;
    rm)
        [ $# -eq 2 ] || error_exit "Usage: $0 rm <environment_name>"
        remove_environment "$2"
        ;;
    *)
        echo "Usage: $0 {create|start|run|build|ps|rm} <environment_name> [args...]"
        exit 1
        ;;
esac
