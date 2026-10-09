// Personal QR bitmaps belong in the ignored qr_assets_private.h file.
#pragma once
#include <Arduino.h>

#if __has_include("qr_assets_private.h")
#include "qr_assets_private.h"
#else
constexpr uint8_t BANK_QR_SIZE = 0;
const uint8_t BANK_QR_BITS[] PROGMEM = {0};
constexpr uint8_t PROFILE_QR_SIZE = 0;
const uint8_t PROFILE_QR_BITS[] PROGMEM = {0};
#endif

#ifndef BANK_QR_CAPTION
#define BANK_QR_CAPTION "Scan to pay"
#endif
