# ASL Troubleshooting Guide

This guide covers common issues and solutions for ASL (Android Subsystem for Linux).

---

## 🔴 Critical Issues

### Issue: "Permission denied" / "su command not found"

**Symptom**: `asl doctor` shows "FAIL: su grants root access"

**Causes & Solutions**:

1. **Root access not granted**
   ```bash
   su -c "id"  # Test if root works
   ```
   - Grant Superuser permission in your root manager (Magisk/KernelSU/APatch)
   - Restart Termux after granting permission

2. **su binary not in PATH**
   ```bash
   which su
   echo $PATH
   ```
   - Reinstall root manager or run: `pkg install tsu` (Termux Superuser)

3. **SELinux blocking execution**
   ```bash
   su -c "getenforce"
   ```
   - Set SELinux to permissive (requires root manager settings)

---

### Issue: Chroot Won't Start / "Mount Failed"

**Symptom**: `asl start` shows error or hangs

**Diagnostic Steps**:

```bash
# Step 1: Check system state
asl doctor

# Step 2: Verify rootfs exists
ls -la /data/local/tmp/chrootDebian/

# Step 3: Check mount points
mount | grep chrootDebian

# Step 4: Check disk space
df -h /data/local/tmp/

# Step 5: Force unmount any stuck mounts
su -c "umount -l /data/local/tmp/chrootDebian"
```

**Common Fixes**:

| Error | Solution |
|-------|----------|
| "No such file or directory" | Reinstall: `asl install` |
| "Device or resource busy" | Force unmount: `su -c "umount -l /data/local/tmp/chrootDebian"` |
| "Read-only file system" | Reboot device or check storage errors |
| "Mount timeout" | Try: `asl start --timeout 60` |

---

### Issue: Debian Rootfs Missing / Corrupted

**Symptom**: `asl doctor` shows "FAIL: /data/local/tmp/chrootDebian is missing"

**Solution**:

```bash
# Option 1: Reinstall cleanly
asl install

# Option 2: Use snapshot restore
asl snapshot list      # Check if snapshot exists
asl snapshot restore <snapshot-name>

# Option 3: From backup
asl backup list
asl backup restore <backup-name>

# Option 4: Clean and reinstall
rm -rf /data/local/tmp/chrootDebian /data/local/tmp/.asl-snapshots/
asl install
```

---

## 🟠 Medium Priority Issues

### Issue: High CPU/Memory Usage

**Symptom**: Device heats up, battery drains quickly

**Diagnosis**:

```bash
# Real-time process monitor
asl ps

# Check running services
asl shell
ps aux | grep -E "Xvfb|box64|wine"

# Monitor thermal
asl thermal
```

**Solutions**:

1. **Stop unused services**
   ```bash
   # Stop desktop if not using
   asl desktop stop
   
   # Kill background processes
   asl ps -k <pid>
   
   # Or force stop chroot
   asl stop --force
   ```

2. **Optimize system**
   ```bash
   asl boost          # Run optimization script
   asl mode balanced  # Set balanced performance mode
   ```

3. **Reduce background apps** (Android side)
   ```bash
   asl shell
   # Then in chroot:
   pkill -f chrome    # Stop resource-hungry apps
   ```

---

### Issue: No Sound / Audio Not Working

**Symptom**: Apps launch but no audio output

**Diagnostic**:

```bash
# Check if PulseAudio is running
asl doctor | grep pulseaudio

# Check audio device
asl shell
pacmd list-sinks

# Test audio
speaker-test -c 2 -t sine -f 1000
```

**Solutions**:

1. **Restart audio**
   ```bash
   asl desktop stop   # This stops audio too
   asl audio start
   ```

2. **Reinstall PulseAudio**
   ```bash
   asl shell
   apt-get remove --purge pulseaudio
   apt-get install pulseaudio
   ```

3. **Check Android permissions**
   - Go to Settings → Apps → Termux → Permissions → Audio
   - Enable microphone and audio recording

---

### Issue: Desktop (XFCE) Won't Launch

**Symptom**: `asl desktop start` fails or X11 doesn't appear

**Checks**:

```bash
# 1. Verify Termux:X11 is installed
asl doctor | grep termux-x11

# 2. Test X11 manually
export DISPLAY=:0
xclock

# 3. Check Xwayland/Xvfb process
ps aux | grep -i x11

# 4. Check environment
env | grep DISPLAY
```

**Fixes**:

1. **Install Termux:X11**
   ```bash
   pkg install termux-x11
   # Then launch Termux:X11 app from home screen
   ```

2. **Restart X11 server**
   ```bash
   killall -9 Xwayland  # or Xvfb
   asl desktop start
   ```

