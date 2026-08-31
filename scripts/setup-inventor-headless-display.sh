#!/usr/bin/env bash
set -euo pipefail

TARGET_GPU_UUID="d9af9e5935f8aff337a1d6d44d145cfc"
DISPLAY_NUM="1"
DISPLAY_NAME=":${DISPLAY_NUM}"
VNC_PORT="5911"
XAUTHORITY_FILE="${HOME}/.Xauthority-inventor"
VNC_PASSWORD_FILE="${HOME}/.vnc/inventor-x11vnc.pass"
XORG_CONFIG="/etc/X11/inventor-xorg.conf"
XORG_LOG="/var/log/Xorg.inventor.log"
STATE_DIR="${HOME}/.cache/inventor-on-linux/headless-display"
OPENBOX_PID_FILE="${STATE_DIR}/openbox.pid"
X11VNC_PID_FILE="${STATE_DIR}/x11vnc.pid"
XTERM_PID_FILE="${STATE_DIR}/xterm.pid"
OPENBOX_LOG="${STATE_DIR}/openbox.log"
X11VNC_LOG="${STATE_DIR}/x11vnc.log"
XTERM_LOG="${STATE_DIR}/xterm.log"

die() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

find_gpu() {
    local row rest bus_hex dev_func dev_hex func_hex
    row="$(nvidia-smi --query-gpu=index,pci.bus_id,uuid,name --format=csv,noheader,nounits | grep -i -m1 "$TARGET_GPU_UUID" || true)"
    [[ -n "$row" ]] || die "Could not find configured Inventor GPU UUID: $TARGET_GPU_UUID"

    GPU_INDEX="$(awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}' <<<"$row")"
    GPU_PCI="$(awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' <<<"$row")"
    GPU_UUID="$(awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}' <<<"$row")"
    GPU_NAME="$(awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4}' <<<"$row")"

    rest="${GPU_PCI#*:}"
    bus_hex="${rest%%:*}"
    dev_func="${rest#*:}"
    dev_hex="${dev_func%%.*}"
    func_hex="${dev_func#*.}"

    [[ "$bus_hex" =~ ^[0-9A-Fa-f]+$ ]] || die "Unexpected PCI bus address: $GPU_PCI"
    [[ "$dev_hex" =~ ^[0-9A-Fa-f]+$ ]] || die "Unexpected PCI device address: $GPU_PCI"
    [[ "$func_hex" =~ ^[0-9A-Fa-f]+$ ]] || die "Unexpected PCI function address: $GPU_PCI"

    XORG_BUS_ID="PCI:$((16#$bus_hex)):$((16#$dev_hex)):$((16#$func_hex))"
}

create_xauthority() {
    rm -f "$XAUTHORITY_FILE"
    touch "$XAUTHORITY_FILE"
    chmod 600 "$XAUTHORITY_FILE"
    xauth -f "$XAUTHORITY_FILE" add "$DISPLAY_NAME" MIT-MAGIC-COOKIE-1 "$(mcookie)"
}

write_xorg_config() {
    local tmp
    tmp="$(mktemp)"
    cat >"$tmp" <<EOC
Section "ServerLayout"
    Identifier     "InventorHeadlessLayout"
    Screen      0  "InventorHeadlessScreen" 0 0
EndSection

Section "Device"
    Identifier     "InventorGPU"
    Driver         "nvidia"
    BusID          "$XORG_BUS_ID"
    Option         "AllowEmptyInitialConfiguration" "True"
    Option         "UseDisplayDevice" "none"
EndSection

Section "Screen"
    Identifier     "InventorHeadlessScreen"
    Device         "InventorGPU"
    DefaultDepth    24

    SubSection "Display"
        Depth       24
        Virtual     1920 1080
    EndSubSection
EndSection
EOC
    sudo install -o root -g root -m 0644 "$tmp" "$XORG_CONFIG"
    rm -f "$tmp"
}

setup() {
    echo "Installing headless-display dependencies..."
    sudo apt-get update
    sudo apt-get install -y x11vnc openbox xterm xauth x11-xserver-utils mesa-utils dbus-x11

    for cmd in nvidia-smi Xorg xauth x11vnc openbox xterm xdpyinfo glxinfo; do
        have "$cmd" || die "$cmd is not available after setup."
    done

    find_gpu
    echo "Inventor GPU:"
    echo "  index:      $GPU_INDEX"
    echo "  name:       $GPU_NAME"
    echo "  PCI:        $GPU_PCI"
    echo "  UUID:       $GPU_UUID"
    echo "  Xorg BusID: $XORG_BUS_ID"

    write_xorg_config
    create_xauthority
    mkdir -p "$STATE_DIR" "${HOME}/.vnc"
    chmod 700 "${HOME}/.vnc"

    if [[ ! -s "$VNC_PASSWORD_FILE" ]]; then
        echo
        echo "Create a password for the Ubuntu Inventor VNC desktop."
        echo "This is separate from the Windows VM VNC password."
        x11vnc -storepasswd "$VNC_PASSWORD_FILE"
        chmod 600 "$VNC_PASSWORD_FILE"
    fi

    echo
    echo "Setup complete."
    echo "Next: bash $0 start"
}

wait_for_x() {
    local attempt
    for attempt in $(seq 1 30); do
        if DISPLAY="$DISPLAY_NAME" XAUTHORITY="$XAUTHORITY_FILE" xdpyinfo >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "Xorg log tail:" >&2
    sudo tail -n 120 "$XORG_LOG" >&2 || true
    return 1
}

