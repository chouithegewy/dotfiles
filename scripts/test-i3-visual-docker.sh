#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
LABEL="${1:-arch}"
LOG_DIR="${ROOT_DIR}/container-test-logs/${RUN_ID}/i3-visual-${LABEL}"
EXPECT_SCRIPT="/workspace/scripts/bootstrap-test.expect"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
KEEP_CONTAINERS="${KEEP_CONTAINERS:-0}"

mkdir -p "$LOG_DIR"

case "$LABEL" in
  arch)
    IMAGE="archlinux:latest"
    CONTAINER="i3-visual-arch-${RUN_ID}"
    SHELL_PATH="/bin/bash"
    SETUP_CMD=$'pacman -Syu --noconfirm\npacman -S --needed --noconfirm sudo expect shadow xorg-server-xvfb xorg-xinit xorg-xrdb xorg-xsetroot xorg-xprop xorg-xdpyinfo i3-wm i3status xterm imagemagick procps-ng jq'
    ;;
  ubuntu)
    IMAGE="ubuntu:24.04"
    CONTAINER="i3-visual-ubuntu-${RUN_ID}"
    SHELL_PATH="/bin/bash"
    SETUP_CMD=$'export DEBIAN_FRONTEND=noninteractive\napt-get update\napt-get install -y sudo expect xvfb xinit x11-xserver-utils x11-utils i3-wm i3status xterm imagemagick procps jq'
    ;;
  *)
    printf 'usage: %s [arch|ubuntu]\n' "$0" >&2
    exit 2
    ;;
esac

log() {
  printf '%s\n' "$*"
}

cleanup_container() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}

prepare_tester_user() {
  docker exec "$CONTAINER" bash -lc "
    set -e
    username=\$(getent passwd ${HOST_UID} | cut -d: -f1 || true)
    if [ -z \"\$username\" ]; then
      if ! getent group ${HOST_GID} >/dev/null 2>&1; then
        groupadd -g ${HOST_GID} tester
      fi
      useradd -m -u ${HOST_UID} -g ${HOST_GID} -s ${SHELL_PATH} tester
      username=tester
    fi
    homedir=\$(getent passwd \"\$username\" | cut -d: -f6)
    usermod -s ${SHELL_PATH} \"\$username\" || true
    mkdir -p \"\$homedir\" /etc/sudoers.d
    chown -R ${HOST_UID}:${HOST_GID} \"\$homedir\" || true
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' \"\$username\" >/etc/sudoers.d/bootstrap-test-user
    chmod 440 /etc/sudoers.d/bootstrap-test-user
    printf '%s:%s\n' \"\$username\" \"\$homedir\"
  "
}

log "==> docker pull ${IMAGE}"
docker pull "$IMAGE" | tee "${LOG_DIR}/pull.log"

cleanup_container
log "==> start container ${CONTAINER}"
docker run -d --name "$CONTAINER" -v "${ROOT_DIR}:/workspace" -w /workspace "$IMAGE" sleep infinity >"${LOG_DIR}/container-id.txt"

if [ "$KEEP_CONTAINERS" != "1" ]; then
  trap cleanup_container EXIT
fi

log "==> prepare visual test packages"
docker exec "$CONTAINER" bash -lc "$SETUP_CMD" | tee "${LOG_DIR}/setup.log"

IFS=: read -r RUN_USER RUN_HOME <<<"$(prepare_tester_user | tee "${LOG_DIR}/user.log" | tail -n1)"

log "==> run bootstrap installer"
docker exec -u "$RUN_USER" -e HOME="$RUN_HOME" -e USER="$RUN_USER" -e SHELL="$SHELL_PATH" -w /workspace "$CONTAINER" "$EXPECT_SCRIPT" /workspace 2>&1 | tee "${LOG_DIR}/bootstrap.log"

log "==> start i3 under Xvfb and capture screenshot"
set +e
docker exec -u "$RUN_USER" -e HOME="$RUN_HOME" -e USER="$RUN_USER" -e SHELL="$SHELL_PATH" -w /workspace "$CONTAINER" bash -lc '
  set -Eeuo pipefail
  out=/tmp/i3-visual
  rm -rf "$out"
  mkdir -p "$out"

  require_target() {
    local path="$1"
    local expected="$2"
    local actual

    actual="$(readlink -f "$path")"
    printf "%s -> %s\n" "$path" "$actual" >>"$out/links.txt"
    [ "$actual" = "$expected" ]
  }

  require_target "$HOME/.xinitrc" /workspace/dotfiles/x/.xinitrc
  require_target "$HOME/.Xresources" /workspace/dotfiles/x/.Xresources
  test -x "$HOME/.xinitrc"
  require_target "$HOME/.config/i3/config" /workspace/dotfiles/i3/.config/i3/config
  test ! -e "$HOME/.i3/config"

  Xvfb :99 -screen 0 1280x800x24 >"$out/xvfb.log" 2>&1 &
  xvfb_pid=$!
  trap "kill $xvfb_pid >/dev/null 2>&1 || true" EXIT
  export DISPLAY=:99

  for _ in 1 2 3 4 5; do
    xdpyinfo >/dev/null 2>&1 && break
    sleep 1
  done

  xrdb -merge "$HOME/.Xresources"
  i3 -V -c "$HOME/.config/i3/config" >"$out/i3.log" 2>&1 &
  i3_pid=$!
  printf "%s\n" "$i3_pid" >"$out/i3.pid"

  for _ in 1 2 3 4 5; do
    i3-msg -t get_version >/dev/null 2>&1 && break
    sleep 1
  done

  i3-msg exec xterm >/dev/null
  sleep 2
  import -window root "$out/screenshot.png"
  i3-msg -t get_tree >"$out/tree.json"
  i3-msg exit >/dev/null 2>&1 || true
  wait "$i3_pid" >/dev/null 2>&1 || true
' 2>&1 | tee "${LOG_DIR}/visual.log"
visual_status="${PIPESTATUS[0]}"
set -e

docker cp "${CONTAINER}:/tmp/i3-visual/." "$LOG_DIR" >/dev/null 2>&1 || true

if [ "$visual_status" -ne 0 ]; then
  log "Visual i3 smoke test failed with exit code ${visual_status}."
  exit "$visual_status"
fi

log
log "Saved visual artifacts under ${LOG_DIR}"
log "Open ${LOG_DIR}/screenshot.png to inspect the installed i3 session."
