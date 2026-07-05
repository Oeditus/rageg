#!/usr/bin/env bash
#
# clean.sh -- wipe all rageg / ragex / dllb state for an absolutely fresh start.
#
# Removes, in order:
#   1. dllb database  -- logical wipe over TCP when the server is running,
#                        otherwise the on-disk redb + search-index files.
#   2. rageg state    -- ~/.rageg (dashboard stats, ingest cache, profiles).
#   3. ragex caches   -- ~/.cache/ragex (embeddings, graph, analysis caches)
#                        and ~/.ragex (MCP telemetry, editor undo & backups).
#   4. build output   -- _build and erl_crash.dump in the rageg project
#                        (skip with --keep-build; add deps/ with --purge-deps).
#
# Safe by default: prints a plan and asks for confirmation. Use -y to skip the
# prompt and -n for a dry run (show what would happen, change nothing).
#
# Configuration (all optional environment variables):
#   DLLB_HOST       dllb server host             (default 127.0.0.1)
#   DLLB_PORT       dllb server port             (default 3009)
#   DLLB_PATH       dllb database file path      (default: auto-detect)
#   DLLB_DIR        dllb server repo to scan     (default: <rageg>/../dllb)
#   XDG_CACHE_HOME  overrides ~/.cache for ragex caches
#
# Usage: scripts/clean.sh [-y|--yes] [-n|--dry-run] [--keep-build]
#                         [--purge-deps] [-h|--help]

set -euo pipefail

# ---- configuration -------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
RAGEG_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

: "${HOME:?HOME must be set}"

DLLB_HOST="${DLLB_HOST:-127.0.0.1}"
DLLB_PORT="${DLLB_PORT:-3009}"
DLLB_DIR_DEFAULT="$(cd -- "${RAGEG_DIR}/../dllb" >/dev/null 2>&1 && pwd || echo "${RAGEG_DIR}/../dllb")"
DLLB_DIR="${DLLB_DIR:-${DLLB_DIR_DEFAULT}}"
CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

ASSUME_YES=0
DRY_RUN=0
PURGE_BUILD=1
PURGE_DEPS=0

# Tables created by rageg ingestion (mirrors Rageg.Dllb.clear_all!/0).
DLLB_TABLES=(ast_node _edge_idx calls contains imports type_ref inherits defines)

# ---- helpers -------------------------------------------------------------
log()  { printf '  %s\n' "$*"; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }

usage() {
  grep -E '^# ?' "${BASH_SOURCE[0]}" | sed -e '1d' -e 's/^# \{0,1\}//'
  exit 0
}

# Remove a path, guarding against catastrophic targets and honoring --dry-run.
safe_rm() {
  local target="$1"
  case "$target" in
    "" | "/" | "$HOME")
      warn "refusing to remove unsafe path: '${target:-<empty>}'"
      return 0
      ;;
  esac

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would remove: $target"
  else
    rm -rf -- "$target"
    log "removed: $target"
  fi
}

# Succeeds if a TCP connection to the dllb server can be opened.
dllb_up() {
  (exec 3<>"/dev/tcp/${DLLB_HOST}/${DLLB_PORT}") 2>/dev/null
}

# Clear every rageg table on a running dllb server over its line protocol.
dllb_logical_wipe() {
  exec 3<>"/dev/tcp/${DLLB_HOST}/${DLLB_PORT}" || return 1

  local table
  for table in "${DLLB_TABLES[@]}"; do
    if [ "$DRY_RUN" -eq 1 ]; then
      log "[dry-run] would send: DELETE ${table}"
    else
      printf 'DELETE %s\n' "$table" >&3
    fi
  done

  if [ "$DRY_RUN" -eq 0 ]; then
    # One JSON response line per statement; stop after a short idle timeout
    # since the server keeps the connection open.
    while IFS= read -r -t 2 line <&3; do
      log "dllb <- ${line}"
    done || true
  fi

  exec 3>&- 3<&-
}

