#include "../include/clock_timers.h"
#include <cassert>
#include <cstdio>
#include <initializer_list>

int main() {
  ClockTimers shortRun;
  shortRun.toggleStopwatch(1000);
  shortRun.toggleStopwatch(31000);
  assert(!shortRun.stopwatchRunning && shortRun.elapsed(61000) == 30000);
  assert(shortRun.elapsed(61000) / 60000 == 0); // Paused under one minute.

  ClockTimers clock;
  const uint64_t start = 0xfffffff0ULL; // Cross the 32-bit millis boundary.
  clock.toggleStopwatch(start);
  clock.startTimer(start, 300000);
  assert(clock.elapsed(start + 61000) == 61000);
  assert(clock.remaining(start + 61000) == 239000);
  clock.toggleStopwatch(start + 61000);
  assert(clock.elapsed(start + 90000) == 61000);
  clock.toggleStopwatch(start + 90000);
  assert(clock.elapsed(start + 120000) == 91000);
  const bool earlyExpiry = clock.update(start + 299999);
  assert(!earlyExpiry);
  const bool expired = clock.update(start + 300000);
  assert(expired && clock.ringing);
  const bool repeatedExpiry = clock.update(start + 300001);
  assert(!repeatedExpiry);
  assert(clock.elapsed(start + 300001) == 271001); // Timer never stops stopwatch.
  clock.cancelTimer();
  assert(!clock.ringing && clock.remaining(start + 400000) == 0);
  clock.resetStopwatch();
  assert(!clock.stopwatchRunning && clock.elapsed(start + 500000) == 0);
  for (uint64_t minutes : {5ULL, 15ULL, 30ULL, 60ULL}) {
    clock.startTimer(start, minutes * 60000);
    assert(ClockTimers::remainingMinutes(clock.remaining(start)) == minutes);
    const bool presetExpired = clock.update(start + minutes * 60000);
    assert(presetExpired);
  }
  assert(ClockTimers::remainingMinutes(60001) == 2);
  assert(ClockTimers::remainingMinutes(60000) == 1);
  assert(ClockTimers::remainingMinutes(1) == 1);
  assert(ClockTimers::remainingMinutes(0) == 0);
  assert(ClockTimers::secondsUntil(9, 0, 30, 9, 5) == 270);
  assert(ClockTimers::secondsUntil(23, 59, 30, 0, 0) == 30);
  assert(ClockTimers::secondsUntil(9, 30, 0, 9, 30) == 86400);
  assert(ClockTimers::secondsUntil(10, 0, 0, 9, 30) == 84600);
  std::puts("Clock timers: pause/resume/reset, concurrent operation, wrap, presets, expiry and at-time passed");
}
