#!/usr/bin/env bash

# Bash strict mode
set -euo pipefail
IFS=$'\n\t'

# DEFAULTS
# The path to the source files
export DUPLICACY_REPOSITORY_PATH="${DUPLICACY_REPOSITORY_PATH:-$(pwd -P)}"
# The path to the dotenv file for this script
export DUPLICACY_ENV_FILE="${DUPLICACY_ENV_FILE:-${DUPLICACY_REPOSITORY_PATH}/.duplicacy/.env}"
# Set to 'true' to enable the Volume Shadow Copy service (Windows and macOS using APFS only)
export DUPLICACY_VSS="${DUPLICACY_VSS:-false}"
# Execute the script only when connected to the specified Wi-Fi SSID
export DUPLICACY_SSID="${DUPLICACY_SSID:-}"
# Number of seconds to wait
export DUPLICACY_TIMEOUT="${DUPLICACY_TIMEOUT:-300}"
# Number of uploading threads
export DUPLICACY_THREADS="${DUPLICACY_THREADS:-4}"
# Extra storage (ex: B2)
export DUPLICACY_EXTRA_STORAGE="${DUPLICACY_EXTRA_STORAGE:-}"
# The Slack webhook used for posting messages
export SLACK_ALERTS_WEBHOOK="${SLACK_ALERTS_WEBHOOK:-}"
# The webhook used for healthchecks (HealthChecks.io)
export HEALTHCHECKS_URL="${HEALTHCHECKS_URL:-}"
# Export PATH if needed by scripts that do not load the entire environment
export PATH="${PATH}:/bin:/sbin:/usr/bin:/usr/local/bin:/usr/local/opt/coreutils/libexec/gnubin"

# Log format (ex: log INFO Message)
# Levels: DEBUG, INFO, WARN, ERROR
log(){
  local type=${1:?Must specify the type first}; shift
  echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') ${type} DUPLICACY_SCRIPT ${*:-}"
}

# Check if command exists
is_cmd(){
  command -v "$@" >/dev/null 2>&1
}

# Load .env file
load_dotenv(){
  if [[ -s "$DUPLICACY_ENV_FILE" ]]; then
    # shellcheck disable=1090
    . "$DUPLICACY_ENV_FILE"
  fi
}

# Post message to Slack webhook
notify(){
  if [[ -n "$SLACK_ALERTS_WEBHOOK" ]]; then
    log INFO 'Notify Slack'
    /usr/bin/curl --silent --output /dev/null --show-error --fail --request POST \
      --header 'Content-type: application/json' \
      --data "{\"text\":\"${1:?Must specify the message}\"}" \
      "$SLACK_ALERTS_WEBHOOK"
  fi
}

# Ensure that the repository is initialized
check_repository_initialized(){
  if [[ ! -s "${DUPLICACY_REPOSITORY_PATH}/.duplicacy/preferences" ]]; then
    log ERROR 'The repository is not initialized'; exit 1
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
  if [[ -z "$DUPLICACY_SSID" ]]; then return; fi
  if [[ ! -x /System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport ]]; then return; fi

  if [[ "$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I | awk -F': ' '/AirPort/{print $2}')" == 'Off' ]]; then
    log INFO 'The backup will be skipped because Wi-Fi is Off (probably sleeping)'; exit 2
  elif [[ "$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I | awk -F': ' '/ SSID/{print $2}')" != "$DUPLICACY_SSID" ]]; then
    log INFO 'The backup will be skipped for the current Wi-Fi SSID'; exit 2
  fi
}

# This is here because of tmutil timeout errors (`tmutil localsnapshot` is used for VSS - Shadow Copy)
wait_for_tmutil(){
  if ! is_cmd tmutil; then return; fi

  until tmutil listlocalsnapshots / >/dev/null 2>&1 || [[ $((DUPLICACY_TIMEOUT--)) == 0 ]]; do
    log INFO 'Waiting for tmutil...'; sleep 5
  done

  if ! tmutil listlocalsnapshots / >/dev/null 2>&1; then
    log ERROR 'Tmutil did not respond in a timely manner'; exit 1
  fi
}

# Initialize script
do_initialize(){
  # Initialize trap
  trap 'clean_up $?' EXIT HUP INT QUIT TERM

  # Load settings
  load_dotenv

  # Log everything to file
  mkdir -p "$(dirname "$DUPLICACY_LOG_FILE")"
  exec > >(tee -a "$DUPLICACY_LOG_FILE") 2>&1

  # Sanity checks
  check_repository_initialized
  check_process_running
  check_ssid

  # Wait for other processes
  wait_for_tmutil
}

