#!/bin/bash

set -euo pipefail  # Enable strict error handling

# Constants
CHROOT_BASE="/var/chroot"
LOG_FILE="/var/log/chrooter.log"
VALID_NAME_PATTERN="^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"

# Helper function for logging
log_message() {
    local level=$1
    shift
    local message=$@
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
}

# Helper function for error handling
error_exit() {
    local message=$1
    log_message "ERROR" "$message"
    echo "Error: $message" >&2
    exit 1
}

# Check for root privileges
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error_exit "This script must be run as root"
    fi
    if ! command -v fuser &> /dev/null; then
        error_exit "fuser command not found. Please install psmisc package."
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

    # Special handling for Python binaries to copy their standard library
    if [[ "$binary_path" == *"/python"* ]]; then
        log_message "INFO" "Python binary detected. Copying Python libraries for $binary_path..."

        # Find the python version, e.g., 3.9 from /usr/bin/python3.9
        local python_version=$(echo "$binary_path" | grep -oP 'python\K[0-9]+\.[0-9]+')
        if [ -z "$python_version" ]; then
            # Fallback for generic python, try to get system's default python3 version
            python_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        fi

        log_message "INFO" "Detected Python version: $python_version"
        local python_lib_path="/usr/lib/python${python_version}"

        if [ -d "$python_lib_path" ]; then
            # Ensure the target directory exists
            mkdir -p "$env_path/usr/lib"
            cp -r "$python_lib_path" "$env_path/usr/lib/" 2>/dev/null || true
        fi

        # Also copy the zip file if it exists
        local python_zip_file="/usr/lib/python${python_version%.*}.zip"
        if [ -f "$python_zip_file" ]; then
            cp "$python_zip_file" "$env_path/usr/lib/" 2>/dev/null || true
        fi

        # Also copy lib-dynload, which is often needed.
        # This is not typically versioned, but let's check for a versioned one first.
        local dynload_path="/usr/lib/python${python_version}/lib-dynload"
        if [ -d "$dynload_path" ]; then
             cp -r "$dynload_path" "$env_path/usr/lib/python${python_version}/" 2>/dev/null || true
        elif [ -d "/usr/lib/lib-dynload" ]; then
            # Fallback to a generic lib-dynload
            cp -r "/usr/lib/lib-dynload" "$env_path/usr/lib/" 2>/dev/null || true
        fi
    fi
}

# Function to create a new chroot environment
create_environment() {
    local env_name=$1
    log_message "INFO" "Attempting to create environment: $env_name"
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
        "/bin/sleep"
        "/usr/bin/env"
    )

    for binary in "${essential_binaries[@]}"; do
        copy_binary_with_deps "$binary" "$binary" "$env_path"
    done

    # Create necessary device nodes
    mkdir -p "$env_path/dev"
    mkdir -p "$env_path/proc"
    mkdir -p "$env_path/sys"
    mknod -m 666 "$env_path/dev/null" c 1 3
    mknod -m 666 "$env_path/dev/tty" c 5 0
    mknod -m 666 "$env_path/dev/zero" c 1 5
    mknod -m 666 "$env_path/dev/random" c 1 8

    echo "Successfully created chroot environment: $env_name"
    log_message "INFO" "Successfully created environment: $env_name"
}

# Function to start a chroot environment
start_environment() {
    local env_name=$1
    log_message "INFO" "Attempting to start environment: $env_name"
    validate_env_name "$env_name"

    local env_path="$CHROOT_BASE/$env_name"
    if [ ! -d "$env_path" ]; then
        error_exit "Environment $env_name does not exist"
    fi

    # Mount essential filesystems
    mount -t proc proc "$env_path/proc" || error_exit "Failed to mount proc"
    mount -t sysfs sys "$env_path/sys" || error_exit "Failed to mount sysfs"

    log_message "INFO" "Entering chroot environment: $env_name"
    # The trap is defined with double quotes to ensure variable expansion at the time of setting the trap.
    # This prevents "unbound variable" errors when the trap is executed on EXIT, as the variables' values
    # are embedded in the trap command string.
    trap "umount '$env_path/proc' '$env_path/sys'; log_message 'INFO' 'Exited chroot environment: $env_name'" EXIT

    # Set a safe locale to prevent warnings inside the chroot
    chroot "$env_path" env LC_ALL=C /bin/bash || error_exit "Failed to start chroot environment"
}

