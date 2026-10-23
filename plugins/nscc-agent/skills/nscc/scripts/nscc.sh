#!/usr/bin/env bash
# nscc.sh — lets an AI coding agent (Claude Code, Codex) on your computer drive NSCC through an
# SSH ControlMaster socket that *you* opened once with your own password.
#
# It never asks for, stores or forwards a password. If the connection is not open it prints the
# login command for you to run in your own terminal, and exits 2.
#
# Settings: environment variables, else KEY=value lines in ~/.config/nscc/config
#   NSCC_USER     NSCC username                      (required)
#   NSCC_HOST     login host                         (default aspire2antu.nscc.sg)
#   NSCC_PROJECT  PBS project id, added as qsub -P   (for submit)
#   NSCC_SOCKET   control socket                     (default ~/.ssh/cm/nscc-<user>@<host>.sock)
#   NSCC_POLL     seconds between checks in wait     (default 60)
#   NSCC_LOCAL    1 = the agent runs on NSCC itself  (default: 1 on asp2a-login* hosts, else 0)
#
# On NSCC itself (references/on-nscc.md) there is no socket and no password: commands run
# directly and put/get are not needed.
#
# Commands:
#   login                         print the login command (does not run it)
#   check                         is the connection alive?
#   run '<command>'               run a command on the login node
#   run <<'EOF' ... EOF           run a multi-line bash script from stdin
#   put <local> <remote> [rsync options]   upload (resumable), e.g. --exclude .venv
#   get <remote> <local> [rsync options]   download
#   submit <script> [qsub options]         upload a PBS script, qsub it, print the job id
#   jobs                          your recent jobs, including finished ones
#   status <jobid>                state, queue comment, walltime, exit status, log path
#   tail <remote file> [n]        last n lines of a file on NSCC (default 40)
#   wait <jobid> [log]            block until the job ends, show status and log tail;
#                                 exits 0 if the job exited 0, 1 if it failed, 2 if the connection dropped
#   close                         close the connection
set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/nscc/config"
if [[ -f "$CONF" ]]; then
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^NSCC_(USER|HOST|PROJECT|SOCKET|POLL|LOCAL)$ ]] || continue
    [[ -n "${!k:-}" ]] || export "$k=$v"
  done < <(grep -E '^NSCC_[A-Z]+=' "$CONF")
fi
if [[ -z "${NSCC_LOCAL:-}" ]]; then
  if [[ "$(hostname)" == asp2a-login* ]]; then NSCC_LOCAL=1; else NSCC_LOCAL=0; fi
fi
if [[ "$NSCC_LOCAL" == 1 ]]; then NSCC_USER="${NSCC_USER:-$(id -un)}"; fi
NSCC_HOST="${NSCC_HOST:-aspire2antu.nscc.sg}"
NSCC_SOCKET="${NSCC_SOCKET:-$HOME/.ssh/cm/nscc-${NSCC_USER:-unset}@${NSCC_HOST}.sock}"
NSCC_POLL="${NSCC_POLL:-60}"
SSH_OPTS=(-o ControlMaster=no -o "ControlPath=$NSCC_SOCKET" -o BatchMode=yes -o ConnectTimeout=20)

die() { echo "nscc: $*" >&2; exit 64; }
target() { echo "${NSCC_USER}@${NSCC_HOST}"; }

login_cmd() {
  local d; d="$(dirname "$NSCC_SOCKET")"
  echo "mkdir -p -m 700 \"$d\" && ssh -o ControlMaster=auto -o ControlPath=\"$NSCC_SOCKET\" -o ControlPersist=yes -o ServerAliveInterval=60 $(target) hostname"
}

lost() {
  {
    echo "nscc: no connection to NSCC${1:+ ($1)}. Jobs already submitted keep running."
    echo "Ask the user to run this in their OWN terminal and type their password:"
    echo
    echo "    $(login_cmd)"
    echo
  } >&2
  exit 2
}

# Run on NSCC. ssh exits 255 only when the connection itself failed.
r() {
  if [[ "$NSCC_LOCAL" == 1 ]]; then bash -c "$*"; return; fi
  local rc=0
  # shellcheck disable=SC2029  # the remote command is deliberately built on this side
  ssh "${SSH_OPTS[@]}" "$(target)" "$@" || rc=$?
  [[ $rc -eq 255 ]] && lost "connection dropped"
  return $rc
}

connect() {
  [[ "$NSCC_LOCAL" == 1 ]] && return
  [[ -n "${NSCC_USER:-}" ]] || die "NSCC_USER is not set. Export it, or put NSCC_USER=<username> in $CONF"
  ssh -O check -o "ControlPath=$NSCC_SOCKET" "$(target)" >/dev/null 2>&1 || lost
}

