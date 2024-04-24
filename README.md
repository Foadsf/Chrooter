# Chrooter

Chrooter is a Docker-like CLI tool for managing chroot sandbox environments. It simplifies the creation, management, and use of chroot environments with a familiar syntax.

## Features

- Create chroot environments with a single command
- Start and run commands in chroot environments
- Build environments from a configuration file (`Chrootfile`)
- List, remove, and manage environments easily

## Installation

1. Clone the repository:

   ```sh
   git clone https://github.com/Foadsf/Chrooter.git
   cd chrooter
   ```

2. Run the install script:

   ```sh
   chmod +x install.sh
   sudo ./install.sh
   ```

## Usage

### Create a new environment

```sh
chrooter create <environment_name>
```

### Start an environment

```sh
chrooter start <environment_name>
```

### Run a command inside an environment

```sh
chrooter run <environment_name> <command>
```

### Build an environment from a `Chrootfile`

1. Create a `Chrootfile` in the desired directory.
2. Run the build command:

   ```sh
   chrooter build <environment_name> [Chrootfile]
   ```

### List environments

```sh
chrooter ps
```

### Remove an environment

```sh
chrooter rm <environment_name>
```

### Example `Chrootfile`

```plaintext
# Base setup
COPY /bin/bash /bin/
COPY /lib/x86_64-linux-gnu /lib/
COPY /lib64/* /lib64/
COPY /usr/bin /usr/bin/
COPY /usr/lib /usr/lib/

# Device nodes
MKDEV /dev/null c 1 3
MKDEV /dev/tty c 5 0
MKDEV /dev/zero c 1 5
MKDEV /dev/random c 1 8

# Additional setup
RUN apt-get update
RUN apt-get install -y curl
```

## License

Chrooter is licensed under the GPL-3.0 License. See the [LICENSE](LICENSE) file for details.
