#!/bin/bash
# ASL: Gaming Layer Helper
# Wine + Box64 Status & Execution Wrapper

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi
source "$SCRIPT_DIR/core/gpu-profile.sh"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

check_emulation_available() {
    if ! asl_chroot_exec "/usr/bin/test -x /usr/bin/wine -o -x /usr/bin/wine64 -o -x /opt/wine-x64/bin/wine -o -x /opt/wine-x64/bin/wine64 -o -x /usr/bin/box64" 2>/dev/null; then
        echo "[!] Wine / Box64 emulation packages are not installed in Debian."
        echo "    x86/x64 Windows emulation is currently disabled on this system."
        return 1
    fi
    return 0
}

build_gaming_env_exports() {
    local gpu_vars snippet dyn_mode fastround=1 fastnan=1 x87double=0 esync_var="" fsync_var=""
    gpu_vars=$(asl_gpu_env_exports)

    if [ -e /proc/sys/fs/epoll ]; then
        esync_var=$'export WINEESYNC=1\n'
        fsync_var=$'export WINEFSYNC=1\n'
    fi

    dyn_mode=$(asl_exec "cat /data/local/tmp/asl_dynarec_precision 2>/dev/null" 2>/dev/null | tr -d '[:space:]')
    if [ "$dyn_mode" = "safe" ] || [ "$dyn_mode" = "accurate" ]; then
        fastround=0
        fastnan=0
        x87double=1
    fi

    snippet=$(cat << EOF
if [ -d /opt/wine-x64/bin ]; then
    export PATH=/usr/local/bin:/opt/wine-x64/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
    [ -x /opt/wine-x64/bin/wineserver-wrapper ] && export WINESERVER=/opt/wine-x64/bin/wineserver-wrapper
    [ -x /usr/local/bin/wine64 ] && export WINELOADER=/usr/local/bin/wine64
else
    export PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
fi
export DISPLAY=:0
export TMPDIR=/tmp
export WINEARCH=win64
export WINEPREFIX="\\${WINEPREFIX:-\\$([ -d /root/.wine-x64 ] && echo /root/.wine-x64 || echo /root/.wine)}"
export XDG_RUNTIME_DIR=/run/user/0
export SDL_GAMECONTROLLERCONFIG_FILE=/etc/gamecontrollerdb.txt
export SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml=d"
export WINEDEBUG=-all
${esync_var}${fsync_var}@GPU_VARS@
export PULSE_SERVER=unix:/tmp/pulse-socket,tcp:127.0.0.1
export BOX64_ALLOW_MISSING_LIBS=1
export BOX64_NOBANNER=1
export BOX64_DYNAREC=1
export BOX64_DYNAREC_FASTROUND=$fastround
export BOX64_DYNAREC_FASTNAN=$fastnan
export BOX64_DYNAREC_X87DOUBLE=$x87double
export BOX64_LD_LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:${BOX64_LD_LIBRARY_PATH:-}"
[ -f /etc/box64.apps.conf ] && export BOX64_RCFILE=/etc/box64.apps.conf
mkdir -p /run/user/0 /tmp/.mesa_cache 2>/dev/null || true
EOF
)
    printf '%s' "${snippet/@GPU_VARS@/$gpu_vars}"
}