# Remove the on-disk dllb database (server must be stopped) plus its sidecars.
dllb_file_wipe() {
  local candidates=()
  if [ -n "${DLLB_PATH:-}" ]; then
    candidates+=("$DLLB_PATH" "${DLLB_DIR}/${DLLB_PATH}")
  fi
  candidates+=(
    "${DLLB_DIR}/dllb.redb" "${DLLB_DIR}/dllb_dev.redb"
    "${RAGEG_DIR}/dllb.redb" "${RAGEG_DIR}/dllb_dev.redb"
    "${PWD}/dllb.redb" "${PWD}/dllb_dev.redb"
  )

  local found=0 db
  for db in "${candidates[@]}"; do
    if [ -e "$db" ]; then
      found=1
      safe_rm "$db"
      safe_rm "${db}.search"
      safe_rm "${db}-wal"
      safe_rm "${db}.wal"
      safe_rm "${db}.lock"
    fi
  done

  safe_rm "${DLLB_DIR}/.tantivy"

  if [ "$found" -eq 0 ]; then
    warn "no dllb database file found (looked in ${DLLB_DIR} and ${RAGEG_DIR})."
    warn "if your DB lives elsewhere, re-run with: DLLB_PATH=/path/to/your.redb $0"
  fi
}

# ---- argument parsing ----------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) ASSUME_YES=1 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --keep-build) PURGE_BUILD=0 ;;
    --purge-deps) PURGE_DEPS=1 ;;
    -h | --help) usage ;;
    *)
      warn "unknown option: $1"
      usage
      ;;
  esac
  shift
done

# ---- plan ----------------------------------------------------------------
info "rageg fresh-start cleanup"
log "rageg project : ${RAGEG_DIR}"
log "dllb server   : ${DLLB_HOST}:${DLLB_PORT}  (repo: ${DLLB_DIR})"
log "cache home    : ${CACHE_HOME}"

info "This will remove:"
log "- dllb database (logical wipe if the server is running, else on-disk files)"
log "- ${HOME}/.rageg"
log "- ${CACHE_HOME}/ragex"
log "- ${HOME}/.ragex"
if [ "$PURGE_DEPS" -eq 1 ]; then
  log "- ${RAGEG_DIR}/_build, ${RAGEG_DIR}/deps, ${RAGEG_DIR}/erl_crash.dump"
elif [ "$PURGE_BUILD" -eq 1 ]; then
  log "- ${RAGEG_DIR}/_build, ${RAGEG_DIR}/erl_crash.dump  (recompile on next boot)"
else
  log "- ${RAGEG_DIR}/erl_crash.dump  (build kept: --keep-build)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  warn "dry run -- nothing will actually be removed."
elif [ "$ASSUME_YES" -ne 1 ]; then
  printf '\nProceed? [y/N] '
  read -r reply || reply=""
  case "$reply" in
    y | Y | yes | YES) ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

# ---- 1. dllb database ----------------------------------------------------
info "1/4  dllb database"
if dllb_up; then
  log "server is reachable -- clearing all tables over TCP"
  dllb_logical_wipe || warn "logical wipe failed; stop the server and re-run to wipe files"
else
  log "server not reachable -- removing on-disk database files"
  dllb_file_wipe
fi

# ---- 2. rageg state ------------------------------------------------------
info "2/4  rageg state"
safe_rm "${HOME}/.rageg"

# ---- 3. ragex caches -----------------------------------------------------
info "3/4  ragex caches"
safe_rm "${CACHE_HOME}/ragex"
safe_rm "${HOME}/.ragex"

# ---- 4. build artifacts --------------------------------------------------
info "4/4  build artifacts"
safe_rm "${RAGEG_DIR}/erl_crash.dump"
if [ "$PURGE_BUILD" -eq 1 ] || [ "$PURGE_DEPS" -eq 1 ]; then
  safe_rm "${RAGEG_DIR}/_build"
fi
if [ "$PURGE_DEPS" -eq 1 ]; then
  safe_rm "${RAGEG_DIR}/deps"
fi

# ---- done ----------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run complete -- nothing was removed."
else
  info "Done. State is absolutely fresh."
fi

cat <<EOF

  Next steps:
    - (Re)start the dllb server:  cd "${DLLB_DIR}" && ./start_dev.sh
EOF
if [ "$PURGE_DEPS" -eq 1 ]; then
  echo "    - Fetch dependencies:         (cd \"${RAGEG_DIR}\" && mix deps.get)"
fi
cat <<EOF
    - Start rageg:                (cd "${RAGEG_DIR}" && iex -S mix phx.server)
EOF
