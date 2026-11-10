#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Arshia Ghaf
# SPDX-License-Identifier: GPL-3.0-only
# Sourced by validate-preview.sh; tests replace host commands with synthetic fixtures.

canonical_executable() {
  (cd "$1/Contents/MacOS" && printf '%s/Baseline\n' "$(pwd -P)")
}

process_identity() {
  # comm is the executable path on macOS; lstart fences PID reuse.
  ps -ww -p "$1" -o lstart= -o comm=
}

require_app_stopped() {
  local executable processes process
  executable="$(canonical_executable "$1")" || return 1
  processes="$(ps -axww -o comm=)" || {
    echo "Could not inspect running apps; refusing replacement." >&2
    return 1
  }
  # A pipeline with grep -q can lose a match to SIGPIPE under pipefail.
  # Read the captured output directly so a found target always refuses admission.
  while IFS= read -r process; do
    if [[ "$process" == "$executable" ]]; then
      echo "Quit $1 after its current operations finish, then retry. No running app was stopped." >&2
      return 1
    fi
  done <<< "$processes"
  return 0
}

process_has_exited() {
  # ps failure can mean unreadable process state. Only ESRCH proves absence;
  # permission errors, a live process and an unavailable probe remain uncertain.
  node -e '
    const pid = Number(process.argv[1]);
    if (!Number.isSafeInteger(pid) || pid <= 0) process.exit(1);
    try {
      process.kill(pid, 0);
      process.exit(1);
    } catch (error) {
      process.exit(error.code === "ESRCH" ? 0 : 1);
    }
  ' "$1"
}

confirm_preview_exit() {
  if process_has_exited "$PREVIEW_PID"; then
    wait "$PREVIEW_PID" 2>/dev/null || true
    PREVIEW_PID=""
    return 0
  fi
  echo "Preview exit could not be confirmed for PID $PREVIEW_PID; retaining ownership for inspection." >&2
  return 1
}

stop_owned_preview() {
  [[ -n "${PREVIEW_PID:-}" ]] || return 0
  local current
  current="$(process_identity "$PREVIEW_PID")" || { confirm_preview_exit && return 0; return 1; }
  if [[ "$current" != "$PREVIEW_IDENTITY" ]]; then
    echo "Preview process identity changed; refusing to signal PID $PREVIEW_PID." >&2
    PREVIEW_PID=""
    return 1
  fi
  kill -TERM "$PREVIEW_PID" || return 1
  for _ in {1..40}; do
    current="$(process_identity "$PREVIEW_PID")" || { confirm_preview_exit && return 0; return 1; }
    if [[ "$current" != "$PREVIEW_IDENTITY" ]]; then
      PREVIEW_PID=""
      return 0
    fi
    sleep 0.25
  done
  echo "Owned preview is still running; quit it before retrying. No force signal was sent." >&2
  return 1
}

smoke_launch_app() {
  local app_path="$1" label="$2" keep_running="${3:-false}" executable current launch_log
  launch_log="$TRANSACTION_DIR/preview-mounted.log"
  if [[ "$keep_running" == true ]]; then launch_log="$TRANSACTION_DIR/preview-installed.log"; fi
  executable="$(canonical_executable "$app_path")" || return 1
  require_app_stopped "$app_path" || return 1
  echo "Launching $label"
  "$executable" >"$launch_log" 2>&1 &
  PREVIEW_PID=$!
  PREVIEW_IDENTITY=""
  # The child may still be between fork and exec when the first probe runs.
  # Wait only for this PID to report the intended executable, never a namesake.
  for _ in {1..40}; do
    current="$(process_identity "$PREVIEW_PID")" || return 1
    if [[ "$current" == *" $executable" ]]; then
      PREVIEW_IDENTITY="$current"
      break
    fi
    sleep 0.05
  done
  [[ -n "$PREVIEW_IDENTITY" ]] || return 1
  sleep 2
  current="$(process_identity "$PREVIEW_PID")" || return 1
  [[ "$current" == "$PREVIEW_IDENTITY" ]] || return 1
  echo "Smoke launch succeeded for $label (PID $PREVIEW_PID)."
  if [[ "$keep_running" == true ]]; then
    PREVIEW_PID=""
  else
    stop_owned_preview || return 1
  fi
}

bundle_property() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

bundle_hash() {
  codesign -d --verbose=4 "$1" 2>&1 | awk -F= '/^CDHash=/ {print $2}'
}

verify_preview_bundle() {
  local app_path="$1" reference="$2" key expected actual
  [[ -d "$app_path" && ! -L "$app_path" && -x "$app_path/Contents/MacOS/Baseline" ]] || return 1
  codesign --verify --deep --strict "$app_path" || return 1
  for key in CFBundleIdentifier CFBundleExecutable CFBundleShortVersionString CFBundleVersion; do
    expected="$(bundle_property "$reference" "$key")" || return 1
    actual="$(bundle_property "$app_path" "$key")" || return 1
    [[ -n "$expected" && "$actual" == "$expected" ]] || return 1
  done
  [[ "$(bundle_property "$app_path" CFBundleIdentifier)" == com.arshiaghaf.baseline ]] || return 1
  [[ "$(bundle_property "$app_path" CFBundleExecutable)" == Baseline ]] || return 1
  expected="$(bundle_hash "$reference")" || return 1
  actual="$(bundle_hash "$app_path")" || return 1
  [[ -n "$expected" && "$actual" == "$expected" ]] || return 1
}

install_preview() {
  local source="$1" app_name staged
  app_name="$(basename "$INSTALL_PATH")"
  staged="$TRANSACTION_DIR/staged/$app_name"
  mkdir "$TRANSACTION_DIR/staged" || return 1
  verify_preview_bundle "$source" "$source" || return 1
  ditto "$source" "$staged" || return 1
  verify_preview_bundle "$staged" "$source" || return 1
  if [[ -e "$INSTALL_PATH" || -L "$INSTALL_PATH" ]]; then
    [[ -d "$INSTALL_PATH" && ! -L "$INSTALL_PATH" ]] || return 1
    require_app_stopped "$INSTALL_PATH" || return 1
    # The verified replacement is ready. Do not retain an old-app rollback copy.
    rm -rf "$INSTALL_PATH" || return 1
    [[ ! -e "$INSTALL_PATH" && ! -L "$INSTALL_PATH" ]] || return 1
  fi
  # Pass the parent directory so mv -n refuses an existing app rather than
  # nesting the staged bundle inside a concurrently created target directory.
  mv -n "$staged" "$(dirname "$INSTALL_PATH")/" || return 1
  [[ ! -e "$staged" ]] || return 1
  verify_preview_bundle "$INSTALL_PATH" "$source" || return 1
  smoke_launch_app "$INSTALL_PATH" "installed preview app" true || return 1
}

cleanup_preview_install() {
  stop_owned_preview || return 1
  echo "Preview staging and launch log: $TRANSACTION_DIR"
  if [[ -d "$TRANSACTION_DIR/staged/$(basename "$INSTALL_PATH")" ]]; then
    echo "Staged replacement retained. If promotion failed, the installation may be absent; inspect before retrying."
  fi
}

finish_preview() {
  local result="$1"
  trap - EXIT
  if ! cleanup_preview; then
    if [[ "$result" == 0 ]]; then result=1; fi
  fi
  exit "$result"
}