not_local() {
  [[ "$NSCC_LOCAL" == 1 ]] && die "already on NSCC: files are local, use cp or rsync directly"
  return 0
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  login)  [[ "$NSCC_LOCAL" == 1 ]] && { echo "nscc: already on NSCC ($(hostname)), no login needed"; exit 0; }
          [[ -n "${NSCC_USER:-}" ]] || die "NSCC_USER is not set"; login_cmd ;;
  check)  connect
          if [[ "$NSCC_LOCAL" == 1 ]]; then echo "nscc: running on NSCC itself as $NSCC_USER ($(hostname))"
          else echo "nscc: connected to $(target) ($(r hostname))"; fi ;;
  run)    connect
          if [[ $# -gt 0 ]]; then r "$*"; else r 'bash -s'; fi ;;
  put)    not_local; connect; [[ $# -ge 2 ]] || die "usage: nscc.sh put <local> <remote> [rsync options]"
          src="$1" dst="$2"; shift 2
          rsync -a --partial --info=progress2 -e "ssh ${SSH_OPTS[*]}" "$@" "$src" "$(target):$dst" ;;
  get)    not_local; connect; [[ $# -ge 2 ]] || die "usage: nscc.sh get <remote> <local> [rsync options]"
          src="$1" dst="$2"; shift 2
          rsync -a --partial --info=progress2 -e "ssh ${SSH_OPTS[*]}" "$@" "$(target):$src" "$dst" ;;
  submit) connect; [[ $# -ge 1 && -f "$1" ]] || die "usage: nscc.sh submit <local script> [qsub options]"
          script="$1"; shift
          dir="$(r 'mkdir -p ~/.nscc-agent/jobs && cd ~/.nscc-agent/jobs && pwd')"
          remote="$dir/$(date +%Y%m%d-%H%M%S)-$(basename "$script")"
          if [[ "$NSCC_LOCAL" == 1 ]]; then cp "$script" "$remote"
          else scp -q "${SSH_OPTS[@]}" "$script" "$(target):$remote" || lost "upload failed"; fi
          proj=""; [[ -n "${NSCC_PROJECT:-}" ]] && proj="-P $NSCC_PROJECT"
          r "qsub $proj $* $remote" ;;
  jobs)   connect
          r "qstat -xu $NSCC_USER | awk 'NR<=5{print;next}{a[NR]=\$0}END{for(i=(NR>20?NR-14:6);i<=NR;i++)print a[i]}'" ;;
  status) connect; [[ $# -eq 1 ]] || die "usage: nscc.sh status <jobid>"
          r "qstat -fxw ${1%%.*} | grep -E '^ *(Job_Name|job_state|queue|comment|resources_used.walltime|Resource_List.walltime|Exit_status|Output_Path) ='" ;;
  tail)   connect; [[ $# -ge 1 ]] || die "usage: nscc.sh tail <remote file> [n]"
          r "tail -n ${2:-40} $1" ;;
  wait)   connect; [[ $# -ge 1 ]] || die "usage: nscc.sh wait <jobid> [log]"
          job="${1%%.*}"; log="${2:-}"
          while :; do
            state="$(r "qstat -fxw $job 2>/dev/null | awk '/job_state =/{print \$3}'")"
            [[ -n "$state" ]] || die "job $job not found"
            [[ "$state" == F ]] && break
            sleep "$NSCC_POLL"
          done
          info="$(r "qstat -fxw $job")"
          code="$(awk '/Exit_status =/{print $3}' <<<"$info")"
          [[ -n "$log" ]] || log="$(awk -F'= ' '/Output_Path =/{sub(/^[^:]*:/, "", $2); print $2}' <<<"$info")"
          echo "nscc: job $job finished, exit status ${code:-unknown}"
          grep -E '^ *(Job_Name|resources_used.walltime|comment) =' <<<"$info" || true
          if [[ -n "$log" ]]; then echo "--- $log"; r "tail -n 40 $log" || true; fi
          [[ "$code" == 0 ]] ;;
  close)  [[ "$NSCC_LOCAL" == 1 ]] && exit 0
          [[ -n "${NSCC_USER:-}" ]] || die "NSCC_USER is not set"
          ssh -O exit -o "ControlPath=$NSCC_SOCKET" "$(target)" 2>&1 || true ;;
  help|-h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)      die "unknown command '$cmd' (try: nscc.sh help)" ;;
esac
