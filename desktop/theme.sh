#!/bin/bash
# ASL: Desktop Theme Switcher

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

set_xfce_theme() {
    local gtk_theme="$1" icon_theme="$2" cursor_theme="${3:-Breeze_Snow}"
    if ! su -c "grep -q -w '$DEBIANPATH/proc' /proc/mounts" 2>/dev/null; then
        echo "[!] Mount the Debian chroot before applying desktop themes."
        return 1
    fi
    su -c "chroot '$DEBIANPATH' /bin/bash -c '
        export DISPLAY=:0
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        xfconf-query -c xsettings -p /Net/ThemeName -s \"$gtk_theme\" 2>/dev/null || xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s \"$gtk_theme\" 2>/dev/null || true
        xfconf-query -c xsettings -p /Net/IconThemeName -s \"$icon_theme\" 2>/dev/null || xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s \"$icon_theme\" 2>/dev/null || true
        xfconf-query -c xsettings -p /Gtk/CursorThemeName -s \"$cursor_theme\" 2>/dev/null || xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s \"$cursor_theme\" 2>/dev/null || true
    '"
    echo "[✓] Applied desktop theme: $gtk_theme (Icons: $icon_theme)"
}

case "${1:-status}" in
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
        echo "  dark     - Arc-Dark theme + Papirus-Dark icons"
        echo "  light    - Arc Light theme + Papirus icons"
        echo "  nord     - Nordic theme + Papirus-Dark icons"
        echo "  dracula  - Dracula theme + Papirus-Dark icons"
        echo "  greybird - Greybird theme + Papirus icons"
        ;;
    status|"")
        if su -c "grep -q -w '$DEBIANPATH/proc' /proc/mounts" 2>/dev/null; then
            current=$(su -c "chroot '$DEBIANPATH' /bin/bash -c 'export DISPLAY=:0; xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || echo Unknown'")
            echo "Current Desktop Theme: $current"
        else
            echo "Desktop Theme: Chroot unmounted"
        fi
        ;;
    *)
        echo "Usage: asl theme [dark|light|nord|dracula|greybird|list|status]"
        exit 1
        ;;
esac
