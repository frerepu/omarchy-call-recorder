#!/usr/bin/env bash
# Stop a running take before the machine suspends.
#
# Suspend is an event, not a state: logind broadcasts PrepareForSleep(true) on
# every path into sleep (lid, idle, menu, `systemctl suspend`). A `delay`
# inhibitor held until the recorder confirms it has stopped gives the GStreamer
# pipeline time to flush and close both FLAC files, so a forgotten take survives
# the suspend as a playable recording instead of a truncated one.
#
# Protocol with Service.qml, over this process's stdout/stdin:
#   stdout "sleep"  -> a suspend is imminent; stop recording now
#   stdin  "ack"    -> the pipeline has stopped; the inhibitor can be released
#
# Only the pipeline stop is waited for, never the MP3 export. The export is a
# post-process that takes far longer than logind's window and is picked up again
# after resume, whereas an unflushed FLAC is unrecoverable.
#
# Inhibitors release only when the holding process exits, so each pass takes a
# fresh one rather than holding one across the machine's whole uptime.

set -u

SLEEP_TOKEN="sleep"
ACK_TOKEN="ack"
# Generous enough for a pipeline stop, far below logind's InhibitDelayMaxSec
# (15s here, 5s on stock systemd), which ends the wait regardless.
ACK_TIMEOUT_S="${CALL_RECORDER_ACK_TIMEOUT_S:-5}"
RETRY_S=5

# Quickshell kills only its direct child when a plugin unloads, so without this
# the monitor, its gdbus and its inhibitor would outlive the plugin. setsid
# makes $$ the process-group id; the watcher kills the whole group once stdin
# closes, which is exactly when the owning Process goes away.
#
# The watcher also relays the panel's ack into an anonymous pipe opened
# read-write, so it never blocks and never reaches EOF. systemd-inhibit passes
# stdin through but closes other descriptors, so the pipe is what each inhibited
# wait reads as its stdin.
exec 4<> <(:)

(
  while IFS= read -r line; do
    [ "$line" = "$ACK_TOKEN" ] && printf '%s\n' "$ACK_TOKEN" >&4
  done
  kill -KILL -- "-$$"
) <&0 &

wait_for_sleep() {
  # -u so a match leaves sed as soon as it is read instead of sitting in a block
  # buffer until after the machine has already suspended.
  exec 3< <(gdbus monitor --system --dest org.freedesktop.login1 \
    --object-path /org/freedesktop/login1 2>/dev/null)
  local gdbus_pid=$!
  local matched
  matched="$(sed -une '/PrepareForSleep (true,/{s/.*/x/p;q}' <&3)"
  kill "$gdbus_pid" 2>/dev/null
  exec 3<&-

  # gdbus died without a suspend ever arriving: treat as failure so the outer
  # loop backs off rather than spinning on a broken dbus.
  [ -n "$matched" ] || exit 1

  # Drop any ack left over from an earlier cycle, so only this cycle's ack can
  # end the wait below.
  while read -r -t 0.05 _; do :; done

  printf '%s\n' "$SLEEP_TOKEN"
  read -r -t "$ACK_TIMEOUT_S" _
  exit 0
}

if [ "${1:-}" = "--wait-once" ]; then
  wait_for_sleep
fi

export -f wait_for_sleep 2>/dev/null || true

while :; do
  if ! command -v gdbus >/dev/null 2>&1 || ! command -v systemd-inhibit >/dev/null 2>&1; then
    # Without these the guard is inert; idle rather than spin.
    sleep 300
    continue
  fi

  systemd-inhibit --what=sleep --mode=delay \
    --who="Call Recorder" \
    --why="Stopping the recording before sleep" \
    "$0" --wait-once <&4 || sleep "$RETRY_S"
done
