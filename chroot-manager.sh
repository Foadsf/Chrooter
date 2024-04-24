#!/bin/bash

# Function to create a new chroot environment
create_environment() {
    local env_name=$1
    mkdir -p "/var/chroot/$env_name"

    # Copy essential files and directories
    directories=("/bin" "/lib")
    for dir in "${directories[@]}"; do
        sudo cp -R "$dir" "/var/chroot/$env_name$dir"
    done
    
    # Check if /lib64 exists and copy it if present
    if [ -d "/lib64" ]; then
        sudo cp -R /lib64 "/var/chroot/$env_name"
    fi
    
    # Create /usr directory and copy /usr/bin and /usr/lib
    sudo mkdir -p "/var/chroot/$env_name/usr"
    sudo cp -R /usr/bin "/var/chroot/$env_name/usr"
    sudo cp -R /usr/lib "/var/chroot/$env_name/usr"
    
    # Create necessary device nodes
    sudo mkdir -p "/var/chroot/$env_name/dev"
    sudo mknod -m 666 "/var/chroot/$env_name/dev/null" c 1 3
    sudo mknod -m 666 "/var/chroot/$env_name/dev/tty" c 5 0
    sudo mknod -m 666 "/var/chroot/$env_name/dev/zero" c 1 5
    sudo mknod -m 666 "/var/chroot/$env_name/dev/random" c 1 8
    echo "Created chroot environment: $env_name"
}

# Function to start a chroot environment
start_environment() {
    local env_name=$1
    sudo chroot "/var/chroot/$env_name" /bin/bash
}

# Function to run a command inside a chroot environment
run_command() {
    local env_name=$1
    shift
    sudo chroot "/var/chroot/$env_name" "$@"
}

# Function to build a chroot environment from a Chrootfile
build_environment() {
    local env_name=$1
    local chrootfile=$2
    mkdir -p "/var/chroot/$env_name"
    while IFS= read -r line; do
        if [[ $line == COPY* ]]; then
            src=$(echo "$line" | awk '{print $2}')
            dest=$(echo "$line" | awk '{print $3}')
            sudo cp -R "$src" "/var/chroot/$env_name/$dest"
        elif [[ $line == MKDEV* ]]; then
            dev=$(echo "$line" | awk '{print $2}')
            type=$(echo "$line" | awk '{print $3}')
            major=$(echo "$line" | awk '{print $4}')
            minor=$(echo "$line" | awk '{print $5}')
            sudo mknod "/var/chroot/$env_name/$dev" "$type" "$major" "$minor"
        elif [[ $line == RUN* ]]; then
            cmd=$(echo "$line" | sed 's/RUN //')
            sudo chroot "/var/chroot/$env_name" /bin/bash -c "$cmd"
        fi
    done < "$chrootfile"
    echo "Built chroot environment: $env_name"
}

# Function to list chroot environments
list_environments() {
    ls -1 "/var/chroot"
}

# Function to remove a chroot environment
remove_environment() {
    local env_name=$1
    sudo rm -rf "/var/chroot/$env_name"
    echo "Removed chroot environment: $env_name"
}

# Main script logic
case "$1" in
    create)
        create_environment "$2"
        ;;
    start)
        start_environment "$2"
        ;;
    run)
        run_command "$2" "${@:3}"
        ;;
    build)
        build_environment "$2" "$3"
        ;;
    ps)
        list_environments
        ;;
    rm)
        remove_environment "$2"
        ;;
    *)
        echo "Usage: chrooter [create|start|run|build|ps|rm] <environment_name> [command]"
        ;;
esac