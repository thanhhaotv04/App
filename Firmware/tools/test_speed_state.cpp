#include <cassert>
#include "../include/speed_state.h"
int main() {
  SpeedState state;
  assert(state.visible(0, true) == -1);
  state.update(42, 1000);
  assert(state.visible(1000, true) == 42);
  assert(state.visible(5999, true) == 42);
  assert(state.visible(6000, true) == -1);
  assert(state.visible(1001, false) == -1);
  state.update(0, 9000);
  assert(state.visible(9000, true) == 0);
  state.update(-1, 9001);
  assert(state.visible(9001, true) == -1);
  state.update(60, UINT32_MAX - 1000);
  assert(state.visible(999, true) == 60);
  assert(state.visible(5000, true) == -1);
}
