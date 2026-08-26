# ASL Performance & Audio Tuning Guide

## 1. System Performance & CPU Governor Profiles (`asl mode` / `asl turbo`)
ASL provides system and CPU governor tuning for high performance workloads:

1. **CPU Governor Tuning:** Switches all available CPU cores (`/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`) to `performance` mode.
2. **Android OOM Score Protection:** Adjusts `oom_score_adj` to `-1000` for Termux, PulseAudio, SSH, XFCE4, and D-Bus processes to prevent Android's Out-Of-Memory killer from terminating session components.
3. **Memory Compaction & Caching:** Drops page caches (`drop_caches=3`), compacts Linux memory pool, and sets `vm.swappiness=10`.

### Applying Performance Modes
```bash
# Set GPU/Turbo performance profile (CPU governor set to performance)
asl turbo
# or
asl mode gpu

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

## 4. Turnip / Zink GPU Hardware Acceleration Profiles (`asl gpu`)
ASL provides hardware-accelerated Vulkan and OpenGL via Qualcomm Turnip and Mesa Zink.

```bash
# Auto-detect GPU hardware and apply acceleration profile
asl gpu apply

# Inspect detected GPU hardware and active Vulkan ICD
asl gpu profile
```

