#!/usr/bin/env bash
# Run in the owned emulator session after installing debug + AndroidTest APKs.
set -euo pipefail
serial=${1:-emulator-5580}
[[ "$serial" =~ ^emulator-[0-9]+$ ]] || { echo 'This fixture test is restricted to an emulator' >&2; exit 1; }
artifacts=${2:-/home/mayon/nix-dotfiles/.work/r50/android}
run="$artifacts/run/phase2"
mkdir -p "$run" "$artifacts/shots/round2"
adb -s "$serial" shell run-as dev.mayon.timetable rm -f files/reminder-ready.txt files/reminder-delivered.txt files/reminder-captured.txt
adb -s "$serial" shell am instrument -w -r -e clockHandshake true -e class 'dev.mayon.timetable.ReminderTest#realAlarmFiresExactlyOnceAfterHostClockAdvance' dev.mayon.timetable.test/androidx.test.runner.AndroidJUnitRunner > "$run/reminder-instrumentation.log" 2>&1 &
runner_pid=$!
for attempt in $(seq 1 90); do
  due=$(adb -s "$serial" shell run-as dev.mayon.timetable cat files/reminder-ready.txt 2>/dev/null | tr -d '\r') || true
  [[ "$due" =~ ^[0-9]+$ ]] && break
  sleep 1
done
[[ "$due" =~ ^[0-9]+$ ]]
adb -s "$serial" shell date -s "@$((due - 6))" > "$run/alarm-clock-advance.txt"
adb -s "$serial" shell dumpsys alarm > "$run/alarm-scheduled.txt"
for attempt in $(seq 1 60); do
  if adb -s "$serial" shell run-as dev.mayon.timetable test -f files/reminder-delivered.txt; then break; fi
  sleep 1
done
adb -s "$serial" shell run-as dev.mayon.timetable cat files/reminder-delivered.txt > "$run/alarm-delivered.txt"
adb -s "$serial" shell dumpsys notification --noredact > "$run/notification-delivered.txt"
for theme in dark light; do
  if [ "$theme" = dark ]; then night=yes; else night=no; fi
  adb -s "$serial" shell cmd uimode night "$night"
  adb -s "$serial" shell cmd statusbar expand-notifications
  sleep 1
  adb -s "$serial" exec-out screencap -p > "$artifacts/shots/round2/round2-$theme-reminder.png"
  adb -s "$serial" shell cmd statusbar collapse
done
adb -s "$serial" shell run-as dev.mayon.timetable touch files/reminder-captured.txt
wait "$runner_pid"
grep -q 'OK (1 test)' "$run/reminder-instrumentation.log"
echo 'PASS: one real AlarmManager notification observed and captured during the same instrumentation'
