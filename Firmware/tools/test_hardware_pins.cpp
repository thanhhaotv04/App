#include "../include/hardware_pins.h"

#include <cassert>
#include <cstdio>

int main() {
  assert(hardwarePinsValid(PERIPHERAL_PINS, sizeof(PERIPHERAL_PINS)));
  const uint8_t duplicate[] = {TFT_SCLK, TFT_SCLK};
  assert(!hardwarePinsValid(duplicate, sizeof(duplicate)));
  for (uint8_t pin = 26; pin <= 37; ++pin) {
    assert(!hardwarePinsValid(&pin, 1));
  }
  const uint8_t reserved[] = {3, 19, 20, 22, 25, 43, 44, 46, 49, 255};
  for (uint8_t pin : reserved) assert(!hardwarePinsValid(&pin, 1));
  assert(TFT_MISO == -1);
  assert(TFT_SPI_HZ == 10000000);
  std::puts("Hardware pins: unique wiring; flash/PSRAM/USB/UART pins rejected");
}
