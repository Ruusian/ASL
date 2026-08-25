# ASL Performance & Audio Tuning Guide

## 1. System Performance & CPU Governor Profiles (`asl mode`)
ASL provides system and CPU governor tuning for low-latency gaming and compilation workloads:

1. **CPU Governor Tuning:** Switches all available CPU cores (`/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`) to `performance` mode.
2. **Android OOM Score Protection:** Adjusts `oom_score_adj` to `-1000` for Termux, PulseAudio, Box64, and SSH processes to prevent Android's Out-Of-Memory killer from terminating session components.
3. **Memory Compaction & Caching:** Drops page caches (`drop_caches=3`), compacts Linux memory pool, and sets `vm.swappiness=10`.

### Applying Performance Modes
```bash
# Set gaming performance profile (CPU governor set to performance)
asl mode gaming

# Revert to balanced profile (schedutil / powersave)
asl mode balanced

# Query active profile
asl mode status
```

---

## 2. Virtual Swap Pool & Memory Optimization (`asl swap`)
Manage virtual swap allocation and memory compaction with safety bounds capped at 5GB:

```bash
# Inspect physical RAM, zRAM, and active swap devices
asl swap status

# Set up 5GB virtual swapfile
asl swap setup 5G

# Optimize memory and drop system page caches
asl swap optimize

# Cleanup and detach swap loop devices
asl swap cleanup
```

---

## 3. PulseAudio Low-Latency Configuration
Audio in ASL runs via Termux PulseAudio over TCP local loopback (`127.0.0.1:4713`) or UNIX domain socket (`/tmp/pulse-socket`).

### Environment Variables
- `PULSE_SERVER=127.0.0.1:4713`
- `PULSE_LATENCY_MSEC=30` (Reduces audio buffer delay while avoiding stuttering)

---

## 4. Box64 Dynarec Tuning Profiles
Box64 converts x86_64 machine code to ARM64 dynamically.

### CLI Precision Profile Switcher (`asl game precision`)
Switch runtime Box64 dynarec profiles dynamically:
```bash
# Maximum FPS Profile (FASTROUND=1, FASTNAN=1, X87DOUBLE=0)
asl game precision fast

# Safe Compatibility Profile (FASTROUND=0, FASTNAN=0, X87DOUBLE=1)
asl game precision safe

# Query Active Profile Status
asl game precision status
```

### Compatibility Mode (For crash-prone applications)
If an application or game crashes due to floating-point calculations or strict IEEE-754 NaN requirements:
Run `asl game precision safe`.
