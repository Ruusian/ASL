# ASL Performance & Audio Tuning Guide

## 1. System Performance Booster (`asl boost` / `asl-boost`)
The `asl-boost` script executes kernel-level optimizations before launching intensive games:

1. **Android Background App Termination:** Kills non-essential memory-heavy background Android packages (VPNs, streaming tools, YouTube mods) to free RAM and CPU cycles.
2. **CPU Governor Tuning:** Switches all available CPU cores (`/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`) to `performance` mode.
3. **Android OOM Score Protection:** Adjusts `oom_score_adj` to `-1000` for Termux, Termux-X11, PulseAudio, and Debian GUI processes to prevent Android's Out-Of-Memory killer from terminating session components.
4. **Memory Compaction:** Flushes kernel page cache (`drop_caches=3`), compacts Linux memory pool (`compact_memory=1`), and sets `vm.swappiness=10`.

### Running Performance Boost
```bash
asl boost
```

---

## 2. PulseAudio Low-Latency Configuration
Audio in ASL runs via Termux PulseAudio over TCP local loopback (`127.0.0.1:4713`).

### Environment Variables
- `PULSE_SERVER=127.0.0.1`
- `PULSE_LATENCY_MSEC=60` (Reduces audio buffer delay while avoiding stuttering)
- `PULSE_AUDIO_PROP_media_role="game"`

### Troubleshooting Stuttering Audio
If audio crackles under high CPU load, adjust `PULSE_LATENCY_MSEC` in `/usr/local/bin/asl-wine-launch`:
```bash
export PULSE_LATENCY_MSEC=80
```

---

## 3. Box64 Dynarec Tuning Profiles
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

### Default Optimized Profile (`/root/.config/asl/perf_profile.env` / `/data/local/tmp/asl_dynarec_precision`)
```bash
export BOX64_DYNAREC=1
export BOX64_DYNAREC_FASTNAN=1
export BOX64_DYNAREC_FASTROUND=1
export BOX64_DYNAREC_X87DOUBLE=0
export BOX64_ALLOW_MISSING_LIBS=1
export BOX64_NOBANNER=1
```

### Compatibility Mode (For crash-prone games)
If a game crashes due to floating-point calculations or strict NaN requirements:
Run `asl game precision safe` or select option `7` in `asl-gaming-hub`.