# Function to run a command inside a chroot environment
run_command() {
    local env_name=$1
    local command_to_run="${@:2}"
    log_message "INFO" "Attempting to run command in environment '$env_name': $command_to_run"
    validate_env_name "$env_name"
    shift

    local env_path="$CHROOT_BASE/$env_name"
    if [ ! -d "$env_path" ]; then
        error_exit "Environment $env_name does not exist"
    fi

    # Set a safe locale to prevent warnings inside the chroot
    chroot "$env_path" env LC_ALL=C "$@" || error_exit "Command execution failed: $command_to_run"
    log_message "INFO" "Successfully ran command in environment '$env_name': $command_to_run"
}

# Function to build a chroot environment from a Chrootfile
build_environment() {
    local env_name=$1
    local chrootfile=$2
    log_message "INFO" "Attempting to build environment '$env_name' from Chrootfile: $chrootfile"
    validate_env_name "$env_name"

    if [ ! -f "$chrootfile" ]; then
        error_exit "Chrootfile not found: $chrootfile"
    fi

    local env_path="$CHROOT_BASE/$env_name"
    mkdir -p "$env_path" || error_exit "Failed to create environment directory"

    # Create basic directory structure and device nodes
    mkdir -p "$env_path/dev"
    mkdir -p "$env_path/proc"
    mkdir -p "$env_path/sys"
    mknod -m 666 "$env_path/dev/null" c 1 3
    mknod -m 666 "$env_path/dev/tty" c 5 0
    mknod -m 666 "$env_path/dev/zero" c 1 5
    mknod -m 666 "$env_path/dev/random" c 1 8

    # A list of essential binaries to include in the chroot
    local essential_binaries=(
        "/bin/bash"
        "/bin/ls"
        "/bin/cat"
        "/bin/echo"
        "/bin/sh"
        "/bin/sleep"
        "/usr/bin/env"
        "/bin/mkdir"
        "/bin/chmod"
    )

    for binary in "${essential_binaries[@]}"; do
        copy_binary_with_deps "$binary" "$binary" "$env_path"
    done

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

                # Security: prevent path traversal
                if [[ "$src" == *".."* ]] || [[ "$dest" == *".."* ]]; then
                    error_exit "Path traversal attempt detected in COPY command: $line"
                fi

                log_message "INFO" "Chrootfile: COPY $src $dest"
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
                log_message "INFO" "Chrootfile: MKDEV $dev $type $major $minor"
                mknod "$env_path/$dev" "$type" "$major" "$minor" || \
                    error_exit "Failed to create device node: $dev"
                ;;
            RUN*)
                cmd=${line#RUN }
                if [ -z "$cmd" ]; then
                    error_exit "Empty RUN command"
                fi
                log_message "INFO" "Chrootfile: RUN $cmd"
                # Set a safe locale to prevent warnings inside the chroot
                chroot "$env_path" env LC_ALL=C /bin/bash -c "$cmd" || error_exit "Command failed: $cmd"
                ;;
            *)
                error_exit "Unknown command in Chrootfile: $line"
                ;;
        esac
    done < "$chrootfile"

    echo "Successfully built chroot environment: $env_name"
    log_message "INFO" "Successfully built environment '$env_name' from Chrootfile: $chrootfile"
}

# Function to list chroot environments
list_environments() {
    log_message "INFO" "Listing environments"
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
    log_message "INFO" "Attempting to remove environment: $env_name"
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
        log_message "INFO" "Unmounting $env_path/proc"
        umount "$env_path/proc" || error_exit "Failed to unmount proc"
    done

    while mountpoint -q "$env_path/sys" 2>/dev/null; do
        log_message "INFO" "Unmounting $env_path/sys"
        umount "$env_path/sys" || error_exit "Failed to unmount sys"
    done

    rm -rf "$env_path" || error_exit "Failed to remove environment"
    echo "Successfully removed chroot environment: $env_name"
    log_message "INFO" "Successfully removed environment: $env_name"
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
