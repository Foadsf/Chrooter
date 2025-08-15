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

## Environment Consistency Tests
```bash
# Test create vs build consistency
sudo chrooter create create-test
sudo chrooter build build-test TestChrootfile

# Both should support start command
sudo chrooter start create-test  # Type 'exit' to test
sudo chrooter start build-test   # Type 'exit' to test

# Cleanup
sudo chrooter rm create-test
sudo chrooter rm build-test
```

## Locale Testing
```bash
# Verify no locale warnings appear
sudo chrooter create locale-test 2>&1 | grep -i "locale\|warning" || echo "No locale warnings - SUCCESS"
sudo chrooter start locale-test  # Should be clean output
sudo chrooter run locale-test /bin/echo "Testing locale" 2>&1 | grep -i "locale\|warning" || echo "No locale warnings - SUCCESS"
sudo chrooter rm locale-test
```

## Complex Dependencies Testing
```bash
# Test Python support
sudo chrooter build python-test WebServerChrootfile
sudo chrooter run python-test /usr/bin/python3 -c "print('Python works!')"
sudo chrooter run python-test /usr/bin/python3 -m http.server --help

# Test build utilities
sudo chrooter run python-test /bin/ls /var/www
sudo chrooter run python-test /bin/cat /var/www/index.html

# Cleanup
sudo chrooter rm python-test
```

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
