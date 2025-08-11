#!/bin/bash

# Define the install directory and the alias name
INSTALL_DIR="/usr/local/bin"
ALIAS_NAME="chrooter"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Remove the chrooter binary
if [ -f "$INSTALL_DIR/$ALIAS_NAME" ]; then
    rm "$INSTALL_DIR/$ALIAS_NAME"
    echo "$ALIAS_NAME has been uninstalled."
else
    echo "$ALIAS_NAME is not installed."
fi