3. **Reset session**
   ```bash
   rm -rf ~/.local/state/asl/desktop/state
   asl desktop start
   ```

---

### Issue: Games Running Slowly / Low FPS

**Symptom**: Game graphics lag, stuttering, or low frame rate

**Performance Checks**:

```bash
# Check GPU
asl overview | grep GPU

# Test graphics performance
asl shell
vkcube              # Vulkan benchmark
glxgears            # OpenGL benchmark
gputest             # GPU stress test
```

**Optimization Steps**:

1. **Enable game mode**
   ```bash
   asl mode gaming
   asl boost          # Run optimizer
   ```

2. **Check GPU driver** (if not Turnip)
   ```bash
   export ASL_GPU=turnip
   asl shell
   vulkaninfo | grep "GPU"
   ```

3. **Reduce quality settings**
   ```bash
   # In game settings:
   - Resolution: Lower (1280x720 or 1024x768)
   - Texture quality: Medium
   - Anti-aliasing: Disable or 2x
   - Shadow quality: Low
   ```

4. **Close background apps** (Android side)
   ```bash
   asl boost  # This kills non-essential Android apps
   ```

---

## 🟡 Low Priority Issues

### Issue: Snapshot Restore Failed

**Symptom**: `asl snapshot restore` shows error

**Solution**:

```bash
# 1. Verify snapshot exists
asl snapshot list

# 2. Check disk space (need 2x rootfs size)
df -h /data/local/tmp/

# 3. Try manual restore
su -c "
cd /data/local/tmp
mv chrootDebian chrootDebian.bak
cp -a .asl-snapshots/<snapshot-name> chrootDebian
"

# 4. If failed, rollback
su -c "
rm -rf /data/local/tmp/chrootDebian
mv chrootDebian.bak chrootDebian
"
```

---

### Issue: Clipboard Sync Not Working

**Symptom**: `asl clip` doesn't sync between Android and Linux

**Solution**:

```bash
# 1. Install clipboard tool in chroot
asl shell
apt-get install xclip xsel

# 2. Test manual sync
# Copy in Android
asl clip paste              # This should show Android clipboard

# Copy in Linux
echo "test" | xclip -selection clipboard
asl clip copy               # This should copy to Android

# 3. Check permissions
asl shell
cat /sdcard/some_file       # If fails, storage permissions issue
```

---

### Issue: Storage Permissions

**Symptom**: Can't access `/sdcard/` files from chroot

**Solution**:

```bash
# 1. Grant Termux storage permission (Android Settings)
# Settings → Apps → Termux → Permissions → Storage

# 2. Restart Termux

# 3. Test access
asl shell
ls -la /sdcard/

# 4. Fix ownership if needed
su -c "
export DEBIANPATH=/data/local/tmp/chrootDebian
mount --bind /sdcard $DEBIANPATH/sdcard
chroot $DEBIANPATH chown -R 0:0 /sdcard
"
```

---

### Issue: Wine Prefix Broken

**Symptom**: Wine games crash or won't launch

**Solution**:

```bash
# 1. Backup current prefix
cp -r ~/.wine ~/.wine.backup

# 2. Reset Wine
asl shell
rm -rf ~/.wine
wineboot --init

# 3. Reinstall prerequisites
winetricks vcrun2019
winetricks d3dx9
winetricks d3dcompiler_43

# 4. Restore from backup if needed
rm -rf ~/.wine
cp -r ~/.wine.backup ~/.wine
```

---

## 🔵 Diagnostic Commands

Quick reference for troubleshooting:

```bash
# System diagnostics
asl doctor              # Complete health check
asl overview            # System stats overview
asl thermal             # Thermal & battery
asl ps                  # Process list

# Logging
asl log                 # View system logs
journalctl -u asl-*     # Systemd logs
tail -f ~/.local/state/asl/debug.log

# Force operations
asl start --force       # Force mount even if stuck
asl stop --force        # Force unmount
asl doctor --verbose    # Detailed diagnostics

# Manual chroot operations
su -c "chroot /data/local/tmp/chrootDebian /bin/bash"
su -c "mount | grep chrootDebian"
su -c "lsof /data/local/tmp/chrootDebian"  # Find processes using chroot
```

---

## 📞 Getting Help

If you can't find a solution:

1. **Check logs**
   ```bash
   asl log --tail 50
   ```

2. **Report the issue**
   - Go to: https://github.com/Ruusian5/ASL/issues
   - Include: `asl doctor` output, error message, and steps to reproduce

3. **Provide debug info**
   ```bash
   asl doctor --verbose
   uname -a
   cat /proc/cpuinfo
   ```

---

**Still stuck?** Check [GETTING_STARTED.md](GETTING_STARTED.md) or reach out to the community! 💬
