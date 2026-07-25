#!/usr/bin/env bash
#
# start.sh -- bring up the full local stack: dllb server, then rageg.
#
# Does, in order:
#   1. dllb server -- start it in <rageg>/../dllb (background, logs to a file)
#                     unless it is already listening. Waits until it accepts
#                     TCP connections before continuing.
#   2. rageg       -- start the Phoenix server in the foreground unless it is
#                     already listening. Runs under iex by default.
#
# Defensive by design: probes the TCP ports first and never launches a second
# copy of a server that is already up. Safe to re-run.
#
# Configuration (all optional environment variables):
#   DLLB_HOST       dllb server host                (default 127.0.0.1)
#   DLLB_PORT       dllb server port                (default 3009)
#   DLLB_DIR        dllb server repo                (default: <rageg>/../dllb)
#   DLLB_START      command used to start dllb       (default: ./start_dev.sh)
#   DLLB_LOG        dllb log file                   (default: <dllb>/dllb.log)
#   DLLB_WAIT       seconds to wait for dllb readiness (default 60)
#   RAGEG_HOST      rageg (Phoenix) host            (default 127.0.0.1)
#   RAGEG_PORT      rageg (Phoenix) port            (default 4000)
#   RAGEG_START     command used to start rageg      (default: iex -S mix phx.server)
#
# Usage: scripts/start.sh [-h|--help]

set -euo pipefail

# ---- configuration -------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
RAGEG_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

DLLB_HOST="${DLLB_HOST:-127.0.0.1}"
DLLB_PORT="${DLLB_PORT:-3009}"
DLLB_DIR_DEFAULT="$(cd -- "${RAGEG_DIR}/../dllb" >/dev/null 2>&1 && pwd || echo "${RAGEG_DIR}/../dllb")"
DLLB_DIR="${DLLB_DIR:-${DLLB_DIR_DEFAULT}}"
DLLB_START="${DLLB_START:-./start_dev.sh}"
DLLB_LOG="${DLLB_LOG:-${DLLB_DIR}/dllb.log}"
DLLB_WAIT="${DLLB_WAIT:-60}"

RAGEG_HOST="${RAGEG_HOST:-127.0.0.1}"
RAGEG_PORT="${RAGEG_PORT:-4000}"
RAGEG_START="${RAGEG_START:-iex -S mix phx.server}"

# ---- helpers -------------------------------------------------------------
log()  { printf '  %s\n' "$*"; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m  x %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  grep -E '^# ?' "${BASH_SOURCE[0]}" | sed -e '1d' -e 's/^# \{0,1\}//'
  exit 0
}

# Succeeds if a TCP connection to host:port can be opened.
port_up() {
  local host="$1" port="$2"
  (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null
}

# ---- argument parsing ----------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage ;;
    *)
      warn "unknown option: $1"
      usage
      ;;
  esac
  shift
done

# ---- plan ----------------------------------------------------------------
info "rageg stack startup"
log "rageg project : ${RAGEG_DIR}  (${RAGEG_HOST}:${RAGEG_PORT})"
log "dllb server   : ${DLLB_HOST}:${DLLB_PORT}  (repo: ${DLLB_DIR})"

# ---- 1. dllb server ------------------------------------------------------
info "1/2  dllb server"
if port_up "${DLLB_HOST}" "${DLLB_PORT}"; then
  log "already listening on ${DLLB_HOST}:${DLLB_PORT} -- leaving it alone"
else
  [ -d "${DLLB_DIR}" ] || die "dllb repo not found at ${DLLB_DIR} (set DLLB_DIR)"
  log "not running -- starting in ${DLLB_DIR}"
  log "command : ${DLLB_START}"
  log "logs    : ${DLLB_LOG}"

  # Launch detached so it survives this script and the foreground rageg process.
  (
    cd -- "${DLLB_DIR}"
    nohup ${DLLB_START} >>"${DLLB_LOG}" 2>&1 &
    echo "$!" >"${DLLB_DIR}/.dllb.pid"
  )
  log "started (pid $(/bin/cat "${DLLB_DIR}/.dllb.pid" 2>/dev/null || echo '?'))"

  # Wait for it to accept connections before we start rageg, which needs it.
  log "waiting up to ${DLLB_WAIT}s for ${DLLB_HOST}:${DLLB_PORT} ..."
  waited=0
  until port_up "${DLLB_HOST}" "${DLLB_PORT}"; do
    if [ "${waited}" -ge "${DLLB_WAIT}" ]; then
      warn "dllb did not become ready within ${DLLB_WAIT}s -- check ${DLLB_LOG}"
      die "aborting: rageg requires a running dllb server"
    fi
    sleep 1
    waited=$((waited + 1))
  done
  log "dllb is ready (after ${waited}s)"
fi

# ---- 2. rageg ------------------------------------------------------------
info "2/2  rageg"
if port_up "${RAGEG_HOST}" "${RAGEG_PORT}"; then
  warn "rageg already listening on ${RAGEG_HOST}:${RAGEG_PORT} -- not starting a second instance"
  info "Stack is up. Nothing more to do."
  exit 0
fi

log "starting rageg in foreground: ${RAGEG_START}"
log "(dllb keeps running in the background; stop it with: kill \$(/bin/cat \"${DLLB_DIR}/.dllb.pid\"))"
cd -- "${RAGEG_DIR}"
exec ${RAGEG_START}
