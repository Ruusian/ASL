#!/bin/bash
# ASL: Desktop Theme Switcher

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

get_dbus_env() {
    local pid
    pid=$(asl_chroot_exec "/usr/bin/pgrep -x -n xfsettingsd 2>/dev/null || /usr/bin/pgrep -x -n xfwm4 2>/dev/null || /usr/bin/pgrep -x -n xfce4-panel 2>/dev/null" 2>/dev/null)
    if [ -n "$pid" ]; then
        local bus
        bus=$(asl_exec "tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep '^DBUS_SESSION_BUS_ADDRESS='" 2>/dev/null)
        if [ -n "$bus" ]; then
            echo "export $bus;"
        fi
    fi
}

update_xml_property() {
    local xml_file="$1" prop="$2" val="$3" esc_val file_q
    asl_exec "test -f '$xml_file'" 2>/dev/null || return 0
    esc_val=$(printf '%s\n' "$val" | sed -e 's/[\/&|]/\\&/g')
    file_q=$(printf '%q' "$xml_file")
    asl_exec "sed -i -E 's|(<property name=\"$prop\" type=\"string\" value=\")[^\"]*(\"/>)|\1$esc_val\2|' $file_q" 2>/dev/null || true
}

set_xfce_theme() {
    local gtk_theme="$1" icon_theme="$2" cursor_theme="${3:-Breeze_Snow}"
    if ! is_mounted; then
        echo "[!] Mount the Debian chroot before applying desktop themes."
        return 1
    fi
    local dbus_env
    dbus_env=$(get_dbus_env)

    update_xml_property "$DEBIANPATH/root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" "ThemeName" "$gtk_theme"
    update_xml_property "$DEBIANPATH/root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" "IconThemeName" "$icon_theme"
    update_xml_property "$DEBIANPATH/root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" "CursorThemeName" "$cursor_theme"
    update_xml_property "$DEBIANPATH/root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" "theme" "$gtk_theme"

    asl_chroot_exec "
        mkdir -p /root/.config/gtk-3.0
        cat << 'GTK3EOF' > /root/.config/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=$gtk_theme
gtk-icon-theme-name=$icon_theme
gtk-cursor-theme-name=$cursor_theme
GTK3EOF
        cat << 'GTK2EOF' > /root/.gtkrc-2.0
gtk-theme-name=\"$gtk_theme\"
gtk-icon-theme-name=\"$icon_theme\"
gtk-cursor-theme-name=\"$cursor_theme\"
GTK2EOF
        fc-cache -fv /usr/share/fonts /root/.local/share/fonts 2>/dev/null || true
    " 2>/dev/null || true

    if [ -n "$dbus_env" ]; then
        asl_chroot_exec "
            export DISPLAY=:0
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            $dbus_env
            timeout -k 1s 2 xfconf-query -c xsettings -p /Net/ThemeName -s \"$gtk_theme\" 2>/dev/null || timeout -k 1s 2 xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s \"$gtk_theme\" 2>/dev/null || true
            timeout -k 1s 2 xfconf-query -c xfwm4 -p /general/theme -s \"$gtk_theme\" 2>/dev/null || timeout -k 1s 2 xfconf-query -c xfwm4 -p /general/theme -n -t string -s \"$gtk_theme\" 2>/dev/null || true
            timeout -k 1s 2 xfconf-query -c xsettings -p /Net/IconThemeName -s \"$icon_theme\" 2>/dev/null || timeout -k 1s 2 xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s \"$icon_theme\" 2>/dev/null || true
            timeout -k 1s 2 xfconf-query -c xsettings -p /Gtk/CursorThemeName -s \"$cursor_theme\" 2>/dev/null || timeout -k 1s 2 xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s \"$cursor_theme\" 2>/dev/null || true
        "
    fi
    echo "[✓] Applied desktop theme: $gtk_theme (Icons: $icon_theme)"
}

case "${1:-status}" in
    win11|win11-dark)
        set_xfce_theme "Fluent-Dark" "Fluent-dark"
        ;;
    win11-light)
        set_xfce_theme "Fluent-Light" "Fluent-light"
        ;;
    win11-compact)
        set_xfce_theme "Fluent-Dark-compact" "Fluent-dark"
        ;;
    tokyonight|tokyo)
        set_xfce_theme "Tokyonight-Dark-BL" "Papirus-Dark"
        ;;
    aesthetic)
        set_xfce_theme "Aesthetic-purple" "Papirus-Dark"
        ;;
    graphite)
        set_xfce_theme "Graphite-dark" "Papirus-Dark"
        ;;
    habiboow)
        set_xfce_theme "Habiboow" "Papirus-Dark"
        ;;
    dark)
        set_xfce_theme "Arc-Dark" "Papirus-Dark"
        ;;
    light)
        set_xfce_theme "Arc" "Papirus"
        ;;
    nord)
        set_xfce_theme "Nordic" "Papirus-Dark"
        ;;
    dracula)
        set_xfce_theme "Dracula" "Papirus-Dark"
        ;;
    greybird)
        set_xfce_theme "Greybird" "Papirus"
        ;;
    list)
        echo "Available ASL Desktop Presets:"
        echo "  win11      - Windows 11 Fluent Dark theme + Fluent-dark icons"
        echo "  win11-light - Windows 11 Fluent Light theme + Fluent-light icons"
        echo "  win11-compact - Windows 11 Fluent Dark Compact theme + Fluent-dark icons"
        echo "  tokyonight - Tokyo Night Dark theme + Papirus-Dark icons"
        echo "  aesthetic  - Aesthetic Purple theme + Papirus-Dark icons"
        echo "  graphite   - Graphite Dark theme + Papirus-Dark icons"
        echo "  habiboow   - Habiboow theme + Papirus-Dark icons"
        echo "  dark       - Arc-Dark theme + Papirus-Dark icons"
        echo "  light      - Arc Light theme + Papirus icons"
        echo "  nord       - Nordic theme + Papirus-Dark icons"
        echo "  dracula    - Dracula theme + Papirus-Dark icons"
        echo "  greybird   - Greybird theme + Papirus icons"
        ;;
    status|"")
        if is_mounted; then
            dbus_env=$(get_dbus_env)
            current=""
            if [ -n "$dbus_env" ]; then
                current=$(asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export DISPLAY=:0; $dbus_env timeout -k 1s 2 xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null" 2>/dev/null)
            fi
            if [ -z "$current" ]; then
                current=$(asl_exec "sed -n -E 's/.*<property name=\"ThemeName\" type=\"string\" value=\"([^\"]*)\".*/\1/p' '$DEBIANPATH/root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml'" 2>/dev/null | head -n1)
            fi
            echo "Current Desktop Theme: ${current:-Unknown}"
        else
            echo "Desktop Theme: Chroot unmounted"
        fi
        ;;
    *)
        echo "Usage: asl theme [win11|win11-light|dark|light|nord|dracula|greybird|list|status]"
        exit 1
        ;;
esac