# Concatenate command
concatenate_duplicacy_cmd(){
  duplicacy_cmd='duplicacy -log backup -stats'

  # Use `caffeinate` command if available
  if is_cmd caffeinate; then
    duplicacy_cmd="caffeinate -s ${duplicacy_cmd}"
  fi

  # Enable the Volume Shadow Copy service
  if [[ "$DUPLICACY_VSS" == 'true' ]]; then
    duplicacy_cmd="${duplicacy_cmd} -vss"
  fi

  # Use the specified extra storage
  if [[ -n "$DUPLICACY_EXTRA_STORAGE" ]]; then
    duplicacy_cmd="${duplicacy_cmd} -storage ${DUPLICACY_EXTRA_STORAGE}"
  fi
}

# Run backup (use caffeinate command if it exists to prevent sleeping on MacOS)
do_backup(){
  # The path to the log file for this script
  export DUPLICACY_LOG_FILE="${DUPLICACY_REPOSITORY_PATH}/.duplicacy/logs/backup.log"
  # The path to the file containing the pid of the running process
  export DUPLICACY_PID_FILE="${DUPLICACY_REPOSITORY_PATH}/.duplicacy/running.pid"

  # Initialize script
  do_initialize

  # Concatenate command
  concatenate_duplicacy_cmd

  # Run
  log INFO 'Start backup'
  eval "${duplicacy_cmd:-}"
}

# Prune local storage
prune_local_snapshots(){
  # -keep <n:m> [+]   keep 1 snapshot every n days for snapshots older than m days
  # Keep no snapshots older than 1825 days
  # Keep 1 snapshot every 30 days if older than 180 days
  # Keep 1 snapshot every 7 days if older than 30 days
  # Keep 1 snapshot every 1 day if older than 7 days
  log INFO 'Prune local snapshots'
  duplicacy -log prune -all -keep 0:1825 -keep 30:180 -keep 7:30 -keep 1:7 || notify "Prune local snapshots failed with exit code '$?'. Skipping..."
}

# Prune remote storage
prune_remote_snapshots(){
  if [[ -n "$DUPLICACY_EXTRA_STORAGE" ]]; then
    log INFO 'Prune remote snapshots'
    duplicacy -log prune -all -keep 0:1825 -keep 30:180 -keep 7:30 -keep 1:7 -storage "$DUPLICACY_EXTRA_STORAGE" || notify "Prune remote snapshots failed with exit code '$?'. Skipping..."
  fi
}

# Copy to external storage
copy_snapshots(){
  if [[ -n "$DUPLICACY_EXTRA_STORAGE" ]]; then
    log INFO 'Copy snapshots'
    duplicacy -log copy -to "$DUPLICACY_EXTRA_STORAGE" -threads "$DUPLICACY_THREADS" || notify "Copy snapshots failed with exit code '$?'. Skipping..."
  fi
}

# Run maintenance
do_maintenance(){
  # The path to the log file for this script
  export DUPLICACY_LOG_FILE="${DUPLICACY_REPOSITORY_PATH}/.duplicacy/logs/maintenance.log"
  # The path to the file containing the pid of the running process
  export DUPLICACY_PID_FILE="${DUPLICACY_REPOSITORY_PATH}/.duplicacy/running-maintenance.pid"

  # Initialize script
  do_initialize

  # Copy to external storage
  copy_snapshots

  # Prune local storage
  prune_local_snapshots

  # Prune remote storage
  prune_remote_snapshots

  # Notify HealthChecks.io
  if [[ -n "$HEALTHCHECKS_URL" ]]; then
    curl --silent --output /dev/null --show-error --fail --retry 3 "$HEALTHCHECKS_URL"
  fi

  log INFO 'MAINTENANCE_END'
}

# Clean-up and notify
clean_up(){
  # Exit codes: 1 - Errors; 2 - Skipped; 3 - Already running
  # If it's already running, just clean exit directly
  if [[ ${1:-0} == 3 ]]; then return; fi

  # Remove the PID file
  if [[ -s "$DUPLICACY_PID_FILE" ]]; then rm -f "$DUPLICACY_PID_FILE"; fi

  # If it's skipped, just clean exit (after cleaning the PID file)
  if [[ ${1:-0} == 2 ]]; then return; fi

  # For all other cases notify failure (after cleaning the PID file)
  if [[ ${1:-0} != 0 ]]; then
    log ERROR "Backup Failed with exit code '${1}'"
    notify "Backup Failed on $(hostname) ($(date))"
  fi
}

# Script
main(){
  # Process command line arguments
  local -r cmd="${1:-backup}"; shift

  # Go to the repository path
  cd "$DUPLICACY_REPOSITORY_PATH" || exit 1

  case "$cmd" in
    backup)
      # Backup
      do_backup
      ;;
    maintenance)
      # Maintenance
      do_maintenance
      ;;
    *)
      # Default
      log ERROR "'${cmd}' is not recognized as a valid command"; exit 1
      ;;
  esac
}

# Run
main "${@:-}"
