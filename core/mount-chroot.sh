#!/bin/bash
# Android Subsystem for Linux (ASL): Safe Chroot Mount Script
# ZERO host system/vendor/apex mounts to protect Android OS stability

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "${ASL_EXEC_MODE:-root}" = "proot" ]; then
    if [ -d "$DEBIANPATH" ] || [ -d "$PREFIX/var/lib/proot-distro/containers/asl-debian" ]; then
        if [ -d "$DEBIANPATH" ]; then
            mkdir -p "$DEBIANPATH/usr/local/bin" "$DEBIANPATH/usr/bin" "$DEBIANPATH/bin" 2>/dev/null || true
            cat <<'EOFSHIM' > "$DEBIANPATH/usr/local/bin/pkg"
#!/bin/bash
# ASL Debian chroot compatibility shim for Termux 'pkg' commands

translate_pkgs() {
    local args=()
    for arg in "$@"; do
        case "$arg" in
            python|python3) args+=("python3" "python3-pip" "python3-venv" "python-is-python3") ;;
            python-pip) args+=("python3-pip") ;;
            libffi) args+=("libffi-dev") ;;
            openssl) args+=("libssl-dev" "openssl") ;;
            clang|gcc) args+=("build-essential" "clang") ;;
            rust) args+=("rustc" "cargo") ;;
            pkg-config) args+=("pkg-config") ;;
            ca-certificates) args+=("ca-certificates") ;;
            *) args+=("$arg") ;;
        esac
    done
    echo "${args[@]}"
}

if [ "$1" = "install" ] || [ "$1" = "in" ]; then
    shift
    pkgs=$(translate_pkgs "$@")
    apt-get update && exec apt-get install -y $pkgs
elif [ "$1" = "upgrade" ] || [ "$1" = "up" ]; then
    shift
    apt-get update && exec apt-get dist-upgrade -y "$@"
elif [ "$1" = "show" ] || [ "$1" = "info" ]; then
    shift
    exec apt-cache show "$@"
elif [ "$1" = "search" ]; then
    shift
    exec apt-cache search "$@"
elif [ "$1" = "uninstall" ] || [ "$1" = "remove" ]; then
    shift
    exec apt-get remove -y "$@"
elif [ "$1" = "list-installed" ]; then
    shift
    exec dpkg -l "$@"
elif [ "$1" = "reinstall" ]; then
    shift
    pkgs=$(translate_pkgs "$@")
    apt-get update && exec apt-get install --reinstall -y $pkgs
elif [ "$1" = "clean" ]; then
    exec apt-get clean
else
    exec apt-get "$@"
fi
EOFSHIM
            chmod +x "$DEBIANPATH/usr/local/bin/pkg" 2>/dev/null || true
            cp -f "$DEBIANPATH/usr/local/bin/pkg" "$DEBIANPATH/usr/bin/pkg" 2>/dev/null || true
            chmod +x "$DEBIANPATH/usr/bin/pkg" 2>/dev/null || true
            cp -f "$DEBIANPATH/usr/local/bin/pkg" "$DEBIANPATH/bin/pkg" 2>/dev/null || true
            chmod +x "$DEBIANPATH/bin/pkg" 2>/dev/null || true
        fi
        echo "[✓] PRoot user-space subsystem active — environment ready at $DEBIANPATH."
        exit 0
    else
        echo "[!] Error: Subsystem rootfs not found at $DEBIANPATH"
        echo "    To install a Linux rootfs, run: asl install"
        exit 1
    fi
fi