ensure_wine_desktop_launchers() {
    local env_exports launcher_b64 setup_script script_b64
    env_exports=$(build_gaming_env_exports)
    launcher_b64=$(printf '%s\n%s\nif [ "$1" = "winetricks" ]; then\n    exec "$@"\nfi\nif [[ "$1" != "box64" ]] && command -v box64 >/dev/null 2>&1; then\n    if [ -f "$1" ] && file "$1" 2>/dev/null | grep -q "x86-64"; then\n        exec box64 "$@"\n    elif [[ "$1" == "/opt/wine-x64"* ]]; then\n        exec box64 "$@"\n    else\n        exec "$@"\n    fi\nelse\n    exec "$@"\nfi\n' "#!/bin/bash" "$env_exports" | base64 | tr -d '\n')

    setup_script=$(cat << EOF_SETUP
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
mkdir -p /usr/share/applications /root/Desktop /usr/local/bin

echo "$launcher_b64" | base64 -d > /usr/local/bin/asl-wine-launch
chmod 755 /usr/local/bin/asl-wine-launch

cat << 'EOF_ASLBIN' > /usr/local/bin/asl
#!/bin/bash
if [ "\$1" = "game" ] || [ "\$1" = "gaming" ] || [ -z "\$1" ]; then
    exec asl-wine-launch wine64 explorer
else
    exec asl-wine-launch "\$@"
fi
EOF_ASLBIN
chmod 755 /usr/local/bin/asl

cat << 'EOF_WINE64' > /usr/local/bin/wine64
#!/bin/bash
WINE_EXEC=""
if [ -x /opt/wine-x64/bin/wine64 ]; then
    WINE_EXEC=/opt/wine-x64/bin/wine64
elif [ -x /usr/lib/wine/wine64 ]; then
    WINE_EXEC=/usr/lib/wine/wine64
elif [ -x /usr/bin/wine64 ]; then
    WINE_EXEC=/usr/bin/wine64
else
    WINE_EXEC=/usr/bin/wine
fi
exec /usr/local/bin/asl-wine-launch "\$WINE_EXEC" "\$@"
EOF_WINE64
chmod 755 /usr/local/bin/wine64

cat << 'EOF_WINE' > /usr/local/bin/wine
#!/bin/bash
# Win64-only project: route plain "wine" to wine64 (ELF32 "wine" can't run under box64).
WINE_EXEC=""
if [ -x /opt/wine-x64/bin/wine64 ]; then
    WINE_EXEC=/opt/wine-x64/bin/wine64
elif [ -x /usr/lib/wine/wine64 ]; then
    WINE_EXEC=/usr/lib/wine/wine64
elif [ -x /usr/bin/wine64 ]; then
    WINE_EXEC=/usr/bin/wine64
else
    WINE_EXEC=/usr/bin/wine
fi
exec /usr/local/bin/asl-wine-launch "\$WINE_EXEC" "\$@"
EOF_WINE
chmod 755 /usr/local/bin/wine

cat << 'EOF_WINECFG_BIN' > /usr/local/bin/winecfg
#!/bin/bash
exec /usr/local/bin/asl-wine-launch winecfg "\$@"
EOF_WINECFG_BIN
chmod 755 /usr/local/bin/winecfg

cat << 'EOF_WINESERVER_BIN' > /usr/local/bin/wineserver
#!/bin/bash
WINESERVER_EXEC=""
if [ -x /opt/wine-x64/bin/wineserver ]; then
    WINESERVER_EXEC=/opt/wine-x64/bin/wineserver
elif [ -x /usr/lib/wine/wineserver64 ]; then
    WINESERVER_EXEC=/usr/lib/wine/wineserver64
elif [ -x /usr/lib/wine/wineserver ]; then
    WINESERVER_EXEC=/usr/lib/wine/wineserver
else
    WINESERVER_EXEC=/usr/bin/wineserver
fi
exec /usr/local/bin/asl-wine-launch "\$WINESERVER_EXEC" "\$@"
EOF_WINESERVER_BIN
chmod 755 /usr/local/bin/wineserver

if ! command -v winetricks >/dev/null 2>&1; then
    echo "[*] Installing winetricks script in /usr/local/bin..."
    wget -q https://raw.githubusercontent.com/Winetricks/winetricks/5a59ea07513b24093bd90fad943ecf9543cf05bc/src/winetricks -O /tmp/winetricks.tmp 2>/dev/null || curl -sSL https://raw.githubusercontent.com/Winetricks/winetricks/5a59ea07513b24093bd90fad943ecf9543cf05bc/src/winetricks -o /tmp/winetricks.tmp 2>/dev/null || true
    if [ -f /tmp/winetricks.tmp ] && [ "\$(sha256sum /tmp/winetricks.tmp 2>/dev/null | cut -d' ' -f1)" = "f35c29737ca08a583569e6a3752d52fbe23333c5acfad5f16c4177d25eaf3f4b" ]; then
        chmod +x /tmp/winetricks.tmp
        mv -f /tmp/winetricks.tmp /usr/local/bin/winetricks
    else
        rm -f /tmp/winetricks.tmp 2>/dev/null
        echo "[!] winetricks download failed SHA-256 verification; not installing"
    fi
fi

cat << 'EOF_WINEFILE' > /usr/share/applications/winefile.desktop
[Desktop Entry]
Name=Wine File Manager
Comment=Browse and manage Windows files in Wine
Exec=asl-wine-launch wine64 winefile
Icon=file-manager
Terminal=false
Type=Application
Categories=System;FileTools;Utility;Wine;
EOF_WINEFILE

cat << 'EOF_WINECFG' > /usr/share/applications/winecfg.desktop
[Desktop Entry]
Name=Wine Configuration
Comment=Configure Wine settings and drive mappings
Exec=asl-wine-launch wine64 winecfg
Icon=preferences-system
Terminal=false
Type=Application
Categories=Settings;System;Wine;
EOF_WINECFG

cat << 'EOF_EXPLORER' > /usr/share/applications/wine-explorer.desktop
[Desktop Entry]
Name=Wine Explorer Desktop
Comment=Launch Virtual Windows Explorer Desktop Container
Exec=asl-wine-launch wine64 explorer
Icon=system-file-manager
Terminal=false
Type=Application
Categories=System;Wine;
EOF_EXPLORER

cat << 'EOF_TRICKS' > /usr/share/applications/winetricks.desktop
[Desktop Entry]
Name=Winetricks
Comment=Install Windows DLLs, runtime libraries, and gaming tools
Exec=asl-wine-launch winetricks --gui
Icon=package-x-generic
Terminal=false
Type=Application
Categories=Settings;System;Wine;
EOF_TRICKS

cat << 'EOF_ASLHUB' > /usr/share/applications/asl-hub.desktop
[Desktop Entry]
Name=ASL Gaming & Host Hub
Comment=Interactive Windows Emulation and Host Applications Management Terminal
Exec=asl game
Icon=utilities-terminal
Terminal=true
Type=Application
Categories=Game;Utility;System;Wine;
EOF_ASLHUB

rm -f /usr/share/applications/asl-gaming.desktop /usr/share/applications/asl-host.desktop /root/Desktop/asl-gaming.desktop /root/Desktop/asl-host.desktop 2>/dev/null || true
cp -f /usr/share/applications/winefile.desktop /root/Desktop/ 2>/dev/null || true
cp -f /usr/share/applications/winecfg.desktop /root/Desktop/ 2>/dev/null || true
cp -f /usr/share/applications/wine-explorer.desktop /root/Desktop/ 2>/dev/null || true
cp -f /usr/share/applications/winetricks.desktop /root/Desktop/ 2>/dev/null || true
cp -f /usr/share/applications/asl-hub.desktop /root/Desktop/ 2>/dev/null || true
chmod +x /root/Desktop/*.desktop /usr/share/applications/*.desktop 2>/dev/null || true
gio trust /root/Desktop/*.desktop 2>/dev/null || true
EOF_SETUP
)

    script_b64=$(printf '%s' "$setup_script" | base64 | tr -d '\n')
    if ! asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH; echo $script_b64 | base64 -d | /bin/bash"; then
        echo "[!] Failed to create Wine desktop launchers."
        return 1
    fi
}

setup_gaming() {
    echo "[*] Initializing Gaming Environment dependencies inside Debian chroot..."
    if ! asl_chroot_exec "
        export PATH=/opt/wine-x64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
        dpkg --add-architecture i386 2>/dev/null || true
        CODENAME=\$(. /etc/os-release 2>/dev/null; printf %s \"\$VERSION_CODENAME\")
        [ -n \"\$CODENAME\" ] || CODENAME=trixie
        if [ -f /etc/debian_version ]; then
            echo \"deb http://deb.debian.org/debian \$CODENAME main contrib non-free non-free-firmware\" > /etc/apt/sources.list
        fi
        if ! apt-get update; then
            echo \"[!] apt-get update failed. Check network access inside the chroot.\"
            exit 1
        fi
        echo \"[*] Installing Wine, Box64, Winetricks, Mesa and Vulkan tooling...\"
        if ! apt-get install -y wine wine64 box64 winetricks fonts-liberation libvulkan1 vulkan-tools mesa-utils glmark2 cabextract wget unzip zenity; then
            echo \"[!] apt-get install failed.\"
            echo \"    dxvk and wine32:i386 are not packaged for Debian arm64 and were removed from the install list.\"
            echo \"    Install DXVK DLLs into the Wine prefix later via: winetricks dxvk\"
            exit 1
        fi
        cat << \"EOF_DXVK\" > /etc/dxvk.conf
dxgi.allowModeSwitch = True
dxgi.syncInterval = 0
dxgi.maxFrameRate = 0
dxgi.maxFrameLatency = 1
dxgi.tearFree = False
dxgi.deferredSurfaceCreation = False
dxgi.nvapiHack = False
d3d11.maxFeatureLevel = 11_1
d3d11.relaxedBarriers = True
dxvk.enableAsync = True
dxvk.gplPipelineCache = True
dxvk.numCompilerThreads = 4
dxvk.hud = 0
EOF_DXVK
    '"; then
        echo "[✗] Gaming environment setup FAILED. See the errors above."
        return 1
    fi
    ensure_wine_desktop_launchers || return 1
    echo "[*] Setting up Wine win64 prefix..."
    ENV_EXPORTS=$(build_gaming_env_exports)
    if ! asl_chroot_exec "$ENV_EXPORTS
        wineboot -u
    "; then
        echo "[!] Wine win64 prefix initialization failed."
        return 1
    fi
    echo "[✓] Gaming Environment setup completed."
}

run_gpu_benchmark() {
    asl_gpu_apply
    echo "=========================================="
    echo "       ASL Hardware Acceleration Benchmark"
    echo "=========================================="
    asl_gpu_report
    echo ""
    ENV_EXPORTS=$(build_gaming_env_exports)
    asl_chroot_exec "$ENV_EXPORTS
        echo \"[*] Checking OpenGL / Mesa Information (glxinfo)...\"
        if command -v glxinfo >/dev/null 2>&1; then
            glxinfo -B 2>/dev/null || echo \"glxinfo failed to connect to DISPLAY :0\"
        else
            echo \"[!] mesa-utils (glxinfo) not installed in Debian chroot.\"
        fi
        echo \"\"
        echo \"[*] Checking Vulkan Device Summary (vulkaninfo)...\"
        if command -v vulkaninfo >/dev/null 2>&1; then
            vulkaninfo --summary 2>/dev/null || echo \"vulkaninfo failed to query Vulkan ICD driver\"
        else
            echo \"[!] vulkan-tools (vulkaninfo) not installed in Debian chroot.\"
        fi
        echo \"\"
        echo \"[*] Running OpenGL Benchmark (glmark2)...\"
        if command -v glmark2 >/dev/null 2>&1; then
            glmark2 --size 800x600 || true
        else
            echo \"[!] glmark2 not installed in Debian chroot. Run asl setup-gaming to install benchmark tooling.\"
        fi
    "
}

run_desktop_shortcuts() {
    echo ""
    echo "=== Modded Debian & Host Application Shortcuts ==="
    local apps
    apps=$(asl_chroot_exec "ls /usr/share/applications/*.desktop /root/Desktop/*.desktop 2>/dev/null | sort -u" 2>/dev/null)
    if [ -z "$apps" ]; then
        echo "  [!] No .desktop launchers found in chroot."
    else
        echo "$apps" | sed 's|^.*/||' | awk '{print "  - " $0}'
        echo ""
        echo -n "Enter launcher file name (e.g. winecfg.desktop) or press Enter to cancel: "
        read -r app_name
        if [ -n "$app_name" ]; then
            echo "[*] Launching $app_name..."
            ENV_EXPORTS=$(build_gaming_env_exports)
            asl_chroot_exec "TARGET=\"$app_name\"; $ENV_EXPORTS
                if [[ \"\$TARGET\" == *.desktop ]] && [ ! -f \"\$TARGET\" ]; then
                    if [ -f \"/usr/share/applications/\$TARGET\" ]; then
                        TARGET=\"/usr/share/applications/\$TARGET\"
                    elif [ -f \"/root/Desktop/\$TARGET\" ]; then
                        TARGET=\"/root/Desktop/\$TARGET\"
                    fi
                elif [ ! -f \"\$TARGET\" ]; then
                    if [ -f \"/usr/share/applications/\${TARGET}.desktop\" ]; then
                        TARGET=\"/usr/share/applications/\${TARGET}.desktop\"
                    elif [ -f \"/root/Desktop/\${TARGET}.desktop\" ]; then
                        TARGET=\"/root/Desktop/\${TARGET}.desktop\"
                    fi
                fi

                if [ -f \"\$TARGET\" ] && [[ \"\$TARGET\" == *.desktop ]]; then
                    APP_BASE=\$(basename \"\$TARGET\" .desktop)
                    if command -v gio >/dev/null 2>&1; then
                        nohup gio launch \"\$TARGET\" >/tmp/app_launch.log 2>&1 &
                    elif command -v gtk-launch >/dev/null 2>&1; then
                        nohup gtk-launch \"\$APP_BASE\" >/tmp/app_launch.log 2>&1 &
                    else
                        EXEC_LINE=\$(grep -E '^Exec=' \"\$TARGET\" | head -n1 | cut -d'=' -f2-)
                        EXEC_CMD=\$(echo \"\$EXEC_LINE\" | sed -E 's/%[fFuUiIck]//g')
                        if [ -n \"\$EXEC_CMD\" ]; then
                            nohup /bin/bash -c \"\$EXEC_CMD\" >/tmp/app_launch.log 2>&1 &
                        fi
                    fi
                else
                    if command -v asl-wine-launch >/dev/null 2>&1; then
                        nohup asl-wine-launch \"\$TARGET\" >/tmp/app_launch.log 2>&1 &
                    else
                        nohup \"\$TARGET\" >/tmp/app_launch.log 2>&1 &
                    fi
                fi
            "
        fi
    fi
}

show_gaming_menu() {
    while true; do
        echo "=========================================="
        echo "   ASL Gaming & Host Applications Hub"
        echo "=========================================="
        if ! check_emulation_available; then
            echo "0) Auto-Install Wine / Box64 Gaming Packages"
        fi
        echo "1) Full-Screen Windows Explorer (Wine Desktop)"
        echo "2) Run Windows Executable (.exe)"
        echo "3) Graphical File Picker (Select .exe to run)"
        echo "4) Wine File Manager (winefile)"
        echo "5) Wine Configuration (winecfg)"
        echo "6) Winetricks Helper"
        echo "7) Modded Debian Shortcuts (.desktop)"
        echo "8) Openbox Virtual Desktop (Tint2 + Taskbar + PCManFM)"
        echo "9) Full XFCE4 Virtual Desktop Session"
        echo "10) Run GPU & Vulkan Benchmark (glmark2 / vulkaninfo)"
        echo "11) Exit"
        echo ""
        echo -n "Select option [1-11]: "
        read -r CHOICE
        case "$CHOICE" in
            0) setup_gaming ;;
            1) run_wine_desktop ;;
            2) run_wine_exe ;;
            3) run_gui_picker ;;
            4) run_winefile ;;
            5) run_winecfg ;;
            6) run_winetricks ;;
            7) run_desktop_shortcuts ;;
            8) run_openbox_desktop ;;
            9)
                echo "[*] Launching ASL-managed XFCE4 Desktop..."
                bash "$SCRIPT_DIR/desktop/start-desktop.sh" start
                ;;
            10) run_gpu_benchmark ;;
            11|q|exit) break ;;
            *) echo "[!] Invalid selection." ;;
        esac
        echo ""
    done
}

