#!/usr/bin/env bash

# Bash strict mode
set -euo pipefail
IFS=$'\n\t'

# DEFAULTS
# The path to the source files
export DUPLICACY_REPOSITORY_PATH="${DUPLICACY_REPOSITORY_PATH:-$HOME}"
# The path to the .env file, which contains environment variables that will be loaded by this scripts
export DUPLICACY_ENV_FILE="${DUPLICACY_ENV_FILE:-${DUPLICACY_REPOSITORY_PATH}/.duplicacy/.env}"
# The path to the log file for this script
export DUPLICACY_LOG_FILE="${DUPLICACY_LOG_FILE:-${DUPLICACY_REPOSITORY_PATH}/.duplicacy/logs/backup.log}"
# The path to the file containing the pid of the running process
export DUPLICACY_PID_FILE="${DUPLICACY_PID_FILE:-${DUPLICACY_REPOSITORY_PATH}/.duplicacy/running.pid}"
# Set to 'true' to enable the Volume Shadow Copy service (Windows and macOS using APFS only)
export DUPLICACY_VSS="${DUPLICACY_VSS:-false}"
# Execute the script only when connected to the specified Wi-Fi SSID
export DUPLICACY_SSID="${DUPLICACY_SSID:-}"
# Number of seconds to wait
export DUPLICACY_TIMEOUT="${DUPLICACY_TIMEOUT:-300}"
# Number of uploading threads
export DUPLICACY_THREADS="${DUPLICACY_THREADS:-10}"
# Extra storage (ex: B2)
export DUPLICACY_EXTRA_STORAGE="${DUPLICACY_EXTRA_STORAGE:-}"
# Set to 'true' to clone the snapshots to another storage
export DUPLICACY_CLONE_BACKUPS="${DUPLICACY_CLONE_BACKUPS:-false}"
# Set to 'true' to prune the backups
export DUPLICACY_PRUNE_BACKUPS="${DUPLICACY_PRUNE_BACKUPS:-false}"
# The Slack webhook used for posting messages
export SLACK_ALERTS_WEBHOOK="${SLACK_ALERTS_WEBHOOK:-}"
# Export PATH if needed by scripts that do not load the entire environment
export PATH="${PATH}:/bin:/sbin:/usr/bin:/usr/local/bin:/usr/local/opt/coreutils/libexec/gnubin"

# Log format (ex: log INFO Message)
log(){
  local type=${1:?Must specify the type first}; shift
  echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') ${type} DUPLICACY_SCRIPT ${*:-}"
}

# Post message to Slack webhook
notify(){
  if [[ -n "$SLACK_ALERTS_WEBHOOK" ]]; then
    /usr/bin/curl --silent --output /dev/null --show-error --fail --request POST \
      --header 'Content-type: application/json' \
      --data "{\"text\":\"${1:?Must specify the message}\"}" \
      "$SLACK_ALERTS_WEBHOOK"
  fi
}

# Check if the process is already running
check_process_running(){
  if [ -f "$DUPLICACY_PID_FILE" ]; then
    PID=$(cat "$DUPLICACY_PID_FILE")
    if ps -p "$PID" >/dev/null 2>&1; then
      log WARN 'Process already running'; exit 3
    else
      if ! echo $$ > "$DUPLICACY_PID_FILE"; then
        log ERROR 'Could not create PID file'; exit 1
      fi
    fi
  else
    if ! echo $$ > "$DUPLICACY_PID_FILE"; then
      log ERROR 'Could not create PID file'; exit 1
    fi
  fi
}

# Execute the script only when connected to the specified Wi-Fi SSID
check_ssid(){
  if [[ -n "$DUPLICACY_SSID" ]] && \
     [[ -x /System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport ]] && \
     [[ "$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I | awk -F': ' '/ SSID/{print $2}')" != "$DUPLICACY_SSID" ]]
  then
    log INFO 'The backup will be skipped for the current Wi-Fi SSID'; exit 2
  fi
}

# This is here because of tmutil timeout errors (`tmutil localsnaphost` is
# used for VSS - Shadow Copy)
wait_for_tmutil(){
  if [[ "$DUPLICACY_VSS" == 'false' ]]; then return; fi

  if ! command -v tmutil >/dev/null 2>&1 ; then return; fi

  log INFO 'Waiting for tmutil...'
  until tmutil listlocalsnapshots / >/dev/null 2>&1 || [[ $((DUPLICACY_TIMEOUT--)) == 0 ]]; do
    sleep 1
  done

  if ! tmutil listlocalsnapshots / >/dev/null 2>&1; then
    log ERROR 'Tmutil did not respond in a timely manner'; exit 1
  fi
}

# Run backup
do_backup(){
  cd "$DUPLICACY_REPOSITORY_PATH" || exit 1
  if [[ "$DUPLICACY_VSS" == 'true' ]]; then
    duplicacy -log backup -stats -vss
  else
    duplicacy -log backup -stats
  fi
}

prune_backups(){
  if [[ "$DUPLICACY_PRUNE_BACKUPS" != 'true' ]]; then return; fi

  cd "$DUPLICACY_REPOSITORY_PATH" || exit 1
  # -keep <n:m> [+]   keep 1 snapshot every n days for snapshots older than m days
  # Keep snapshots for 5 years, monlthy for 6 months, weekly for a month, and daily for a week
  duplicacy -log prune -all -keep 0:1825 -keep 30:180 -keep 7:30 -keep 1:7
  if [[ -n "$DUPLICACY_EXTRA_STORAGE" ]]; then
    duplicacy -log prune -all -keep 0:1825 -keep 30:180 -keep 7:30 -keep 1:7 -storage "$DUPLICACY_EXTRA_STORAGE"
  fi
  log INFO 'Finished pruning snapshots'
}

clone_snapshots(){
  if [[ "$DUPLICACY_CLONE_BACKUPS" != 'true' ]]; then return; fi

  if [[ -n "$DUPLICACY_EXTRA_STORAGE" ]]; then
    cd "$DUPLICACY_REPOSITORY_PATH" || exit 1
    duplicacy -log copy -to "$DUPLICACY_EXTRA_STORAGE" -threads "$DUPLICACY_THREADS"
    log INFO 'Finished copying snapshots'
  fi
}

# Clean-up and notify
clean_up() {
  if [[ -s "$DUPLICACY_PID_FILE" ]] && [[ ${1:-0} != 3 ]]; then
    rm -f "$DUPLICACY_PID_FILE"
  fi
  if [[ ${1:-0} != 0 ]]; then
    notify "Backup Failed on $(hostname) ($(date))"
  fi
}

# Script
main(){
  trap 'clean_up $?' EXIT HUP INT QUIT TERM

  # Ensure that the repository is initialized
  if [[ ! -s "${DUPLICACY_REPOSITORY_PATH}/.duplicacy/preferences" ]]; then
    log ERROR 'The repository is not initialized'; exit 1
  fi

  # Log everything to file
  mkdir -p "$(dirname "$DUPLICACY_LOG_FILE")"
  exec > >(tee -a "$DUPLICACY_LOG_FILE") 2>&1

  # Sanity checks
  check_process_running
  check_ssid

  # Wait for other processes
  wait_for_tmutil

  # Backup
  do_backup

  # Prune first and upload to a secondary storage after
  prune_backups
  clone_snapshots
}

main "${@:-}"
