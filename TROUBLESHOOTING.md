# ASL Troubleshooting Guide

This guide covers common issues, diagnostic steps, and solutions for ASL (Android Subsystem for Linux).

---

## 🔴 Critical Issues

### Issue: "Permission denied" / "su command not found"

**Symptom**: `asl doctor` shows "FAIL: root access through su is unavailable"

**Causes & Solutions**:

1. **Root access not granted**
   ```bash
   su -c "id"  # Test if root works
   ```
   - Grant Superuser permission to Termux in your root manager (Magisk, KernelSU, or APatch).
   - Switch execution mode if device is non-rooted: `asl exec-mode shizuku` or `asl exec-mode proot`.

2. **SELinux restrictions**
   ```bash
   su -c "getenforce"
   ```
   - ASL uses strict private bind mounts (`--make-rprivate` / `--make-rslave`) to run seamlessly under SELinux Enforcing.

---

### Issue: Subsystem Won't Start / "Mount Failed"

**Symptom**: `asl start` reports error or partial mount state

**Diagnostic Steps**:

```bash
# Step 1: Run pre-flight health check
asl doctor

# Step 2: Verify rootfs directory exists
ls -la /data/local/tmp/chrootDebian/

# Step 3: Run automated self-healing repair
asl repair mounts

# Step 4: Check disk space
df -h /data/local/tmp/
```

**Common Fixes**:

| Error / State | Solution |
| :--- | :--- |
| "No such file or directory" | Reinstall or unpack rootfs: `bash install.sh` |
| "Device or resource busy" / Stale mounts | Run self-healing recovery: `asl repair mounts` |
| "Read-only file system" | Reboot device or verify Android storage permissions |
| Broken DPKG / APT locks | Recover package state: `asl repair dpkg` |

---

### Issue: Debian Rootfs Missing or Corrupted

**Symptom**: `asl doctor` shows "FAIL: /data/local/tmp/chrootDebian is missing"

**Solution**:

```bash
# Option 1: Reinstall rootfs
bash install.sh

# Option 2: Restore from point-in-time snapshot
asl snapshot list
asl snapshot restore <snapshot-name>

# Option 3: Restore from full backup archive
asl restore /sdcard/Download/asl-backup.tar.xz
```

---

## 🟠 Medium Priority Issues

### Issue: High CPU / Memory Pressure

**Symptom**: Device heats up or memory-heavy apps get killed

**Diagnosis & Solutions**:

```bash
# 1. Real-time process manager
asl ps

# 2. Thermal sensor monitor
asl thermal watch

# 3. Setup 5GB virtual swap pool
asl swap setup 5G

# 4. Run memory compaction & cache drop
asl swap optimize

# 5. Switch to balanced mode when idle
asl mode balanced
```

---

### Issue: No Sound / PulseAudio Not Responding

**Symptom**: Desktop apps or Wine games have no audio output

**Diagnostic & Solutions**:

1. **Verify PulseAudio on host**:
   ```bash
   asl doctor
   ```

2. **Restart desktop audio**:
   ```bash
   asl desktop stop
   asl desktop start
   ```

3. **Check audio connection**:
   Inside subsystem, audio routes over TCP loopback to `127.0.0.1:4713` or UNIX socket `/tmp/pulse-socket`.

---

### Issue: Desktop (XFCE4) Won't Launch on Termux:X11

**Symptom**: `asl desktop start` runs but Termux:X11 shows black screen or connection refused

**Diagnostic & Fixes**:

```bash
# 1. Verify Termux:X11 app is installed
asl doctor

# 2. Refresh Termux:X11 display socket
asl desktop refresh-x11

# 3. Stop and restart desktop session
asl desktop stop
asl desktop start
```

---

### Issue: 3D Games Stuttering or Crashing (Box64 / Wine)

**Symptom**: Game graphics lag or crash during startup

**Optimization Steps**:

1. **Switch Box64 Dynarec Profile**:
   - For maximum frame rates: `asl game precision fast`
   - For sensitive float/NaN calculations: `asl game precision safe`

2. **Verify GPU Hardware Node & Vulkan ICD**:
   ```bash
   asl doctor
   asl game benchmark
   ```

3. **Enable DXVK Async Translation**:
   ```bash
   asl dxvk enable
   ```

4. **Toggle MangoHud Telemetry Overlay**:
   ```bash
   asl hud on
   ```

---

## 🟡 Low Priority Issues

### Issue: Clipboard Synchronization Between Android and Linux

**Symptom**: Copied text in Linux doesn't appear in Android or vice versa

**Solution**:

```bash
# 1. Ensure Termux:API is installed and configured
asl clip copy "test"
asl clip paste

# 2. Start background bidirectional clipboard sync daemon
asl clip-sync start
```

---

### Issue: Storage Permissions (`/sdcard`)

**Symptom**: Cannot access files in `/sdcard/` from subsystem

**Solution**:

```bash
# 1. Trigger storage permission dialog in Termux
asl storage

# 2. Resynchronize Android AID groups (sdcard_rw, inet)
asl aid
```

---

## 🔵 System Diagnostics Reference

```bash
asl doctor              # Comprehensive environment health check
asl overview            # Live system stats & remote endpoints overview
asl thermal             # Thermal zones and battery report
asl thermal watch       # Continuous thermal monitor
asl ps                  # Interactive process manager
asl repair all          # Automated integrity repair suite
asl clean all           # Purge APT caches, /tmp, and shader caches
```

---

## 📞 Getting Help

If you encounter an issue not covered in this guide:

1. **Check pre-flight diagnostics**:
   ```bash
   asl doctor
   ```

2. **Submit a Bug Report**:
   - Go to: https://github.com/Ruusian/ASL/issues
   - Include: `asl doctor` output, device model, and reproduction steps.
