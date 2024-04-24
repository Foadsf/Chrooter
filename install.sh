#!/bin/bash

# Define the install directory and the alias name
INSTALL_DIR="/usr/local/bin"
ALIAS_NAME="chrooter"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Copy chroot-manager.sh to the install directory
install -m 755 chroot-manager.sh "$INSTALL_DIR/$ALIAS_NAME"

# Check if the alias is already defined in ~/.bashrc or ~/.bash_aliases
if grep -q "alias $ALIAS_NAME=" ~/.bashrc ~/.bash_aliases 2>/dev/null; then
  echo "Alias $ALIAS_NAME is already defined in ~/.bashrc or ~/.bash_aliases."
else
  # Add the alias to ~/.bash_aliases if it exists, otherwise to ~/.bashrc
  if [ -f ~/.bash_aliases ]; then
    echo "alias $ALIAS_NAME='$INSTALL_DIR/$ALIAS_NAME'" >> ~/.bash_aliases
  else
    echo "alias $ALIAS_NAME='$INSTALL_DIR/$ALIAS_NAME'" >> ~/.bashrc
  fi
  echo "Alias $ALIAS_NAME added."
fi

# Reload the shell configuration
if [ -f ~/.bash_aliases ]; then
  source ~/.bash_aliases
else
  source ~/.bashrc
fi

echo "$ALIAS_NAME is now installed and ready to use."
