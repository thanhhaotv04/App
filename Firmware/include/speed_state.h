#pragma once
#include <stdint.h>

struct SpeedState {
  int kmh = -1;
  uint32_t receivedAt = 0;
  void update(int value, uint32_t now) { kmh = value; receivedAt = now; }
  int visible(uint32_t now, bool connected) const {
    return connected && static_cast<uint32_t>(now - receivedAt) < 5000 ? kmh : -1;
  }
};