start() {
    [[ -f "$XORG_CONFIG" ]] || die "$XORG_CONFIG does not exist. Run '$0 setup' first."
    [[ -s "$XAUTHORITY_FILE" ]] || die "$XAUTHORITY_FILE does not exist. Run '$0 setup' first."
    [[ -s "$VNC_PASSWORD_FILE" ]] || die "$VNC_PASSWORD_FILE does not exist. Run '$0 setup' first."

    find_gpu
    mkdir -p "$STATE_DIR"

    if DISPLAY="$DISPLAY_NAME" XAUTHORITY="$XAUTHORITY_FILE" xdpyinfo >/dev/null 2>&1; then
        echo "X display $DISPLAY_NAME is already running."
    else
        echo "Starting NVIDIA-backed Xorg display $DISPLAY_NAME on GPU $GPU_INDEX..."
        sudo systemctl stop inventor-xorg.service >/dev/null 2>&1 || true
        sudo rm -f "/tmp/.X${DISPLAY_NUM}-lock"
        sudo systemd-run \
            --unit=inventor-xorg \
            --collect \
            --service-type=simple \
            /usr/lib/xorg/Xorg \
            "$DISPLAY_NAME" \
            -config "$XORG_CONFIG" \
            -auth "$XAUTHORITY_FILE" \
            -nolisten tcp \
            -noreset \
            -novtswitch \
            -sharevts \
            -logfile "$XORG_LOG" \
            >/dev/null
        wait_for_x || die "Xorg display $DISPLAY_NAME did not become usable."
    fi

    if [[ -f "$OPENBOX_PID_FILE" ]] && kill -0 "$(cat "$OPENBOX_PID_FILE")" 2>/dev/null; then
        echo "Openbox already running."
    else
        nohup env DISPLAY="$DISPLAY_NAME" XAUTHORITY="$XAUTHORITY_FILE" dbus-run-session -- openbox-session >"$OPENBOX_LOG" 2>&1 &
        echo $! >"$OPENBOX_PID_FILE"
        sleep 2
    fi

    if [[ -f "$X11VNC_PID_FILE" ]] && kill -0 "$(cat "$X11VNC_PID_FILE")" 2>/dev/null; then
        echo "x11vnc already running."
    else
        nohup x11vnc \
            -display "$DISPLAY_NAME" \
            -auth "$XAUTHORITY_FILE" \
            -rfbauth "$VNC_PASSWORD_FILE" \
            -rfbport "$VNC_PORT" \
            -localhost \
            -forever \
            -shared \
            -noxdamage \
            -o "$X11VNC_LOG" \
            >/dev/null 2>&1 &
        echo $! >"$X11VNC_PID_FILE"
        sleep 2
    fi

    if [[ -f "$XTERM_PID_FILE" ]] && kill -0 "$(cat "$XTERM_PID_FILE")" 2>/dev/null; then
        echo "xterm already running."
    else
        nohup env DISPLAY="$DISPLAY_NAME" XAUTHORITY="$XAUTHORITY_FILE" xterm -geometry 120x40+20+20 -title "Inventor Linux Session" >"$XTERM_LOG" 2>&1 &
        echo $! >"$XTERM_PID_FILE"
    fi

    echo
    echo "Display is ready."
    echo "  DISPLAY=$DISPLAY_NAME"
    echo "  XAUTHORITY=$XAUTHORITY_FILE"
    echo "  VNC server=127.0.0.1:$VNC_PORT"
    echo
    echo "From your workstation, create an SSH tunnel:"
    echo "  ssh -N -L ${VNC_PORT}:127.0.0.1:${VNC_PORT} ai4@<SERVER-IP>"
    echo "Then connect TigerVNC Viewer to 127.0.0.1:${VNC_PORT}"
}

stop_pid_file() {
    local file="$1" pid=""
    if [[ -f "$file" ]]; then
        pid="$(cat "$file" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$file"
    fi
}

stop() {
    stop_pid_file "$XTERM_PID_FILE"
    stop_pid_file "$X11VNC_PID_FILE"
    stop_pid_file "$OPENBOX_PID_FILE"
    sudo systemctl stop inventor-xorg.service >/dev/null 2>&1 || true
    echo "Inventor headless display stopped."
}

status() {
    find_gpu
    echo "Inventor GPU: $GPU_INDEX / $GPU_NAME / $GPU_PCI / $GPU_UUID"
    echo "Xorg BusID: $XORG_BUS_ID"

    if DISPLAY="$DISPLAY_NAME" XAUTHORITY="$XAUTHORITY_FILE" xdpyinfo >/dev/null 2>&1; then
        echo "X display $DISPLAY_NAME: OK"
    else
        echo "X display $DISPLAY_NAME: NOT RUNNING"
    fi

    if systemctl is-active --quiet inventor-xorg.service 2>/dev/null; then
        echo "inventor-xorg.service: active"
    else
        echo "inventor-xorg.service: inactive"
    fi

    if ss -ltn 2>/dev/null | grep -qE "127\\.0\\.0\\.1:${VNC_PORT}[[:space:]]"; then
        echo "x11vnc localhost:$VNC_PORT: listening"
    else
        echo "x11vnc localhost:$VNC_PORT: not listening"
    fi

    echo "GLX renderer:"
    DISPLAY="$DISPLAY_NAME" XAUTHORITY="$XAUTHORITY_FILE" glxinfo -B 2>/dev/null | grep -E 'direct rendering|OpenGL vendor|OpenGL renderer' || true
}

case "${1:-}" in
    setup) setup ;;
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "Usage: $0 {setup|start|status|stop}" >&2; exit 2 ;;
esac
