#pragma once
#include <stdint.h>

// All durations use monotonic milliseconds, independent of radio and wall time.
struct ClockTimers {
  bool stopwatchRunning = false;
  uint64_t stopwatchSaved = 0;
  uint64_t stopwatchStarted = 0;
  bool timerRunning = false;
  bool ringing = false;
  uint64_t timerDeadline = 0;

  uint64_t elapsed(uint64_t now) const {
    return stopwatchSaved + (stopwatchRunning ? now - stopwatchStarted : 0);
  }
  void toggleStopwatch(uint64_t now) {
    if (stopwatchRunning) stopwatchSaved = elapsed(now);
    else stopwatchStarted = now;
    stopwatchRunning = !stopwatchRunning;
  }
  void resetStopwatch() {
    stopwatchRunning = false;
    stopwatchSaved = 0;
  }
  void startTimer(uint64_t now, uint64_t duration) {
    timerDeadline = now + duration;
    timerRunning = true;
    ringing = false;
  }
  uint64_t remaining(uint64_t now) const {
    return timerRunning && timerDeadline > now ? timerDeadline - now : 0;
  }
  bool update(uint64_t now) {
    if (!timerRunning || now < timerDeadline) return false;
    timerRunning = false;
    ringing = true;
    return true;
  }
  void cancelTimer() { timerRunning = false; ringing = false; }
  static uint64_t remainingMinutes(uint64_t milliseconds) {
    return (milliseconds + 59999) / 60000;
  }
  static uint32_t secondsUntil(int hour, int minute, int second,
                               int targetHour, int targetMinute) {
    int delta = targetHour * 3600 + targetMinute * 60 -
                (hour * 3600 + minute * 60 + second);
    if (delta <= 0) delta += 86400;
    return static_cast<uint32_t>(delta);
  }
};
