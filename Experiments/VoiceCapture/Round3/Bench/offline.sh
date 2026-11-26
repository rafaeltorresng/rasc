#!/usr/bin/env bash
set -euo pipefail
probe="${1:?Path to the signed, prepared study fixture executable}"
device="${2:?Wi-Fi device, e.g. en0}"
out="${3:?Evidence path on disk}"
case "$(/usr/sbin/networksetup -getairportpower "$device")" in
  *": On") ;;
  *) printf '%s\n' 'Start this test with Wi-Fi on.' >&2; exit 2 ;;
esac
exec >"$out" 2>&1
restore() {
  /usr/sbin/networksetup -setairportpower "$device" on
  /usr/sbin/networksetup -getairportpower "$device"
}
trap restore EXIT
trap 'exit 130' HUP INT TERM
is_disconnected() {
  local state
  state="$(/usr/sbin/scutil --nwi)"
  grep -q "No IPv4 states found" <<< "$state" &&
    grep -q "No IPv6 states found" <<< "$state"
}
/usr/bin/curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 -o /dev/null https://example.com
printf '%s\n' 'Online control reached example.com.'
/usr/sbin/networksetup -setairportpower "$device" off
for _ in {1..20}; do
  if is_disconnected; then break; fi
  sleep 0.25
done
/usr/sbin/networksetup -getairportpower "$device"
if ! is_disconnected; then
  printf '%s\n' 'The OS still reports active network interfaces.'
  exit 2
fi
/usr/sbin/scutil --nwi | grep -E 'No IPv[46] states found|Network interfaces'
if /usr/bin/curl -fsS --noproxy '*' --connect-timeout 1 --max-time 2 -o /dev/null https://example.com; then
  printf '%s\n' 'External network control still reachable.'
  exit 2
else
  printf '%s\n' 'External network control unreachable.'
fi
for args in 'apple en-US en-clip.wav' 'apple pt-BR pt-clip.wav' 'ultra auto en-clip.wav pt-clip.wav' 'fluid auto en-clip.wav pt-clip.wav'; do
  /usr/bin/perl -e 'alarm shift; exec @ARGV' 35 "$probe" --benchmark $args
done
if ! is_disconnected; then
  printf '%s\n' 'An active interface returned. No disconnected result claimed.'
  exit 2
fi
printf '%s\n' 'No active IPv4 or IPv6 state after test.'