run_wine_desktop() {
    if ! check_emulation_available; then return 1; fi
    ensure_wine_desktop_launchers || return 1
    RES="${1:-1280x720}"
    asl_gpu_apply
    local ncpu mask
    ncpu=$(nproc 2>/dev/null || echo 8)
    mask="0-$((ncpu - 1))"
    echo "[*] Launching Full-Screen Windows Explorer Desktop..."
    ENV_EXPORTS=$(build_gaming_env_exports)
    asl_chroot_exec "$ENV_EXPORTS
        wineserver-wrapper -k 2>/dev/null || wineserver -k 2>/dev/null || true
        nohup taskset -c $mask wine64 explorer >/tmp/wine_desktop.log 2>&1 &
        sleep 1
    "
    echo "[✓] Full-Screen Windows Explorer launched on DISPLAY :0."
}

run_winefile() {
    if ! check_emulation_available; then return 1; fi
    asl_gpu_apply
    echo "[*] Opening Wine File Manager..."
    ENV_EXPORTS=$(build_gaming_env_exports)
    asl_chroot_exec "$ENV_EXPORTS wine64 winefile"
}

run_gui_picker() {
    if ! check_emulation_available; then return 1; fi
    echo "[*] Opening Graphical File Picker..."
    EXE=$(asl_chroot_exec "export DISPLAY=:0; zenity --file-selection --file-filter=\"Executable files (*.exe) | *.exe\" --title=\"Select Windows Executable\"" 2>/dev/null)
    if [ -n "$EXE" ]; then
        run_wine_exe "$EXE"
    else
        echo "[!] No valid executable selected."
    fi
}

