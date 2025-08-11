# Chrooter

Chrooter is a Docker-like CLI tool for managing chroot sandbox environments. It simplifies the creation, management, and use of chroot environments with a familiar syntax.

This version of Chrooter has been significantly overhauled for robustness and security.

## Features

- **Automatic Dependency Resolution:** When creating environments or copying binaries with a `Chrootfile`, Chrooter automatically finds and copies all necessary dependencies using `ldd`.
- **Minimal Environments:** The `create` command sets up a minimal, functional environment with a set of essential commands (`bash`, `sh`, `ls`, `cat`, `echo`, `sleep`).
- **Powerful `build` command:** Build environments from a `Chrootfile`, with automatic dependency handling for copied binaries.
- **Secure by Default:** Includes checks for root privileges, validation of environment names to prevent path traversal, and protection against removing running environments.
- **Interactive Sessions:** The `start` command provides an interactive shell within the chroot and correctly mounts `/proc` and `/sys`.
- **Centralized Logging:** All operations and errors are logged to `/var/log/chrooter.log` for easy traceability and debugging.

## Logging

All actions performed by `chrooter` are logged to `/var/log/chrooter.log`. This includes the creation, removal, starting, and building of environments, as well as any errors that occur. You can monitor this file to see a detailed history of operations.

## Installation

1. Clone the repository:

   ```sh
   git clone https://github.com/Foadsf/Chrooter.git
   cd chrooter
   ```

2. Run the install script. This will copy the `chrooter` script to `/usr/local/bin`.

   ```sh
   chmod +x install.sh
   sudo ./install.sh
   ```

   **Note:** The script requires `rsync` and `psmisc` (`fuser`) to be installed on the host system. You can install them with:
   `sudo apt-get update && sudo apt-get install -y rsync psmisc`

## Uninstallation

To remove Chrooter, run the `uninstall.sh` script:
```sh
sudo ./uninstall.sh
```

## Usage

**Note:** All `chrooter` commands must be run as root or with `sudo`.

### Create a new environment

This creates a minimal environment with a few essential commands and their dependencies.
```sh
sudo chrooter create <environment_name>
```

### Start an environment

This starts an interactive `bash` shell inside the environment. `/proc` and `/sys` are mounted.
```sh
sudo chrooter start <environment_name>
```

### Run a command inside an environment

```sh
sudo chrooter run <environment_name> <command>
```

### Build an environment from a `Chrootfile`

The `build` command creates an environment based on a `Chrootfile`. It automatically handles dependencies for any binaries you `COPY`.

1. Create a `Chrootfile` in the desired directory.
2. Run the build command:

   ```sh
   sudo chrooter build <environment_name> Chrootfile
   ```

### List environments

```sh
sudo chrooter ps
```

### Remove an environment

```sh
sudo chrooter rm <environment_name>
```

### Example `Chrootfile`

This example creates an environment, copies the `pwd` command into it, and then runs a script that creates a file.

**`install_stuff.sh`:**
```sh
#!/bin/sh
echo "This script was run inside the chroot" > /tmp/test_result
```

**`Chrootfile`:**
```plaintext
# Copy the pwd binary and its dependencies
COPY /bin/pwd /bin/pwd

# Copy and run a custom script
COPY install_stuff.sh /tmp/install_stuff.sh
RUN chmod +x /tmp/install_stuff.sh
RUN /tmp/install_stuff.sh
```

## License

Chrooter is licensed under the GPL-3.0 License. See the [LICENSE](LICENSE) file for details.
