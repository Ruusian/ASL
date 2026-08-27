#!/bin/bash
# Android Subsystem for Linux (ASL): Safe Chroot Mount Script
# ZERO host system/vendor/apex mounts to protect Android OS stability

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" = "/" ] || [ "${ASL_EXEC_MODE:-}" = "direct" ]; then
    echo "[✓] Already running inside container environment."
    exit 0
fi

if [ ! -d "$DEBIANPATH" ]; then
    echo "[!] Error: Debian chroot rootfs not found at $DEBIANPATH"
    echo "    To install a Debian rootfs, run: asl install"
    echo "    💡 Note: ASL runs as a native root chroot environment (Magisk / KernelSU / APatch required)."
    exit 1
fi

TERMUX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"

echo "[*] Mounting Linux chroot environment at $DEBIANPATH..."

asl_exec "
    set -e

    cleanup_on_error() {
        echo '[!] Mount error encountered; rolling back partial mounts...' >&2
        for m in \"$DEBIANPATH/proc/sys/fs/binfmt_misc\" \"$DEBIANPATH/dev/pts\" \"$DEBIANPATH/proc\" \"$DEBIANPATH/sys\" \"$DEBIANPATH/dev/shm\" \"$DEBIANPATH/run\" \"$DEBIANPATH/var/lock\" \"$DEBIANPATH/tmp\" \"$DEBIANPATH/data/data/com.termux\" \"$DEBIANPATH/storage/emulated/0\" \"$DEBIANPATH/sdcard\" \"$DEBIANPATH/dev\" \"$DEBIANPATH\"; do
            grep -q -F \" \$m \" /proc/mounts 2>/dev/null && umount -l \"\$m\" 2>/dev/null || true
        done
    }
    trap cleanup_on_error ERR

    is_mounted() {
        local target
        target=\$(readlink -f \"\$1\" 2>/dev/null || echo \"\$1\")
        awk -v t=\"\$target\" '\$2 == t { found=1; exit } END { exit !found }' /proc/mounts 2>/dev/null
    }

    domount_bind() {
        if ! is_mounted \"\$2\"; then
            mkdir -p \"\$2\"
            mount --bind \"\$1\" \"\$2\"
            mount --make-rslave \"\$2\" 2>/dev/null || true
        fi
    }

    domount_fs() {
        if ! is_mounted \"\$2\"; then
            mkdir -p \"\$2\"
            mount -t \"\$1\" \"\$1\" \"\$2\"
        fi
    }

    domount_tmpfs() {
        if ! is_mounted \"\$1\"; then
            mkdir -p \"\$1\"
            mount -t tmpfs -o \"\$2\" tmpfs \"\$1\"
        fi
    }

    if ! is_mounted \"$DEBIANPATH/dev\" || [ ! -c \"$DEBIANPATH/dev/null\" ]; then
        umount -l \"$DEBIANPATH/dev/pts\" \"$DEBIANPATH/dev/shm\" \"$DEBIANPATH/dev\" 2>/dev/null || true
        mkdir -p \"$DEBIANPATH/dev\"
        mount --bind /dev \"$DEBIANPATH/dev\"
        mount --make-rslave \"$DEBIANPATH/dev\" 2>/dev/null || true
    fi
    chmod 666 /dev/null /dev/zero /dev/urandom /dev/random /dev/full 2>/dev/null || true
    chmod 666 \"$DEBIANPATH/dev/null\" \"$DEBIANPATH/dev/zero\" \"$DEBIANPATH/dev/urandom\" \"$DEBIANPATH/dev/random\" \"$DEBIANPATH/dev/full\" 2>/dev/null || true
    # Android's graphics group (GID 1003) owns /dev/input nodes; grant that
    # group rw access for the chroot instead of making devices world-writable
    # (0666 lets any host or chroot process inject input events). Original
    # ownership/modes are recorded so stop-chroot.sh can restore them.
    INPUT_PERMS_BACKUP=\"$DEBIANPATH/.asl_input_perms\"
    : > \"\$INPUT_PERMS_BACKUP\"
    chmod 600 \"\$INPUT_PERMS_BACKUP\" 2>/dev/null || true
    for dev in /dev/input/event* /dev/input/js* /dev/input/mouse* /dev/input/mice; do
        [ -e \"\$dev\" ] || continue
        printf '%s %s %s\\n' \"\$dev\" \"\$(stat -c '%u:%g' \"\$dev\" 2>/dev/null)\" \"\$(stat -c '%a' \"\$dev\" 2>/dev/null)\" >> \"\$INPUT_PERMS_BACKUP\"
        chgrp 1003 \"\$dev\" 2>/dev/null || true
        chmod 0660 \"\$dev\" 2>/dev/null || true
    done
    domount_fs proc \"$DEBIANPATH/proc\"
    domount_fs sysfs \"$DEBIANPATH/sys\"
    domount_bind /dev/pts \"$DEBIANPATH/dev/pts\"
    chmod 666 \"$DEBIANPATH/dev/pts/ptmx\" 2>/dev/null || true
    chmod 666 \"$DEBIANPATH/dev/ptmx\" 2>/dev/null || true

    if [ -d /proc/sys/fs/binfmt_misc ] && grep -q -w \"/proc/sys/fs/binfmt_misc\" /proc/mounts 2>/dev/null; then
        domount_bind /proc/sys/fs/binfmt_misc \"$DEBIANPATH/proc/sys/fs/binfmt_misc\"
    fi

    if [ "${ASL_MOUNT_SDCARD:-1}" = "1" ] && [ -d /sdcard ]; then
        domount_bind /sdcard \"$DEBIANPATH/sdcard\"
        domount_bind /sdcard \"$DEBIANPATH/storage/emulated/0\"
    fi

    if [ -d /data/data/com.termux ]; then
        domount_bind /data/data/com.termux \"$DEBIANPATH/data/data/com.termux\"
        ln -sfn /data/data/com.termux \"$DEBIANPATH/termux\" 2>/dev/null || true
        ln -sfn /data/data/com.termux/files/home \"$DEBIANPATH/termux-home\" 2>/dev/null || true
    fi

    mkdir -p \"$TERMUX_TMP\"
    chmod 1777 \"$TERMUX_TMP\"
    domount_bind \"$TERMUX_TMP\" \"$DEBIANPATH/tmp\"
    domount_bind \"$TERMUX_TMP\" \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
    domount_tmpfs \"$DEBIANPATH/run\" rw,nosuid,nodev,mode=0755,noatime
    domount_tmpfs \"$DEBIANPATH/dev/shm\" rw,nosuid,nodev,noatime,mode=1777,size=2G

    if [ -d \"$DEBIANPATH/var\" ] && [ ! -L \"$DEBIANPATH/var/lock\" ]; then
        domount_tmpfs \"$DEBIANPATH/var/lock\" rw,nosuid,nodev,mode=1777,noatime
    fi

    # Dynamic DNS synchronization: pull active network nameservers from Android properties & Termux
    mkdir -p \"$DEBIANPATH/etc\"
    {
        for prop in net.dns1 net.dns2 net.dns3 net.dns4 net.wlan0.dns1 net.wlan0.dns2 net.rmnet_data0.dns1 net.rmnet_data0.dns2 net.rmnet_data1.dns1 net.rmnet_data1.dns2 net.eth0.dns1; do
            val=\$(getprop \"\$prop\" 2>/dev/null || true)
            if [ -n \"\$val\" ] && [[ \"\$val\" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$|^[0-9a-fA-F:]+$ ]]; then
                printf 'nameserver %s\n' \"\$val\"
            fi
        done
        if [ -f /data/data/com.termux/files/usr/etc/resolv.conf ]; then
            grep '^nameserver' /data/data/com.termux/files/usr/etc/resolv.conf 2>/dev/null || true
        fi
        printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n'
    } | awk '!seen[\$0]++' | head -n 4 > \"$DEBIANPATH/etc/resolv.conf\"
    chmod 644 \"$DEBIANPATH/etc/resolv.conf\" 2>/dev/null || true

    # Ensure D-Bus and system machine-id are provisioned
    mkdir -p \"$DEBIANPATH/var/lib/dbus\" \"$DEBIANPATH/etc\" 2>/dev/null || true
    if [ ! -s \"$DEBIANPATH/etc/machine-id\" ]; then
        if chroot \"$DEBIANPATH\" /usr/bin/test -x /usr/bin/dbus-uuidgen 2>/dev/null; then
            chroot \"$DEBIANPATH\" /usr/bin/dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null || true
        else
            od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' > \"$DEBIANPATH/etc/machine-id\" 2>/dev/null || true
        fi
    fi
    if [ -s \"$DEBIANPATH/etc/machine-id\" ] && [ ! -s \"$DEBIANPATH/var/lib/dbus/machine-id\" ]; then
        cp -f \"$DEBIANPATH/etc/machine-id\" \"$DEBIANPATH/var/lib/dbus/machine-id\" 2>/dev/null || true
    fi

    # Ensure chroot profile/bashrc unsets host Termux environment variables and caps FD limits
    for rc in \"$DEBIANPATH/etc/bash.bashrc\" \"$DEBIANPATH/etc/profile\"; do
        if [ -f \"\$rc\" ] && ! grep -q \"ASL Environment Isolation\" \"\$rc\" 2>/dev/null; then
            printf '\n# ASL Environment Isolation\nunset PREFIX TERMUX_VERSION TERMUX_APP_PID TERMUX_MAIN_PACKAGE_NAME TERMUX__PREFIX TERMUX__HOME TERMUX__ROOTFS_DIR TMPDIR\nulimit -n 2048 2>/dev/null || true\n' >> \"\$rc\" 2>/dev/null || true
        fi
    done

    # Provision kernel close_range workaround shim to prevent Android kernel 4.14 close_range spin locks in Python 3.13 / glibc
    mkdir -p \"$DEBIANPATH/usr/local/lib\" \"$DEBIANPATH/etc\" 2>/dev/null || true
    if [ ! -f \"$DEBIANPATH/usr/local/lib/libdisable_close_range.so\" ]; then
        local cc_cmd
        cc_cmd=\$(chroot \"$DEBIANPATH\" /bin/sh -c 'command -v gcc || command -v clang || command -v cc' 2>/dev/null || true)
        if [ -n \"\$cc_cmd\" ]; then
            cat <<'EOFCR' > \"$DEBIANPATH/tmp/libdisable_close_range.c\"
#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>
#include <stdarg.h>
#include <dlfcn.h>

#ifndef __NR_close_range
#define __NR_close_range 436
#endif

typedef long (*syscall_fn_t)(long number, ...);
static syscall_fn_t real_syscall = NULL;

int close_range(unsigned int first, unsigned int last, int flags) {
    if (last > 2048) last = 2048;
    if (!real_syscall) {
        real_syscall = (syscall_fn_t)dlsym(RTLD_NEXT, "syscall");
    }
    if (real_syscall) {
        return (int)real_syscall(__NR_close_range, (long)first, (long)last, (long)flags);
    }
    return 0;
}

void closefrom(int lowfd) {
    close_range(lowfd, 2048, 0);
}

long syscall(long number, ...) {
    if (!real_syscall) {
        real_syscall = (syscall_fn_t)dlsym(RTLD_NEXT, "syscall");
    }
    va_list args;
    va_start(args, number);
    long a0 = va_arg(args, long);
    long a1 = va_arg(args, long);
    long a2 = va_arg(args, long);
    long a3 = va_arg(args, long);
    long a4 = va_arg(args, long);
    long a5 = va_arg(args, long);
    va_end(args);

    if (number == __NR_close_range) {
        if ((unsigned long)a1 > 2048) a1 = 2048;
    }

    if (real_syscall) {
        return real_syscall(number, a0, a1, a2, a3, a4, a5);
    }
    return 0;
}
EOFCR
            chroot \"$DEBIANPATH\" \"\$cc_cmd\" -shared -fPIC -O2 /tmp/libdisable_close_range.c -o /usr/local/lib/libdisable_close_range.so -ldl 2>/dev/null || true
            rm -f \"$DEBIANPATH/tmp/libdisable_close_range.c\" 2>/dev/null || true
        fi
    fi
    if [ -f \"$DEBIANPATH/usr/local/lib/libdisable_close_range.so\" ]; then
        if ! grep -q \"libdisable_close_range.so\" \"$DEBIANPATH/etc/ld.so.preload\" 2>/dev/null; then
            echo \"/usr/local/lib/libdisable_close_range.so\" >> \"$DEBIANPATH/etc/ld.so.preload\" 2>/dev/null || true
        fi
    fi

    # Provision Python 3 sitecustomize & .pth optimizer to prevent close_range / POSIX_SPAWN_CLOSEFROM spinlocks on Kernel 4.14
    mkdir -p \"$DEBIANPATH/usr/lib/python3/dist-packages\" 2>/dev/null || true
    cat <<'EOFPY' > \"$DEBIANPATH/usr/lib/python3/dist-packages/asl_optimizer.py\"
# ASL Platform Optimizer for Linux Kernel 4.14
import os, sys

try:
    import subprocess
    subprocess._HAVE_POSIX_SPAWN_CLOSEFROM = False
    subprocess._USE_POSIX_SPAWN = False
except Exception:
    pass

try:
    import resource
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    if soft > 2048:
        resource.setrlimit(resource.RLIMIT_NOFILE, (2048, hard))
except Exception:
    pass
EOFPY
    echo 'import asl_optimizer' > \"$DEBIANPATH/usr/lib/python3/dist-packages/asl_optimizer.pth\" 2>/dev/null || true
    chmod 644 \"$DEBIANPATH/usr/lib/python3/dist-packages/asl_optimizer.py\" \"$DEBIANPATH/usr/lib/python3/dist-packages/asl_optimizer.pth\" 2>/dev/null || true
    for pydir in \"$DEBIANPATH\"/usr/local/lib/python3*/dist-packages \"$DEBIANPATH\"/usr/lib/python3*/dist-packages; do
        if [ -d \"\$pydir\" ]; then
            cp -f \"$DEBIANPATH/usr/lib/python3/dist-packages/asl_optimizer.py\" \"\$pydir/asl_optimizer.py\" 2>/dev/null || true
            cp -f \"$DEBIANPATH/usr/lib/python3/dist-packages/asl_optimizer.pth\" \"\$pydir/asl_optimizer.pth\" 2>/dev/null || true
            chmod 644 \"\$pydir/asl_optimizer.py\" \"\$pydir/asl_optimizer.pth\" 2>/dev/null || true
        fi
    done
    for sc in \"$DEBIANPATH\"/usr/lib/python3*/sitecustomize.py; do
        if [ -f \"\$sc\" ] && ! grep -q \"asl_optimizer\" \"\$sc\" 2>/dev/null; then
            printf '\ntry:\n    import asl_optimizer\nexcept Exception:\n    pass\n' >> \"\$sc\" 2>/dev/null || true
        fi
    done

    # Create pkg -> apt compatibility shim inside Debian chroot for third-party scripts
    mkdir -p \"$DEBIANPATH/usr/local/bin\" \"$DEBIANPATH/usr/bin\" \"$DEBIANPATH/bin\" 2>/dev/null || true
    cat <<'EOFSHIM' > \"$DEBIANPATH/usr/local/bin/pkg\"
#!/bin/bash
# ASL Debian chroot compatibility shim for Termux 'pkg' commands

translate_pkgs() {
    local args=()
    for arg in \"\$@\"; do
        case \"\$arg\" in
            python|python3) args+=(\"python3\" \"python3-pip\" \"python3-venv\" \"python-is-python3\") ;;
            python-pip) args+=(\"python3-pip\") ;;
            libffi) args+=(\"libffi-dev\") ;;
            openssl) args+=(\"libssl-dev\" \"openssl\") ;;
            clang|gcc) args+=(\"build-essential\" \"clang\") ;;
            rust) args+=(\"rustc\" \"cargo\") ;;
            pkg-config) args+=(\"pkg-config\") ;;
            ca-certificates) args+=(\"ca-certificates\") ;;
            *) args+=(\"\$arg\") ;;
        esac
    done
    echo \"\${args[@]}\"
}

if [ \"\$1\" = \"install\" ] || [ \"\$1\" = \"in\" ]; then
    shift
    pkgs=\$(translate_pkgs \"\$@\")
    apt-get update && exec apt-get install -y \$pkgs
elif [ \"\$1\" = \"upgrade\" ] || [ \"\$1\" = \"up\" ]; then
    shift
    apt-get update && exec apt-get dist-upgrade -y \"\$@\"
elif [ \"\$1\" = \"show\" ] || [ \"\$1\" = \"info\" ]; then
    shift
    exec apt-cache show \"\$@\"
elif [ \"\$1\" = \"search\" ]; then
    shift
    exec apt-cache search \"\$@\"
elif [ \"\$1\" = \"uninstall\" ] || [ \"\$1\" = \"remove\" ]; then
    shift
    exec apt-get remove -y \"\$@\"
elif [ \"\$1\" = \"list-installed\" ]; then
    shift
    exec dpkg -l \"\$@\"
elif [ \"\$1\" = \"reinstall\" ]; then
    shift
    pkgs=\$(translate_pkgs \"\$@\")
    apt-get update && exec apt-get install --reinstall -y \$pkgs
elif [ \"\$1\" = \"clean\" ]; then
    exec apt-get clean
else
    exec apt-get \"\$@\"
fi
EOFSHIM
    chmod +x \"$DEBIANPATH/usr/local/bin/pkg\" 2>/dev/null || true
    cp -f \"$DEBIANPATH/usr/local/bin/pkg\" \"$DEBIANPATH/usr/bin/pkg\" 2>/dev/null || true
    chmod +x \"$DEBIANPATH/usr/bin/pkg\" 2>/dev/null || true
    cp -f \"$DEBIANPATH/usr/local/bin/pkg\" \"$DEBIANPATH/bin/pkg\" 2>/dev/null || true
    chmod +x \"$DEBIANPATH/bin/pkg\" 2>/dev/null || true

    trap - ERR
" || {
    echo "[!] Chroot mount failed during initialization."
    echo "    Troubleshooting:"
    echo "    - Verify Debian rootfs exists: ls -la $DEBIANPATH"
    echo "    - Check root access: su -c id"
    echo "    - View error logs: dmesg | tail -20"
    echo "    💡 Hint: Ensure your device is rooted and Termux is granted Superuser access in Magisk / KernelSU / APatch."
    exit 1
}

if ! is_mounted "$DEBIANPATH/proc"; then
    echo "[!] Chroot mount verification failed - /proc not mounted."
    echo "    Verify: grep $DEBIANPATH /proc/mounts"
    exit 1
fi

# Ensure 5GB virtual swap pool is active
if [ -f "$SCRIPT_DIR/core/swap-manager.sh" ]; then
    bash "$SCRIPT_DIR/core/swap-manager.sh" setup >/dev/null 2>&1 || true
fi

echo "[✓] Chroot mounted successfully."