if [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "[!] Error: Debian chroot rootfs not found at $DEBIANPATH"
    echo "    To install a Debian rootfs, run: asl install"
    echo "    Or check if proot-distro is installed: which proot-distro"
    exit 1
fi

TERMUX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"

echo "[*] Mounting Linux chroot environment at $DEBIANPATH..."

asl_exec "
    set -e

    cleanup_on_error() {
        echo '[!] Mount error encountered; rolling back partial mounts...' >&2
        for m in \"$DEBIANPATH/proc/sys/fs/binfmt_misc\" \"$DEBIANPATH/dev/pts\" \"$DEBIANPATH/proc\" \"$DEBIANPATH/sys\" \"$DEBIANPATH/dev/shm\" \"$DEBIANPATH/run\" \"$DEBIANPATH/var/lock\" \"$DEBIANPATH/tmp\" \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\" \"$DEBIANPATH/sdcard\" \"$DEBIANPATH/dev\" \"$DEBIANPATH\"; do
            grep -q -F \" \$m \" /proc/mounts 2>/dev/null && umount -l \"\$m\" 2>/dev/null || true
        done
    }
    trap cleanup_on_error ERR

    is_mounted() {
        local target
        target=\$(readlink -f \"\$1\" 2>/dev/null || echo \"\$1\")
        grep -q -F \" \$target \" /proc/mounts 2>/dev/null
    }

    if ! is_mounted \"$DEBIANPATH\"; then
        mount --bind \"$DEBIANPATH\" \"$DEBIANPATH\"
    fi
    mount --make-rprivate \"$DEBIANPATH\" 2>/dev/null || true

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

    domount_bind /dev \"$DEBIANPATH/dev\"
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

    if [ -d /sdcard ]; then
        domount_bind /sdcard \"$DEBIANPATH/sdcard\"
        mkdir -p \"$DEBIANPATH/storage/emulated/0\" 2>/dev/null || true
        if ! is_mounted \"$DEBIANPATH/storage/emulated/0\"; then
            mount --bind /sdcard \"$DEBIANPATH/storage/emulated/0\" 2>/dev/null || true
            mount --make-rslave \"$DEBIANPATH/storage/emulated/0\" 2>/dev/null || true
        fi
    fi

    mkdir -p \"$TERMUX_TMP\"
    chmod 1777 \"$TERMUX_TMP\"
    if ! is_mounted \"$DEBIANPATH/tmp\"; then
        mount --bind \"$TERMUX_TMP\" \"$DEBIANPATH/tmp\"
        mount --make-rslave \"$DEBIANPATH/tmp\" 2>/dev/null || true
    fi
    mkdir -p \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
    if ! is_mounted \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"; then
        mount --bind \"$TERMUX_TMP\" \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
        mount --make-rslave \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\" 2>/dev/null || true
    fi
    domount_tmpfs \"$DEBIANPATH/run\" rw,nosuid,nodev,mode=0755,noatime
    domount_tmpfs \"$DEBIANPATH/dev/shm\" rw,nosuid,nodev,noatime,mode=1777,size=2G

    if [ -d \"$DEBIANPATH/var\" ] && [ ! -L \"$DEBIANPATH/var/lock\" ]; then
        domount_tmpfs \"$DEBIANPATH/var/lock\" rw,nosuid,nodev,mode=1777,noatime
    fi

    if [ ! -s \"$DEBIANPATH/etc/resolv.conf\" ]; then
        mkdir -p \"$DEBIANPATH/etc\"
        dns1=\$(getprop net.dns1 2>/dev/null)
        dns2=\$(getprop net.dns2 2>/dev/null)
        if [ -n \"\$dns1\" ]; then
            printf 'nameserver %s\n' \"\$dns1\" > \"$DEBIANPATH/etc/resolv.conf\"
            [ -n \"\$dns2\" ] && printf 'nameserver %s\n' \"\$dns2\" >> \"$DEBIANPATH/etc/resolv.conf\"
        elif [ -f /data/data/com.termux/files/usr/etc/resolv.conf ]; then
            cp /data/data/com.termux/files/usr/etc/resolv.conf \"$DEBIANPATH/etc/resolv.conf\" 2>/dev/null || true
        fi
        if [ ! -s \"$DEBIANPATH/etc/resolv.conf\" ]; then
            printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > \"$DEBIANPATH/etc/resolv.conf\"
        fi
    fi

    # Ensure chroot profile/bashrc unsets host Termux environment variables
    for rc in \"$DEBIANPATH/etc/bash.bashrc\" \"$DEBIANPATH/etc/profile\"; do
        if [ -f \"\$rc\" ] && ! grep -q \"ASL Environment Isolation\" \"\$rc\" 2>/dev/null; then
            printf '\n# ASL Environment Isolation\nunset PREFIX TERMUX_VERSION TERMUX_APP_PID TERMUX_MAIN_PACKAGE_NAME TERMUX__PREFIX TERMUX__HOME TERMUX__ROOTFS_DIR TMPDIR\n' >> \"\$rc\" 2>/dev/null || true
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

echo "[✓] Chroot mounted successfully."