run_openbox_desktop() {
    if ! check_emulation_available; then return 1; fi
    echo "[*] Launching Openbox + Tint2 Desktop Environment Container..."
    asl_chroot_exec "
        export DISPLAY=:0
        export PATH=/opt/wine-x64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
        nohup openbox >/tmp/openbox.log 2>&1 &
        nohup tint2 >/tmp/tint2.log 2>&1 &
        nohup pcmanfm --desktop >/tmp/pcmanfm.log 2>&1 &
    "
    echo "[✓] Openbox virtual desktop environment started on DISPLAY :0."
}

run_wine_exe() {
    if ! check_emulation_available; then
        return 1
    fi
    EXE_PATH="${1:-}"
    if [ -z "$EXE_PATH" ]; then
        echo -n "Enter full path to .exe file: "
        read -r EXE_PATH
    fi
    if [ -z "$EXE_PATH" ]; then
        echo "[!] No executable path provided."
        return 1
    fi

    local host_path="$EXE_PATH"
    if [[ "$host_path" == "$DEBIANPATH"* ]]; then
        host_path="$EXE_PATH"
    elif [ ! -e "$host_path" ] && asl_chroot_exec "test -f '$EXE_PATH'" 2>/dev/null; then
        host_path="$DEBIANPATH$EXE_PATH"
    fi

    if [ ! -e "$host_path" ]; then
        echo "[!] File not found: $EXE_PATH"
        return 1
    fi

    host_path=$(realpath "$host_path" 2>/dev/null || readlink -f "$host_path" 2>/dev/null || echo "$host_path")
    local internal_exe="$host_path"
    if [[ "$internal_exe" == "$DEBIANPATH"* ]]; then
        internal_exe="${internal_exe#$DEBIANPATH}"
    fi

    APP_NAME=$(basename "$EXE_PATH" .exe)
    SAFE_APP_NAME=$(echo "$APP_NAME" | sed 's/[^A-Za-z0-9_-]/_/g')
    [ -n "$SAFE_APP_NAME" ] || SAFE_APP_NAME="App"
    asl_gpu_apply
    local ncpu mask
    ncpu=$(nproc 2>/dev/null || echo 8)
    mask="0-$((ncpu - 1))"
    echo "[*] Executing $EXE_PATH ($APP_NAME) with Box64 + Wine64..."
    export TARGET_EXE="$internal_exe"
    export TARGET_NAME="$SAFE_APP_NAME"
    ENV_EXPORTS=$(build_gaming_env_exports)
    asl_chroot_exec "export TARGET_EXE=\"$TARGET_EXE\"; export TARGET_NAME=\"$TARGET_NAME\"; $ENV_EXPORTS
        workdir=\$(dirname \"\$TARGET_EXE\")
        [ -d \"\$workdir\" ] && cd \"\$workdir\" 2>/dev/null || true
        wineserver-wrapper -k 2>/dev/null || wineserver -k 2>/dev/null || true
        nohup box64 wine64 \"\$TARGET_EXE\" >/tmp/\"\${TARGET_NAME}_wine.log\" 2>&1 &
        sleep 1
    "
}

run_winecfg() {
    if ! check_emulation_available; then return 1; fi
    asl_gpu_apply
    echo "[*] Opening Wine Configuration..."
    ENV_EXPORTS=$(build_gaming_env_exports)
    asl_chroot_exec "$ENV_EXPORTS winecfg"
}

run_winetricks() {
    if ! check_emulation_available; then return 1; fi
    asl_gpu_apply
    echo "[*] Launching Winetricks..."
    ENV_EXPORTS=$(build_gaming_env_exports)
    asl_chroot_exec "$ENV_EXPORTS winetricks"
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0 2>/dev/null || true
fi

case "${1:-}" in
    setup|setup-gaming)
        setup_gaming
        ;;
    desktop|virtual-desktop)
        shift
        run_wine_desktop "$@"
        ;;
    openbox)
        run_openbox_desktop
        ;;
    picker|gui)
        run_gui_picker
        ;;
    winefile)
        run_winefile
        ;;
    winecfg|cfg)
        run_winecfg
        ;;
    winetricks|tricks)
        run_winetricks
        ;;
    benchmark|bench)
        run_gpu_benchmark
        ;;
    precision|dynarec)
        shift
        TARGET_PRECISION="${1:-status}"
        PRECISION_STATE="/data/local/tmp/asl_dynarec_precision"
        case "$TARGET_PRECISION" in
            safe|accurate|precise)
                asl_exec "echo safe > '$PRECISION_STATE'" 2>/dev/null || true
                echo "[✓] Box64 Dynarec set to Safe / Accurate mode (FASTROUND=0, FASTNAN=0, X87DOUBLE=1)."
                ;;
            fast|performance)
                asl_exec "rm -f '$PRECISION_STATE'" 2>/dev/null || true
                echo "[✓] Box64 Dynarec set to Fast / Performance mode (FASTROUND=1, FASTNAN=1, X87DOUBLE=0)."
                ;;
            status|"")
                CUR_PREC=$(asl_exec "cat '$PRECISION_STATE' 2>/dev/null" 2>/dev/null | tr -d '[:space:]')
                if [ "$CUR_PREC" = "safe" ] || [ "$CUR_PREC" = "accurate" ]; then
                    echo "Current Box64 Dynarec Profile: Safe / Accurate (FASTROUND=0, FASTNAN=0, X87DOUBLE=1)"
                else
                    echo "Current Box64 Dynarec Profile: Fast / Performance (FASTROUND=1, FASTNAN=1, X87DOUBLE=0)"
                fi
                ;;
            *)
                echo "Usage: asl game precision [safe|fast|status]"
                exit 1
                ;;
        esac
        ;;
    run)
        shift
        run_wine_exe "$@"
        ;;
    status|info)
        if ! is_mounted; then
            echo "Gaming Layer: Chroot unmounted"
        else
            wine_ver=$(asl_chroot_exec "export PATH=/opt/wine-x64/bin:/usr/local/bin:/usr/bin:\$PATH; wine --version 2>/dev/null" 2>/dev/null || echo "Not installed")
            box64_ver=$(asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH; box64 --version 2>&1 | head -n1" 2>/dev/null || echo "Not installed")
            echo "Gaming Layer Status:"
            echo "  Wine Version:  ${wine_ver:-Not installed}"
            echo "  Box64 Version: ${box64_ver:-Not installed}"
        fi
        ;;
    menu)
        show_gaming_menu
        ;;
    "")
        show_gaming_menu
        ;;
    *)
        run_wine_exe "$@"
        ;;
esac
