# Chrooter Testing Guide

## Test Results Summary

### ✅ Working Features
- Environment creation: `sudo chrooter create <name>`
- Environment listing: `sudo chrooter ps`
- Building from Chrootfile: `sudo chrooter build <name> <file>`
- Running commands: `sudo chrooter run <name> <command>`
- Environment removal: `sudo chrooter rm <name>`

### ✅ Security Features Confirmed
- Path traversal protection: Blocks `../../` attempts in COPY commands
- Input validation: Rejects invalid environment names
- Error handling: Proper messages for nonexistent environments

### ❌ Known Issues (Fixed in this release)
- Exit error: "unbound variable" when exiting chroot environment

## Basic Test Sequence
```bash
# Test basic functionality
sudo chrooter create test-env
sudo chrooter ps
sudo chrooter start test-env  # Type 'exit' to test
sudo chrooter rm test-env

# Test complex build
sudo chrooter build complex-test ComplexChrootfile
sudo chrooter run complex-test /bin/cat /tmp/test_result
sudo chrooter rm complex-test

# Test security (should fail safely)
sudo chrooter build malicious-test MaliciousChrootfile
sudo chrooter create ""
sudo chrooter create "test/../../../bad"
sudo chrooter start nonexistent
```

## Platform Tested
- Raspberry Pi 3 Model B V1.2
- Raspberry Pi OS Lite (Debian GNU/Linux 11)
- Architecture: armv7l
