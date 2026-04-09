#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${1:-$(date +%Y%m%d-%H%M%S)}"
LOG_DIR="${ROOT_DIR}/container-test-logs/${RUN_ID}"
EXPECT_SCRIPT="/workspace/scripts/bootstrap-test.expect"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
KEEP_CONTAINERS="${KEEP_CONTAINERS:-0}"

mkdir -p "$LOG_DIR"

log() {
  printf '%s\n' "$*"
}

run_and_capture() {
  local logfile="$1"
  shift

  set +e
  "$@" 2>&1 | tee "$logfile"
  local status="${PIPESTATUS[0]}"
  set -e
  return "$status"
}

cleanup_container() {
  local name="$1"
  docker rm -f "$name" >/dev/null 2>&1 || true
}

prepare_tester_user() {
  local container="$1"
  local shell_path="$2"
  local info

  info="$(docker exec "$container" bash -lc "
    set -e
    username=\$(getent passwd ${HOST_UID} | cut -d: -f1 || true)
    if [ -z \"\$username\" ]; then
      if ! getent group ${HOST_GID} >/dev/null 2>&1; then
        groupadd -g ${HOST_GID} tester
      fi
      if ! id tester >/dev/null 2>&1; then
        useradd -m -u ${HOST_UID} -g ${HOST_GID} -s ${shell_path} tester
      fi
      username=tester
    fi

    homedir=\$(getent passwd \"\$username\" | cut -d: -f6)
    if command -v usermod >/dev/null 2>&1; then
      usermod -s ${shell_path} \"\$username\" || true
    fi
    mkdir -p \"\$homedir\"
    chown -R ${HOST_UID}:${HOST_GID} \"\$homedir\" || true
    mkdir -p /etc/sudoers.d
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' \"\$username\" >/etc/sudoers.d/bootstrap-test-user
    chmod 440 /etc/sudoers.d/bootstrap-test-user
    printf '%s:%s\n' \"\$username\" \"\$homedir\"
  ")" || return 1

  printf '%s\n' "$info"
}

run_bootstrap_test() {
  local label="$1"
  local image="$2"
  local container="$3"
  local setup_cmd="$4"
  local shell_path="$5"
  local log_file="${LOG_DIR}/${label}.log"
  local status=0
  local run_user
  local run_home

  log
  log "==> ${label}: docker pull ${image}"
  docker pull "$image" | tee "${LOG_DIR}/${label}-pull.log"

  cleanup_container "$container"

  log
  log "==> ${label}: start container ${container}"
  docker run -d --name "$container" -v "${ROOT_DIR}:/workspace" -w /workspace "$image" sleep infinity >"${LOG_DIR}/${label}-container-id.txt"

  if [ "$KEEP_CONTAINERS" != "1" ]; then
    trap "cleanup_container '$container'" RETURN
  fi

  log
  log "==> ${label}: prepare container"
  docker exec "$container" bash -lc "$setup_cmd" | tee "${LOG_DIR}/${label}-setup.log"
  IFS=: read -r run_user run_home <<<"$(prepare_tester_user "$container" "$shell_path" | tee "${LOG_DIR}/${label}-user.log" | tail -n1)"

  log
  log "==> ${label}: run bootstrap"
  if run_and_capture "$log_file" docker exec -u "$run_user" -e HOME="$run_home" -e USER="$run_user" -e SHELL="$shell_path" -w /workspace "$container" "$EXPECT_SCRIPT" /workspace; then
    status=0
  else
    status=$?
  fi

  printf 'exit_code=%s\n' "$status" >"${LOG_DIR}/${label}-exit.txt"

  if [ "$KEEP_CONTAINERS" != "1" ]; then
    cleanup_container "$container"
    trap - RETURN
  fi

  return "$status"
}

UBUNTU_SETUP=$'export DEBIAN_FRONTEND=noninteractive\napt-get update\napt-get install -y sudo expect'
ARCH_SETUP=$'pacman -Syu --noconfirm\npacman -S --noconfirm sudo expect shadow'

ubuntu_status=0
arch_status=0

run_bootstrap_test "ubuntu" "ubuntu:24.04" "bootstrap-test-ubuntu-${RUN_ID}" "$UBUNTU_SETUP" "/bin/bash" || ubuntu_status=$?
run_bootstrap_test "arch" "archlinux:latest" "bootstrap-test-arch-${RUN_ID}" "$ARCH_SETUP" "/bin/bash" || arch_status=$?

{
  printf 'run_id=%s\n' "$RUN_ID"
  printf 'ubuntu_exit=%s\n' "$ubuntu_status"
  printf 'arch_exit=%s\n' "$arch_status"
} >"${LOG_DIR}/summary.txt"

log
log "Saved logs under ${LOG_DIR}"
log "Ubuntu exit code: ${ubuntu_status}"
log "Arch exit code: ${arch_status}"

if [ "$ubuntu_status" -ne 0 ] || [ "$arch_status" -ne 0 ]; then
  exit 1
fi
