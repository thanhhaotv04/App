#pragma once

#include <stddef.h>
#include <stdint.h>

// GOOUUU ESP32-S3 N16R8 + ST7735. Keep GPIO26-37 for flash/Octal PSRAM,
// GPIO19/20 for native USB, and GPIO43/44 for the onboard CH340 UART.
constexpr uint8_t TFT_SCLK = 21;
constexpr uint8_t TFT_MOSI = 47;
constexpr uint8_t TFT_CS = 41;
constexpr uint8_t TFT_DC = 40;
// TFT reset only: never wire this signal to the board's EN/RST pin.
// GPIO45 is a strap pin; verify VDD_SPI is fixed at 3.3 V before reuse on
// another board. Do not drive an external pull-up on this pin at boot.
constexpr uint8_t TFT_RST = 45;
constexpr int8_t TFT_MISO = -1;
constexpr uint32_t TFT_SPI_HZ = 10000000;
constexpr uint8_t BUTTON_WIFI = 38;
constexpr uint8_t BUTTON_BLUETOOTH = 39;
constexpr uint8_t BUTTON_MENU = 0;  // BOOT: release before power-on/reset.

constexpr bool peripheralPinAllowed(uint8_t pin) {
  return (pin <= 21 || (pin >= 38 && pin <= 48)) &&
         pin != 3 && pin != 19 && pin != 20 &&
         pin != 43 && pin != 44 && pin != 46;
}

constexpr bool hardwarePinsValid(const uint8_t *pins, size_t count,
                                 uint64_t used = 0) {
  return count == 0 ||
      (peripheralPinAllowed(pins[0]) && (used & (1ULL << pins[0])) == 0 &&
       hardwarePinsValid(pins + 1, count - 1, used | (1ULL << pins[0])));
}

constexpr uint8_t PERIPHERAL_PINS[] = {
    TFT_SCLK, TFT_MOSI, TFT_CS, TFT_DC, TFT_RST,
    BUTTON_WIFI, BUTTON_BLUETOOTH, BUTTON_MENU};
static_assert(hardwarePinsValid(PERIPHERAL_PINS, sizeof(PERIPHERAL_PINS)),
              "TFT/buttons must have unique pins outside flash, PSRAM, USB and UART");
