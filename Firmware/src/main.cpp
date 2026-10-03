#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>
#include <Arduino.h>
#include <ArduinoJson.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <SPI.h>
#include <WebServer.h>
#include <WiFi.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <sys/time.h>
#include <time.h>

#include "secrets.h"

// GOOUUU ESP32-S3 + 1.8-inch ST7735 128x160 wiring.
constexpr uint8_t TFT_SCLK = 21;
constexpr uint8_t TFT_MOSI = 47;
constexpr uint8_t TFT_CS = 41;
constexpr uint8_t TFT_DC = 40;
constexpr uint8_t TFT_RST = 45;
constexpr int8_t TFT_MISO = -1;
constexpr uint8_t BUTTON_WIFI = 38;
constexpr uint8_t BUTTON_BLUETOOTH = 39;
constexpr uint8_t BUTTON_MENU = 0;  // BOOT strap: release before reset/upload.

constexpr char SERVICE_UUID[] = "7e6d0001-5b1a-4d8f-9a2c-320001000001";
constexpr char COMMAND_UUID[] = "7e6d0002-5b1a-4d8f-9a2c-320001000002";
constexpr char BLE_NAME[] = "ESP32-NavRide";
constexpr char FIRMWARE_VERSION[] = "1.3.13";
constexpr char SETUP_SSID[] = "ESP32-NavRide-Setup";
constexpr char SETUP_PASSWORD[] = "monitor1234";
constexpr uint32_t WIFI_TIMEOUT_MS = 12000;
constexpr uint32_t DRAW_INTERVAL_MS = 1000;
constexpr uint32_t POPUP_DURATION_MS = 8000;
constexpr uint32_t DETAILS_DURATION_MS = 10000;
constexpr uint32_t MENU_TIMEOUT_MS = 15000;
constexpr uint32_t BUTTON_DEBOUNCE_MS = 60;
constexpr uint32_t STATUS_BLINK_MS = 500;
constexpr uint32_t NAVIGATION_BLINK_MS = 500;
constexpr uint32_t NAVIGATION_LINK_LOST_MS = 15000;
constexpr uint32_t MODE_SWITCH_DELAY_MS = 250;
constexpr int TURN_ARROW_SHOW_METERS = 2000;
constexpr int TURN_ARROW_BLINK_METERS = 1000;
constexpr int METERS_PER_KM = 1000;
constexpr bool distanceUsesMeters(int distanceMeters) {
  return distanceMeters < METERS_PER_KM;
}
static_assert(distanceUsesMeters(999) && !distanceUsesMeters(1000),
              "Show metres strictly below one kilometre");
constexpr bool showTurnAt(int distanceMeters) {
  return distanceMeters < TURN_ARROW_SHOW_METERS;
}
constexpr bool blinkTurnAt(int distanceMeters) {
  return distanceMeters < TURN_ARROW_BLINK_METERS;
}
static_assert(!showTurnAt(2000) && showTurnAt(1999) &&
                  !blinkTurnAt(1000) && blinkTurnAt(999),
              "Navigation thresholds must be strict at 2 km and 1 km");
constexpr int roundaboutVisibleDegrees(int magnitude, int exitNumber) {
  return magnitude < 55 ? (exitNumber >= 3 ? 305 : 55)
         : magnitude > 305 ? (exitNumber <= 1 ? 55 : 305)
                           : magnitude;
}
constexpr int roundaboutSweepDegrees(int angle, int exitNumber,
                                     bool clockwise) {
  return (clockwise ? 1 : -1) *
         roundaboutVisibleDegrees(clockwise ? angle + 180 : 180 - angle,
                                 exitNumber);
}
static_assert(roundaboutSweepDegrees(110, 1, false) == -70 &&
                  roundaboutSweepDegrees(0, 2, false) == -180 &&
                  roundaboutSweepDegrees(-110, 3, false) == -290,
              "Right-hand roundabout exits must progress counterclockwise");
constexpr size_t MAX_COMMAND_BYTES = 512;
constexpr long GMT_OFFSET_SECONDS = 7 * 60 * 60;
constexpr int DAYLIGHT_OFFSET_SECONDS = 0;

uint16_t COLOR_BACKGROUND = 0x0841;
uint16_t COLOR_PANEL = 0x18E3;
uint16_t COLOR_TEXT = ST77XX_WHITE;
uint16_t COLOR_ACCENT = 0x07FF;
uint16_t COLOR_OK = 0x07E0;
uint16_t COLOR_WAIT = 0xFFE0;
uint16_t COLOR_ERROR = 0xF800;

SPIClass tftSPI(FSPI);
Adafruit_ST7735 tft(&tftSPI, TFT_CS, TFT_DC, TFT_RST);
WebServer server(80);
Preferences preferences;

struct QueuedCommand {
  char payload[MAX_COMMAND_BYTES + 1];
};
QueueHandle_t commandQueue = nullptr;

NimBLEServer *bleServer = nullptr;
NimBLECharacteristic *bleStatus = nullptr;
bool httpStarted = false;
bool httpConfigured = false;
bool bleStarted = false;
volatile bool bleConnected = false;
bool observedBleConnected = false;
uint32_t bleDisconnectedAt = 0;
bool wifiConnected = false;
String activeMode = "setup";
String wifiSsid;
String wifiPassword;
String popupTitle;
String popupBody;
String popupKind;
String lastNavigationKey;
String navigationManeuver;
String navigationStreet;
int navigationDistanceMeters = 0;
int navigationExitNumber = 0;
int navigationTurnAngle = 999;  // OsmAnd angle; 999 means it was not supplied.
bool navigationVisible = false;
bool navigationOnScreen = false;
bool navigationArrowVisible = true;
uint32_t lastNavigationBlink = 0;
enum class MenuView : uint8_t { Closed, List, Info };
MenuView menuView = MenuView::Closed;
uint8_t menuSelection = 0;
uint32_t menuLastInput = 0;
bool lightTheme = false;
uint32_t popupUntil = 0;
uint32_t detailsUntil = 0;
uint32_t lastDraw = 0;
uint32_t wifiAttemptStarted = 0;
uint32_t pendingModeAt = 0;
String pendingMode;
bool pendingDefaultWifi = false;
bool clockFrameDrawn = false;
bool setupFrameDrawn = false;
String lastRenderedTime;
String lastRenderedDate;
String lastRenderedStatus;

struct ButtonState {
  uint8_t pin;
  bool stablePressed;
  bool lastRawPressed;
  uint32_t changedAt;
};

ButtonState wifiButton{BUTTON_WIFI, false, false, 0};
ButtonState bluetoothButton{BUTTON_BLUETOOTH, false, false, 0};
ButtonState menuButton{BUTTON_MENU, false, false, 0};

void showPopup(const String &kind, const String &title, const String &body);
void drawNavigation(const String &maneuver, int distanceMeters,
                    const String &street, int exitNumber = 0,
                    int turnAngle = 999);
void switchToBluetooth();
void switchToWifi(bool useDefaultCredentials = false);

void applyTheme(bool light) {
  lightTheme = light;
  COLOR_BACKGROUND = light ? 0xFFFF : 0x0841;
  COLOR_PANEL = light ? 0xE71C : 0x18E3;
  COLOR_TEXT = light ? 0x1082 : ST77XX_WHITE;
  COLOR_ACCENT = light ? 0x03AC : 0x07FF;
  COLOR_OK = light ? 0x0380 : 0x07E0;
  COLOR_WAIT = light ? 0xA2A0 : 0xFFE0;
  COLOR_ERROR = light ? 0xB000 : 0xF800;
}

bool clockValid() {
  return time(nullptr) > 1700000000;
}

void applyVietnamTimezone() {
  // POSIX signs are inverted: UTC-7 means local time is UTC+7.
  setenv("TZ", "UTC-7", 1);
  tzset();
}

void sendJson(const String &body, int code = 200) {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  server.send(code, "application/json", body);
}

char transliterateCodepoint(uint32_t codepoint) {
  switch (codepoint) {
    case 0x00C0: case 0x00C1: case 0x00C2: case 0x00C3: case 0x00C4: case 0x00C5: case 0x0100: case 0x0102: case 0x0104: case 0x01CD: case 0x01DE: case 0x01E0: case 0x01FA: case 0x0200: case 0x0202: case 0x0226: case 0x1E00: case 0x1EA0: case 0x1EA2: case 0x1EA4: case 0x1EA6: case 0x1EA8: case 0x1EAA: case 0x1EAC: case 0x1EAE: case 0x1EB0: case 0x1EB2: case 0x1EB4: case 0x1EB6: return 'A';
    case 0x00E0: case 0x00E1: case 0x00E2: case 0x00E3: case 0x00E4: case 0x00E5: case 0x0101: case 0x0103: case 0x0105: case 0x01CE: case 0x01DF: case 0x01E1: case 0x01FB: case 0x0201: case 0x0203: case 0x0227: case 0x1E01: case 0x1EA1: case 0x1EA3: case 0x1EA5: case 0x1EA7: case 0x1EA9: case 0x1EAB: case 0x1EAD: case 0x1EAF: case 0x1EB1: case 0x1EB3: case 0x1EB5: case 0x1EB7: return 'a';
    case 0x00C7: case 0x0106: case 0x0108: case 0x010A: case 0x010C: case 0x1E08: return 'C';
    case 0x00E7: case 0x0107: case 0x0109: case 0x010B: case 0x010D: case 0x1E09: return 'c';
    case 0x010E: case 0x0110: case 0x1E0A: case 0x1E0C: case 0x1E0E: case 0x1E10: case 0x1E12: return 'D';
    case 0x010F: case 0x0111: case 0x1E0B: case 0x1E0D: case 0x1E0F: case 0x1E11: case 0x1E13: return 'd';
    case 0x00C8: case 0x00C9: case 0x00CA: case 0x00CB: case 0x0112: case 0x0114: case 0x0116: case 0x0118: case 0x011A: case 0x0204: case 0x0206: case 0x0228: case 0x1E14: case 0x1E16: case 0x1E18: case 0x1E1A: case 0x1E1C: case 0x1EB8: case 0x1EBA: case 0x1EBC: case 0x1EBE: case 0x1EC0: case 0x1EC2: case 0x1EC4: case 0x1EC6: return 'E';
    case 0x00E8: case 0x00E9: case 0x00EA: case 0x00EB: case 0x0113: case 0x0115: case 0x0117: case 0x0119: case 0x011B: case 0x0205: case 0x0207: case 0x0229: case 0x1E15: case 0x1E17: case 0x1E19: case 0x1E1B: case 0x1E1D: case 0x1EB9: case 0x1EBB: case 0x1EBD: case 0x1EBF: case 0x1EC1: case 0x1EC3: case 0x1EC5: case 0x1EC7: return 'e';
    case 0x00CC: case 0x00CD: case 0x00CE: case 0x00CF: case 0x0128: case 0x012A: case 0x012C: case 0x012E: case 0x0130: case 0x01CF: case 0x0208: case 0x020A: case 0x1E2C: case 0x1E2E: case 0x1EC8: case 0x1ECA:
      return 'I';
    case 0x00EC: case 0x00ED: case 0x00EE: case 0x00EF: case 0x0129: case 0x012B: case 0x012D: case 0x012F: case 0x01D0: case 0x0209: case 0x020B: case 0x1E2D: case 0x1E2F: case 0x1EC9: case 0x1ECB: return 'i';
    case 0x00D1: case 0x0143: case 0x0145: case 0x0147: case 0x01F8: case 0x1E44: case 0x1E46: case 0x1E48: case 0x1E4A: return 'N';
    case 0x00F1: case 0x0144: case 0x0146: case 0x0148: case 0x01F9: case 0x1E45: case 0x1E47: case 0x1E49: case 0x1E4B: return 'n';
    case 0x00D2: case 0x00D3: case 0x00D4: case 0x00D5: case 0x00D6: case 0x014C: case 0x014E: case 0x0150: case 0x01A0: case 0x01D1: case 0x01EA: case 0x01EC: case 0x020C: case 0x020E: case 0x022A: case 0x022C: case 0x022E: case 0x0230: case 0x1E4C: case 0x1E4E: case 0x1E50: case 0x1E52: case 0x1ECC: case 0x1ECE: case 0x1ED0: case 0x1ED2: case 0x1ED4: case 0x1ED6: case 0x1ED8: case 0x1EDA: case 0x1EDC: case 0x1EDE: case 0x1EE0: case 0x1EE2: return 'O';
    case 0x00F2: case 0x00F3: case 0x00F4: case 0x00F5: case 0x00F6: case 0x014D: case 0x014F: case 0x0151: case 0x01A1: case 0x01D2: case 0x01EB: case 0x01ED: case 0x020D: case 0x020F: case 0x022B: case 0x022D: case 0x022F: case 0x0231: case 0x1E4D: case 0x1E4F: case 0x1E51: case 0x1E53: case 0x1ECD: case 0x1ECF: case 0x1ED1: case 0x1ED3: case 0x1ED5: case 0x1ED7: case 0x1ED9: case 0x1EDB: case 0x1EDD: case 0x1EDF: case 0x1EE1: case 0x1EE3: return 'o';
    case 0x015A: case 0x015C: case 0x015E: case 0x0160: case 0x0218: case 0x1E60: case 0x1E62: case 0x1E64: case 0x1E66: case 0x1E68: return 'S';
    case 0x015B: case 0x015D: case 0x015F: case 0x0161: case 0x0219: case 0x1E61: case 0x1E63: case 0x1E65: case 0x1E67: case 0x1E69: return 's';
    case 0x0162: case 0x0164: case 0x021A: case 0x1E6A: case 0x1E6C: case 0x1E6E: case 0x1E70: return 'T';
    case 0x0163: case 0x0165: case 0x021B: case 0x1E6B: case 0x1E6D: case 0x1E6F: case 0x1E71: case 0x1E97:
      return 't';
    case 0x00D9: case 0x00DA: case 0x00DB: case 0x00DC: case 0x0168: case 0x016A: case 0x016C: case 0x016E: case 0x0170: case 0x0172: case 0x01AF: case 0x01D3: case 0x01D5: case 0x01D7: case 0x01D9: case 0x01DB: case 0x0214: case 0x0216: case 0x1E72: case 0x1E74: case 0x1E76: case 0x1E78: case 0x1E7A: case 0x1EE4: case 0x1EE6: case 0x1EE8: case 0x1EEA: case 0x1EEC: case 0x1EEE: case 0x1EF0: return 'U';
    case 0x00F9: case 0x00FA: case 0x00FB: case 0x00FC: case 0x0169: case 0x016B: case 0x016D: case 0x016F: case 0x0171: case 0x0173: case 0x01B0: case 0x01D4: case 0x01D6: case 0x01D8: case 0x01DA: case 0x01DC: case 0x0215: case 0x0217: case 0x1E73: case 0x1E75: case 0x1E77: case 0x1E79: case 0x1E7B: case 0x1EE5: case 0x1EE7: case 0x1EE9: case 0x1EEB: case 0x1EED: case 0x1EEF: case 0x1EF1: return 'u';
    case 0x00DD: case 0x0176: case 0x0178: case 0x0232: case 0x1E8E: case 0x1EF2: case 0x1EF4: case 0x1EF6: case 0x1EF8: return 'Y';
    case 0x00FD: case 0x00FF: case 0x0177: case 0x0233: case 0x1E8F: case 0x1E99: case 0x1EF3: case 0x1EF5: case 0x1EF7: case 0x1EF9: return 'y';
    case 0x1E02: case 0x1E04: case 0x1E06: return 'B';
    case 0x1E03: case 0x1E05: case 0x1E07: return 'b';
    case 0x1E1E: return 'F';
    case 0x1E1F: return 'f';
    case 0x1E3E: case 0x1E40: case 0x1E42: return 'M';
    case 0x1E3F: case 0x1E41: case 0x1E43: return 'm';
    case 0x1E54: case 0x1E56: return 'P';
    case 0x1E55: case 0x1E57: return 'p';
    case 0x011C: case 0x011E: case 0x0120: case 0x0122: case 0x01E6: case 0x01F4: case 0x1E20: return 'G';
    case 0x011D: case 0x011F: case 0x0121: case 0x0123: case 0x01E7: case 0x01F5: case 0x1E21: return 'g';
    case 0x0124: case 0x021E: case 0x1E22: case 0x1E24: case 0x1E26: case 0x1E28: case 0x1E2A: return 'H';
    case 0x0125: case 0x021F: case 0x1E23: case 0x1E25: case 0x1E27: case 0x1E29: case 0x1E2B: case 0x1E96:
      return 'h';
    case 0x0134: return 'J';
    case 0x0135: case 0x01F0: return 'j';
    case 0x0136: case 0x01E8: case 0x1E30: case 0x1E32: case 0x1E34: return 'K';
    case 0x0137: case 0x01E9: case 0x1E31: case 0x1E33: case 0x1E35: return 'k';
    case 0x0139: case 0x013B: case 0x013D: case 0x1E36: case 0x1E38: case 0x1E3A: case 0x1E3C: return 'L';
    case 0x013A: case 0x013C: case 0x013E: case 0x1E37: case 0x1E39: case 0x1E3B: case 0x1E3D: return 'l';
    case 0x0154: case 0x0156: case 0x0158: case 0x0210: case 0x0212: case 0x1E58: case 0x1E5A: case 0x1E5C: case 0x1E5E: return 'R';
    case 0x0155: case 0x0157: case 0x0159: case 0x0211: case 0x0213: case 0x1E59: case 0x1E5B: case 0x1E5D: case 0x1E5F: return 'r';
    case 0x1E7C: case 0x1E7E: return 'V';
    case 0x1E7D: case 0x1E7F: return 'v';
    case 0x0174: case 0x1E80: case 0x1E82: case 0x1E84: case 0x1E86: case 0x1E88: return 'W';
    case 0x0175: case 0x1E81: case 0x1E83: case 0x1E85: case 0x1E87: case 0x1E89: case 0x1E98: return 'w';
    case 0x1E8A: case 0x1E8C: return 'X';
    case 0x1E8B: case 0x1E8D: return 'x';
    case 0x0179: case 0x017B: case 0x017D: case 0x1E90: case 0x1E92: case 0x1E94: return 'Z';
    case 0x017A: case 0x017C: case 0x017E: case 0x1E91: case 0x1E93: case 0x1E95: return 'z';
    default: return 0;
  }
}

String toDisplayAscii(const String &value) {
  String result;
  result.reserve(value.length());
  bool previousSpace = false;
  for (size_t index = 0; index < value.length();) {
    const uint8_t first = static_cast<uint8_t>(value[index++]);
    uint32_t codepoint = first;
    uint8_t continuationCount = 0;
    if ((first & 0xE0) == 0xC0) {
      codepoint = first & 0x1F;
      continuationCount = 1;
    } else if ((first & 0xF0) == 0xE0) {
      codepoint = first & 0x0F;
      continuationCount = 2;
    } else if ((first & 0xF8) == 0xF0) {
      codepoint = first & 0x07;
      continuationCount = 3;
    } else if (first >= 0x80) {
      codepoint = 0xFFFD;
    }

    bool validSequence = index + continuationCount <= value.length();
    for (uint8_t byteIndex = 0; validSequence && byteIndex < continuationCount;
         ++byteIndex) {
      const uint8_t next = static_cast<uint8_t>(value[index++]);
      if ((next & 0xC0) != 0x80) {
        validSequence = false;
        break;
      }
      codepoint = (codepoint << 6) | (next & 0x3F);
    }
    if (!validSequence) codepoint = 0xFFFD;

    char output = 0;
    if (codepoint >= 32 && codepoint <= 126) {
      output = static_cast<char>(codepoint);
    } else if (codepoint == 0x00A0 || codepoint == 0x2013 ||
               codepoint == 0x2014 || codepoint == 0x2212) {
      output = codepoint == 0x00A0 ? ' ' : '-';
    } else if (codepoint == 0x2018 || codepoint == 0x2019) {
      output = '\'';
    } else if (codepoint == 0x201C || codepoint == 0x201D) {
      output = '"';
    } else if (codepoint == 0x2022) {
      output = '*';
    } else if (codepoint == 0x2190 || codepoint == 0x2B05) {
      output = '<';
    } else if (codepoint == 0x2191 || codepoint == 0x2B06) {
      output = '^';
    } else if (codepoint == 0x2192 || codepoint == 0x27A1) {
      output = '>';
    } else if (codepoint == 0x2193 || codepoint == 0x2B07) {
      output = 'v';
    } else if (codepoint == 0x21B6) {
      output = 'U';
    } else if (codepoint == 0x2611 || codepoint == 0x2713 ||
               codepoint == 0x2714 || codepoint == 0x2705 ||
               codepoint == 0x1F5F8) {
      output = 'v';
    } else if (codepoint == 0x26A0 || codepoint == 0x2757 ||
               codepoint == 0x1F514) {
      output = '!';
    } else if (codepoint == 0x1F4CD) {
      output = '@';
    } else if (codepoint >= 0x0300 && codepoint <= 0x036F) {
      continue;
    } else {
      output = transliterateCodepoint(codepoint);
    }

    if (output != 0) {
      result += output;
      previousSpace = output == ' ';
    } else if (!previousSpace) {
      result += ' ';
      previousSpace = true;
    }
  }
  result.trim();
  return result;
}

void drawText(const String &value, int16_t x, int16_t y, uint8_t size,
              uint16_t color = COLOR_TEXT,
              uint16_t background = COLOR_BACKGROUND) {
  tft.setTextSize(size);
  tft.setTextColor(color, background);
  tft.setCursor(x, y);
  tft.print(value);
}

void drawCentered(const String &value, int16_t y, uint8_t size,
                  uint16_t color = COLOR_TEXT,
                  uint16_t background = COLOR_BACKGROUND) {
  const int16_t width = static_cast<int16_t>(value.length()) * 6 * size;
  drawText(value, max<int16_t>(1, (tft.width() - width) / 2), y, size, color,
           background);
}

void drawWrapped(const String &value, int16_t y, uint16_t color = COLOR_TEXT,
                 uint16_t background = COLOR_BACKGROUND,
                 uint8_t maxLines = 4) {
  String remaining = toDisplayAscii(value);
  for (uint8_t line = 0; line < maxLines && remaining.length() > 0; ++line) {
    const int limit = min<int>(20, remaining.length());
    int split = remaining.lastIndexOf(' ', limit);
    if (split <= 0) split = limit;
    drawText(remaining.substring(0, split), 5, y + line * 11, 1, color,
             background);
    remaining = remaining.substring(split);
    remaining.trim();
  }
}

String clockStatusKey() {
  if (activeMode == "wifi") {
    if (WiFi.status() == WL_CONNECTED) return "WiFi";
    return (millis() / STATUS_BLINK_MS) % 2 == 0 ? "WifiWait" : "";
  }
  if (activeMode == "bluetooth") {
    if (bleConnected) return "BLT";
    return (millis() / STATUS_BLINK_MS) % 2 == 0 ? "BLTWait" : "";
  }
  return "SET";
}

void drawClockStaticLayout() {
  // Top third is reserved for date, connection indicator and the clock.
  tft.drawFastHLine(4, 54, 120, COLOR_PANEL);
}

void resetClockRenderCache() {
  lastRenderedTime = "";
  lastRenderedDate = "";
  lastRenderedStatus = "";
}

void drawClockStatus(const String &status) {
  tft.fillRect(90, 0, 38, 14, COLOR_BACKGROUND);
  if (status == "WiFi") {
    drawText("WiFi", 100, 3, 1, COLOR_OK);
  } else if (status == "WifiWait") {
    drawText("WiFi", 100, 3, 1, COLOR_WAIT);
  } else if (status == "BLT") {
    drawText("BLT", 106, 3, 1, COLOR_OK);
  } else if (status == "BLTWait") {
    drawText("BLT", 106, 3, 1, COLOR_WAIT);
  } else if (status == "SET") {
    drawText("SET", 106, 3, 1, COLOR_WAIT);
  }
  lastRenderedStatus = status;
}

void refreshConnectionIndicator() {
  if (!clockFrameDrawn || detailsUntil != 0 ||
      menuView != MenuView::Closed || activeMode == "setup") return;
  const String status = clockStatusKey();
  if (status != lastRenderedStatus) drawClockStatus(status);
}

void renderClock(bool restorePopupRegion = false) {
  // The full frame is drawn only when entering the clock. Normal ticks and
  // popup restoration update only the dirty rectangles below.
  if (!clockFrameDrawn) {
    tft.fillScreen(COLOR_BACKGROUND);
    drawClockStaticLayout();
    clockFrameDrawn = true;
    resetClockRenderCache();
  } else if (restorePopupRegion) {
    // Notifications live below the clock, so restoring one never touches the
    // date, connection indicator or clock in the top third.
    tft.fillRect(0, 56, 128, 104, COLOR_BACKGROUND);
  }

  const bool valid = clockValid();
  String timeText = "--:--";
  String dateText = "--/--/----";
  if (valid) {
    tm localTime{};
    time_t current = time(nullptr);
    localtime_r(&current, &localTime);
    char timeBuffer[8];
    char dateBuffer[16];
    strftime(timeBuffer, sizeof(timeBuffer), "%H:%M", &localTime);
    strftime(dateBuffer, sizeof(dateBuffer), "%d/%m/%Y", &localTime);
    timeText = timeBuffer;
    dateText = dateBuffer;
  }

  if (timeText != lastRenderedTime) {
    tft.fillRect(4, 17, 120, 34, COLOR_BACKGROUND);
    drawCentered(timeText, 17, 4, valid ? COLOR_TEXT : COLOR_WAIT);
    lastRenderedTime = timeText;
  }
  if (dateText != lastRenderedDate) {
    tft.fillRect(0, 0, 86, 14, COLOR_BACKGROUND);
    drawText(dateText, 4, 3, 1, valid ? COLOR_TEXT : COLOR_WAIT);
    lastRenderedDate = dateText;
  }

  const String status = clockStatusKey();
  if (status != lastRenderedStatus) drawClockStatus(status);
}

void drawSetupScreen(bool force = false) {
  if (setupFrameDrawn && !force) return;
  tft.fillScreen(COLOR_BACKGROUND);
  drawCentered("SETUP", 8, 2, COLOR_ACCENT);
  drawText("IP: 192.168.4.1", 5, 34, 1);
  drawText("WIFI AP:", 5, 46, 1);
  drawText(SETUP_SSID, 5, 58, 1);
  drawText("Pass: monitor1234", 5, 70, 1);
  drawText("BLE: " + String(BLE_NAME), 5, 85, 1, COLOR_ACCENT);
  drawText("Open app to send", 5, 102, 1, COLOR_WAIT);
  drawText("Use WiFi or BLE", 5, 114, 1, COLOR_WAIT);
  tft.drawFastHLine(4, 135, 120, COLOR_PANEL);
  drawCentered("AP + BLE", 141, 1, COLOR_OK);
  setupFrameDrawn = true;
  clockFrameDrawn = false;
}

String clippedText(const String &value, size_t maxLength) {
  if (value.length() <= maxLength) return value;
  if (maxLength < 2) return value.substring(0, maxLength);
  return value.substring(0, maxLength - 1) + "~";
}

void restoreMainScreen() {
  menuView = MenuView::Closed;
  detailsUntil = 0;
  popupUntil = 0;
  clockFrameDrawn = false;
  setupFrameDrawn = false;
  if (activeMode == "setup") {
    drawSetupScreen(true);
  } else {
    renderClock();
    if (navigationVisible) {
      drawNavigation(navigationManeuver, navigationDistanceMeters,
                     navigationStreet, navigationExitNumber, navigationTurnAngle);
      navigationOnScreen = true;
      Serial.println("DISPLAY: navigation restored after details");
    }
  }
}

void drawConnectionDetails() {
  popupUntil = 0;
  navigationOnScreen = false;
  detailsUntil = menuView == MenuView::Info
                     ? 0
                     : millis() + DETAILS_DURATION_MS;
  clockFrameDrawn = false;
  setupFrameDrawn = false;

  String method = "SETUP";
  String state = "AP+BLE READY";
  String ssid = SETUP_SSID;
  String ip = WiFi.softAPIP().toString();
  String rssi = "--";

  if (activeMode == "wifi") {
    const bool connected = WiFi.status() == WL_CONNECTED;
    method = "WIFI";
    state = connected ? "CONNECTED" : "DISCONNECTED";
    ssid = wifiSsid.isEmpty() ? WiFi.SSID() : wifiSsid;
    ip = connected ? WiFi.localIP().toString() : "--";
    rssi = connected ? String(WiFi.RSSI()) + " dBm" : "--";
  } else if (activeMode == "bluetooth") {
    method = "BLT";
    state = bleConnected ? "CONNECTED" : "WAITING";
    ssid = "--";
    ip = "--";
  }

  tft.fillScreen(COLOR_BACKGROUND);
  drawCentered("ESP32 INFO", 5, 2, COLOR_ACCENT);
  tft.drawFastHLine(4, 25, 120, COLOR_PANEL);
  drawText("DEV: " + String(BLE_NAME), 4, 33, 1);
  drawText("METHOD: " + method, 4, 49, 1,
           method == "WIFI" ? COLOR_OK : COLOR_ACCENT);
  drawText("STATE: " + state, 4, 65, 1,
           state == "CONNECTED" ? COLOR_OK : COLOR_WAIT);
  drawText("SSID: " + clippedText(toDisplayAscii(ssid), 14), 4, 81, 1);
  drawText("IP: " + ip, 4, 97, 1, COLOR_WAIT);
  drawText("RSSI: " + rssi, 4, 113, 1);
  drawText("FW: " + String(FIRMWARE_VERSION), 4, 129, 1);
  tft.drawFastHLine(4, 143, 120, COLOR_PANEL);
  drawText("B3: MENU", 4, 149, 1, COLOR_ACCENT);

  Serial.printf("MENU: details mode=%s ssid=%s ip=%s rssi=%s\n",
                 method.c_str(), ssid.c_str(), ip.c_str(), rssi.c_str());
}

constexpr uint8_t MENU_ITEM_COUNT = 4;
constexpr uint8_t nextMenuItem(uint8_t index) {
  return (index + 1) % MENU_ITEM_COUNT;
}
static_assert(nextMenuItem(3) == 0, "Menu selection must wrap");

void drawMenuRow(uint8_t index) {
  const int16_t y = 36 + index * 26;
  const bool selected = index == menuSelection;
  const uint16_t background = selected ? COLOR_ACCENT : COLOR_PANEL;
  const uint16_t foreground = selected ? COLOR_BACKGROUND : COLOR_TEXT;
  tft.fillRect(4, y, 120, 23, background);
  const String label = index == 0 ? "WiFi"
                       : index == 1 ? "Bluetooth"
                       : index == 2 ? (lightTheme ? "Theme: Light" : "Theme: Dark")
                                    : "ESP32 Info";
  drawText(label, 9, y + 7, 1, foreground, background);
  if ((index == 0 && activeMode == "wifi") ||
      (index == 1 && activeMode == "bluetooth")) {
    drawText("ON", 105, y + 7, 1, selected ? foreground : COLOR_OK,
             background);
  }
}

void drawMenu() {
  tft.fillScreen(COLOR_BACKGROUND);
  drawCentered("MENU", 5, 2, COLOR_ACCENT);
  tft.drawFastHLine(4, 29, 120, COLOR_PANEL);
  for (uint8_t index = 0; index < MENU_ITEM_COUNT; ++index) {
    drawMenuRow(index);
  }
  tft.drawFastHLine(4, 142, 120, COLOR_PANEL);
  drawText("1 NEXT 2 OK 3 BACK", 6, 149, 1, COLOR_WAIT);
  clockFrameDrawn = false;
  setupFrameDrawn = false;
}

void openMenu() {
  menuView = MenuView::List;
  menuSelection = 0;
  menuLastInput = millis();
  detailsUntil = 0;
  popupUntil = 0;
  navigationOnScreen = false;
  drawMenu();
  Serial.println("MENU: opened");
}

void closeMenu() {
  if (menuView == MenuView::Closed) return;
  Serial.println("MENU: closed");
  restoreMainScreen();
}

void selectMenuItem() {
  if (menuView != MenuView::List) return;
  menuLastInput = millis();
  if (menuSelection == 0) {
    if (activeMode == "wifi") {
      closeMenu();
    } else {
      switchToWifi();
    }
  } else if (menuSelection == 1) {
    if (activeMode == "bluetooth") {
      closeMenu();
    } else {
      switchToBluetooth();
    }
  } else if (menuSelection == 2) {
    applyTheme(!lightTheme);
    preferences.putBool("lightTheme", lightTheme);
    drawMenu();
    Serial.printf("MENU: theme=%s\n", lightTheme ? "light" : "dark");
  } else {
    menuView = MenuView::Info;
    drawConnectionDetails();
    Serial.println("MENU: device info");
  }
}

bool updateButton(ButtonState &button) {
  const bool rawPressed = digitalRead(button.pin) == LOW;
  const uint32_t now = millis();

  if (rawPressed != button.lastRawPressed) {
    button.lastRawPressed = rawPressed;
    button.changedAt = now;
  }

  if (now - button.changedAt >= BUTTON_DEBOUNCE_MS &&
      rawPressed != button.stablePressed) {
    button.stablePressed = rawPressed;
    return true;
  }
  return false;
}

void handleButtons() {
  const bool wifiChanged = updateButton(wifiButton);
  const bool bluetoothChanged = updateButton(bluetoothButton);
  const bool menuChanged = updateButton(menuButton);

  if (menuChanged && !menuButton.stablePressed) {
    menuLastInput = millis();
    if (menuView == MenuView::Closed) {
      openMenu();
    } else if (menuView == MenuView::Info) {
      menuView = MenuView::List;
      drawMenu();
    } else {
      closeMenu();
    }
  }
  if (wifiChanged && !wifiButton.stablePressed) {
    if (menuView == MenuView::List) {
      const uint8_t previous = menuSelection;
      menuSelection = nextMenuItem(menuSelection);
      menuLastInput = millis();
      drawMenuRow(previous);
      drawMenuRow(menuSelection);
      Serial.printf("MENU: selected %u\n", menuSelection);
    } else if (menuView == MenuView::Closed) {
      if (activeMode == "wifi" && wifiSsid == DEFAULT_WIFI_SSID &&
          WiFi.status() == WL_CONNECTED) {
        Serial.println("BUTTON G38: WiFi SuBo already connected");
      } else {
        Serial.println("BUTTON G38: quick WiFi SuBo");
        switchToWifi(true);
      }
    }
  }
  if (bluetoothChanged && !bluetoothButton.stablePressed) {
    if (menuView == MenuView::List) {
      selectMenuItem();
    } else if (menuView == MenuView::Closed) {
      Serial.println("BUTTON G39: quick fresh Bluetooth link");
      switchToBluetooth();
    }
  }
}

void drawDisplayBootScreen() {
  tft.fillScreen(COLOR_BACKGROUND);
  drawCentered("DISPLAY", 36, 2, COLOR_ACCENT);
  drawCentered("INITIALIZED", 62, 2, COLOR_TEXT);
  drawCentered("ST7735 128x160", 94, 1, COLOR_OK);
  Serial.println("DISPLAY: initialized ST7735 128x160");
}

void showColorTestPage(uint16_t background, uint16_t foreground,
                       const String &name, uint8_t page) {
  tft.fillScreen(background);
  tft.setTextSize(1);
  tft.setTextColor(foreground, background);
  tft.setCursor(30, 20);
  tft.print("DISPLAY TEST");
  tft.setTextSize(3);
  tft.setCursor(34, 58);
  tft.print(name);
  tft.setTextSize(1);
  tft.setCursor(55, 112);
  tft.printf("%u/6", static_cast<unsigned>(page));
}

void runColorTest() {
  Serial.println("DISPLAY TEST: RED GREEN BLUE WHITE BLACK YELLOW");
  showColorTestPage(ST77XX_RED, ST77XX_WHITE, "RED", 1);
  delay(700);
  showColorTestPage(ST77XX_GREEN, ST77XX_BLACK, "GREEN", 2);
  delay(700);
  showColorTestPage(ST77XX_BLUE, ST77XX_WHITE, "BLUE", 3);
  delay(700);
  showColorTestPage(ST77XX_WHITE, ST77XX_BLACK, "WHITE", 4);
  delay(700);
  showColorTestPage(ST77XX_BLACK, ST77XX_WHITE, "BLACK", 5);
  delay(700);
  showColorTestPage(ST77XX_YELLOW, ST77XX_BLACK, "YELLOW", 6);
  delay(700);
  Serial.println("DISPLAY TEST: finished");
}

void drawPopup() {
  // Keep the top third readable while riding; notifications occupy only the
  // lower two thirds of the screen.
  tft.fillRect(2, 58, 124, 100, COLOR_PANEL);
  const String header = popupKind == "task"
                            ? "TASK"
                            : popupKind == "navigation" ? "NAVIGATION"
                            : popupKind == "connection" ? "CONNECTION"
                                                          : "NOTIFICATION";
  drawText(header, 7, 64, 1, COLOR_ACCENT, COLOR_PANEL);
  drawWrapped(popupTitle, 80, COLOR_TEXT, COLOR_PANEL, 2);
  drawWrapped(popupBody, 112, COLOR_WAIT, COLOR_PANEL);
}

String formatNavigationDistance(int distanceMeters) {
  char text[16];
  if (distanceUsesMeters(distanceMeters)) {
    snprintf(text, sizeof(text), "%d m", distanceMeters);
  } else if (distanceMeters < 10000) {
    snprintf(text, sizeof(text), "%d.%02d km", distanceMeters / 1000,
             (distanceMeters % 1000) / 10);
  } else {
    snprintf(text, sizeof(text), "%d.%01d km", distanceMeters / 1000,
             (distanceMeters % 1000) / 100);
  }
  return String(text);
}

void drawNavigationDistance(int distanceMeters) {
  tft.fillRect(2, 58, 124, 23, COLOR_PANEL);
  drawCentered(formatNavigationDistance(distanceMeters), 61, 2, COLOR_WAIT,
               COLOR_PANEL);
}

bool isTurnManeuver(const String &maneuver) {
  return maneuver == "left" || maneuver == "right" || maneuver == "u_turn" ||
         maneuver == "roundabout" || maneuver == "roundabout_left";
}

bool showTurnArrow(const String &maneuver, int distanceMeters) {
  return isTurnManeuver(maneuver) && showTurnAt(distanceMeters);
}

bool blinkTurnArrow(const String &maneuver, int distanceMeters) {
  return isTurnManeuver(maneuver) && blinkTurnAt(distanceMeters);
}

void drawNavigationArrow(const String &maneuver, int distanceMeters,
                         bool visible, int exitNumber = 0,
                         int turnAngle = 999) {
  // The arrow is the only region touched by the 500 ms blink.
  tft.fillRect(2, 82, 58, 66, COLOR_PANEL);
  if (!visible) return;
  if (showTurnArrow(maneuver, distanceMeters) &&
      (maneuver == "left" || maneuver == "right")) {
    const bool right = maneuver == "right";
    // Approach from the bottom, follow a rounded 90-degree corner, then turn.
    const int16_t cornerX = right ? 22 : 38;
    tft.fillCircle(cornerX, 110, 12, COLOR_TEXT);
    tft.fillCircle(cornerX, 110, 4, COLOR_PANEL);
    if (right) {
      tft.fillRect(22, 98, 13, 25, COLOR_PANEL);
      tft.fillRect(10, 110, 25, 13, COLOR_PANEL);
      tft.fillRect(10, 109, 9, 35, COLOR_TEXT);
      tft.fillRect(22, 98, 20, 9, COLOR_TEXT);
      tft.fillTriangle(56, 102, 39, 90, 39, 114, COLOR_TEXT);
    } else {
      tft.fillRect(26, 98, 12, 25, COLOR_PANEL);
      tft.fillRect(26, 110, 25, 13, COLOR_PANEL);
      tft.fillRect(41, 109, 9, 35, COLOR_TEXT);
      tft.fillRect(18, 98, 20, 9, COLOR_TEXT);
      tft.fillTriangle(4, 102, 21, 90, 21, 114, COLOR_TEXT);
    }
  } else if (showTurnArrow(maneuver, distanceMeters) &&
             maneuver == "u_turn") {
    // Enter on the right, turn back, and point down the left return lane.
    tft.fillCircle(29, 111, 18, COLOR_TEXT);
    tft.fillCircle(29, 111, 11, COLOR_PANEL);
    tft.fillRect(9, 111, 41, 24, COLOR_PANEL);
    tft.fillRoundRect(9, 106, 8, 27, 4, COLOR_TEXT);
    tft.fillRoundRect(41, 106, 8, 38, 4, COLOR_TEXT);
    tft.fillTriangle(13, 146, 4, 131, 25, 131, COLOR_TEXT);
  } else if (showTurnArrow(maneuver, distanceMeters) &&
             (maneuver == "roundabout" || maneuver == "roundabout_left")) {
    // OsmAnd's turn path: enter from below, travel around the ring, then exit
    // radially at the route angle. A notification without angle is only a
    // generic roundabout cue; never invent an exit direction from its ordinal.
    constexpr int16_t centerX = 30;
    constexpr int16_t centerY = 111;
    constexpr int16_t outerRadius = 19;
    constexpr int16_t innerRadius = 12;
    const bool clockwise = maneuver == "roundabout_left";
    tft.fillRoundRect(centerX - 4, centerY + outerRadius - 1, 8, 18, 3,
                      COLOR_TEXT);
    if (turnAngle >= -180 && turnAngle <= 180) {
      const uint16_t ringOutline = lightTheme ? 0xAD55 : 0x630C;
      tft.drawCircle(centerX, centerY, outerRadius, ringOutline);
      tft.drawCircle(centerX, centerY, innerRadius, ringOutline);
      // OsmAnd uses t + 180 for left-hand circulation and t - 180 for
      // right-hand circulation. Clamp near the entry so the exit stays legible.
      const int sweep = roundaboutSweepDegrees(turnAngle, exitNumber,
                                               clockwise);
      // OsmAnd draws the exits passed before the chosen one as outline steps.
      if (exitNumber > 1 && exitNumber <= 5) {
        for (int ordinal = 1; ordinal < exitNumber; ++ordinal) {
          const float theta = (sweep * ordinal / exitNumber) * DEG_TO_RAD;
          const float ux = -sinf(theta);
          const float uy = cosf(theta);
          for (int16_t r = outerRadius; r <= 26; r += 2) {
            tft.fillCircle(lroundf(centerX + ux * r),
                           lroundf(centerY + uy * r), 1, ringOutline);
          }
        }
      }
      // Fill the annular route as joined quads, not disconnected dots.
      const int step = clockwise ? 6 : -6;
      for (int degree = 0; clockwise ? degree < sweep : degree > sweep;
           degree += step) {
        const int next = clockwise ? min(degree + step, sweep)
                                   : max(degree + step, sweep);
        const float a = degree * DEG_TO_RAD;
        const float b = next * DEG_TO_RAD;
        const float ax = -sinf(a), ay = cosf(a);
        const float bx = -sinf(b), by = cosf(b);
        const int16_t axOut = lroundf(centerX + ax * outerRadius);
        const int16_t ayOut = lroundf(centerY + ay * outerRadius);
        const int16_t bxOut = lroundf(centerX + bx * outerRadius);
        const int16_t byOut = lroundf(centerY + by * outerRadius);
        const int16_t axIn = lroundf(centerX + ax * innerRadius);
        const int16_t ayIn = lroundf(centerY + ay * innerRadius);
        const int16_t bxIn = lroundf(centerX + bx * innerRadius);
        const int16_t byIn = lroundf(centerY + by * innerRadius);
        tft.fillTriangle(axOut, ayOut, bxOut, byOut, axIn, ayIn, COLOR_TEXT);
        tft.fillTriangle(axIn, ayIn, bxIn, byIn, bxOut, byOut, COLOR_TEXT);
      }
      const float theta = sweep * DEG_TO_RAD;
      const float ux = -sinf(theta);
      const float uy = cosf(theta);
      const int16_t x0 = lroundf(centerX + ux * 16);
      const int16_t y0 = lroundf(centerY + uy * 16);
      const int16_t x1 = lroundf(centerX + ux * 23);
      const int16_t y1 = lroundf(centerY + uy * 23);
      tft.fillTriangle(lroundf(x0 - uy * 4), lroundf(y0 + ux * 4),
                       lroundf(x1 - uy * 4), lroundf(y1 + ux * 4),
                       lroundf(x0 + uy * 4), lroundf(y0 - ux * 4), COLOR_TEXT);
      tft.fillTriangle(lroundf(x0 + uy * 4), lroundf(y0 - ux * 4),
                       lroundf(x1 + uy * 4), lroundf(y1 - ux * 4),
                       lroundf(x1 - uy * 4), lroundf(y1 + ux * 4), COLOR_TEXT);
      tft.fillTriangle(lroundf(centerX + ux * 28),
                       lroundf(centerY + uy * 28),
                       lroundf(centerX + ux * 21 - uy * 8),
                       lroundf(centerY + uy * 21 + ux * 8),
                       lroundf(centerX + ux * 21 + uy * 8),
                       lroundf(centerY + uy * 21 - ux * 8), COLOR_TEXT);
    } else {
      // AIDL fallback/notification may have no route angle.
      tft.fillCircle(centerX, centerY, outerRadius + 1, COLOR_TEXT);
      tft.fillCircle(centerX, centerY, innerRadius, COLOR_PANEL);
      if (clockwise) {
        tft.fillTriangle(53, 92, 34, 84, 34, 100, COLOR_ACCENT);
      } else {
        tft.fillTriangle(7, 92, 26, 84, 26, 100, COLOR_ACCENT);
      }
    }
    if (exitNumber > 0) {
      const String label = String(exitNumber);
      const uint8_t scale = label.length() == 1 ? 2 : 1;
      // The classic font's last spacing column is blank; center its 5x7 ink.
      const int16_t inkWidth = label.length() * 6 * scale - scale;
      drawText(label, centerX - inkWidth / 2, centerY - 7 * scale / 2,
               scale, COLOR_ACCENT, COLOR_PANEL);
    }
  } else if (maneuver == "arrive") {
    tft.fillCircle(29, 113, 20, COLOR_TEXT);
    tft.fillCircle(29, 113, 12, COLOR_PANEL);
    tft.fillCircle(29, 113, 5, COLOR_OK);
  } else {
    tft.fillRect(25, 102, 9, 40, COLOR_TEXT);
    tft.fillTriangle(29, 84, 12, 106, 46, 106, COLOR_TEXT);
  }
}

void drawNavigation(const String &maneuver, int distanceMeters,
                    const String &street, int exitNumber, int turnAngle) {
  tft.fillRect(2, 58, 124, 100, COLOR_PANEL);
  navigationArrowVisible = true;
  lastNavigationBlink = millis();
  drawNavigationArrow(maneuver, distanceMeters, true, exitNumber, turnAngle);
  String road = clippedText(toDisplayAscii(street), 40);
  road.trim();
  drawText(maneuver == "left" || maneuver == "right" ? "ONTO" : "ROAD",
           61, 87, 1, COLOR_WAIT, COLOR_PANEL);
  if (road.isEmpty()) drawText("--", 61, 102, 1, COLOR_WAIT, COLOR_PANEL);
  for (uint8_t line = 0; line < 4 && !road.isEmpty(); ++line) {
    int split = road.length() > 10 ? road.lastIndexOf(' ', 10) : road.length();
    if (split <= 0) split = min<int>(10, road.length());
    drawText(road.substring(0, split), 61, 101 + line * 12, 1,
             COLOR_ACCENT, COLOR_PANEL);
    road = road.substring(split);
    road.trim();
  }

  drawNavigationDistance(distanceMeters);
}

void showPopup(const String &kind, const String &title, const String &body) {
  if (detailsUntil != 0 || menuView != MenuView::Closed) restoreMainScreen();
  navigationOnScreen = false;
  popupKind = kind;
  popupTitle = toDisplayAscii(title);
  popupBody = toDisplayAscii(body);
  popupUntil = millis() + POPUP_DURATION_MS;
  drawPopup();
  Serial.printf("DISPLAY: popup title=%s body=%s\n", popupTitle.c_str(),
                popupBody.c_str());
}

void showNavigation(const String &maneuver, int distanceMeters,
                    const String &street, int exitNumber = 0,
                    int turnAngle = 999) {
  const String safeStreet = clippedText(toDisplayAscii(street), 40);
  const String key = maneuver + ":" + String(distanceMeters) + ":" +
                     String(exitNumber) + ":" + String(turnAngle) + ":" + safeStreet;
  if (navigationOnScreen && lastNavigationKey == key) return;
  const bool distanceOnly = navigationOnScreen &&
                            navigationManeuver == maneuver &&
                            navigationExitNumber == exitNumber &&
                            navigationTurnAngle == turnAngle &&
                            navigationStreet == safeStreet;
  const bool arrowStageChanged =
      showTurnArrow(navigationManeuver, navigationDistanceMeters) !=
          showTurnArrow(maneuver, distanceMeters) ||
      blinkTurnArrow(navigationManeuver, navigationDistanceMeters) !=
          blinkTurnArrow(maneuver, distanceMeters);
  popupKind = "navigation";
  navigationVisible = true;
  navigationManeuver = maneuver;
  navigationDistanceMeters = distanceMeters;
  navigationExitNumber = exitNumber;
  navigationTurnAngle = turnAngle;
  navigationStreet = safeStreet;
  lastNavigationKey = key;
  popupUntil = 0;
  if (detailsUntil == 0 && menuView == MenuView::Closed) {
    if (distanceOnly) {
      drawNavigationDistance(distanceMeters);
      if (arrowStageChanged) {
        navigationArrowVisible = true;
        lastNavigationBlink = millis();
        drawNavigationArrow(maneuver, distanceMeters, true, exitNumber,
                            turnAngle);
      }
    } else {
      drawNavigation(maneuver, distanceMeters, navigationStreet, exitNumber,
                     turnAngle);
    }
    navigationOnScreen = true;
  }
  const String distanceText = formatNavigationDistance(distanceMeters);
  Serial.printf("DISPLAY: navigation %s %s %s exit=%d angle=%d arrow=%s blink=%s\n",
                maneuver.c_str(), navigationStreet.c_str(),
                distanceText.c_str(), exitNumber, turnAngle,
                showTurnArrow(maneuver, distanceMeters) ? maneuver.c_str()
                                                        : "straight",
                blinkTurnArrow(maneuver, distanceMeters) ? "yes" : "no");
}

void sendBleStatus(const String &message) {
  if (bleStatus == nullptr) return;
  bleStatus->setValue(message.c_str());
  bleStatus->notify();
}

void scheduleModeSwitch(const String &mode, bool useDefaultWifi = false) {
  pendingMode = mode;
  pendingDefaultWifi = useDefaultWifi;
  pendingModeAt = millis() + MODE_SWITCH_DELAY_MS;
}

bool processCommand(const String &payload) {
  JsonDocument document;
  if (payload.length() > MAX_COMMAND_BYTES ||
      deserializeJson(document, payload)) {
    sendBleStatus("error:invalid_json");
    return false;
  }

  const char *command = document["command"] | "";
  const int requestId = document["requestId"] | 0;
  const auto acknowledge = [requestId](const String &status) {
    sendBleStatus(requestId > 0 ? status + ":" + String(requestId) : status);
  };
  if (!document["apiVersion"].is<int>() ||
      document["apiVersion"].as<int>() != 1) {
    sendBleStatus("error:api_version");
    return false;
  }
  if (document["timestamp"].is<long>()) {
    const time_t incoming = document["timestamp"].as<time_t>();
    if (incoming > 1700000000) {
      timeval now{incoming, 0};
      settimeofday(&now, nullptr);
    }
  }

  if (strcmp(command, "ping") == 0) {
    acknowledge("ok:ping");
    return true;
  }

  if (strcmp(command, "push_notification") == 0 ||
      strcmp(command, "push_task") == 0) {
    const String title = document["title"] | BLE_NAME;
    const String body = document["body"] | (strcmp(command, "push_task") == 0
                                                ? "You have a new task"
                                                : "New notification");
    Serial.printf("COMMAND: %s title=%s\n", command, title.c_str());
    showPopup(strcmp(command, "push_task") == 0 ? "task" : "notice", title,
              body);
    acknowledge("ok:popup");
    return true;
  }

  if (strcmp(command, "navigation") == 0) {
    const String maneuver = document["maneuver"] | "straight";
    if (maneuver != "left" && maneuver != "right" &&
        maneuver != "straight" && maneuver != "u_turn" &&
        maneuver != "arrive" && maneuver != "roundabout" &&
        maneuver != "roundabout_left") {
      sendBleStatus("error:maneuver");
      return false;
    }
    const int distanceMeters = constrain(document["distance_m"] | 0, 0, 999999);
    const String street = document["street"] | "";
    const int exitNumber = maneuver == "roundabout" || maneuver == "roundabout_left"
                               ? constrain(document["exit"] | 0, 0, 99)
                               : 0;
    const int suppliedAngle = document["angle"] | 999;
    const int turnAngle = (maneuver == "roundabout" || maneuver == "roundabout_left") &&
                                  suppliedAngle >= -180 && suppliedAngle <= 180
                              ? suppliedAngle : 999;
    showNavigation(maneuver, distanceMeters, street, exitNumber, turnAngle);
    acknowledge("ok:navigation");
    return true;
  }

  if (strcmp(command, "clear_popup") == 0 ||
      strcmp(command, "clear_navigation") == 0) {
    const bool clearPopup = strcmp(command, "clear_popup") == 0;
    if (clearPopup) popupUntil = 0;
    navigationVisible = false;
    navigationOnScreen = false;
    lastNavigationKey = "";
    if (menuView == MenuView::Closed && popupUntil == 0) {
      if (detailsUntil != 0) {
        if (clearPopup) restoreMainScreen();
      } else if (activeMode == "setup") {
        drawSetupScreen(true);
      } else {
        renderClock(true);
      }
    }
    Serial.println(clearPopup ? "DISPLAY: popup and navigation cleared"
                              : "DISPLAY: navigation cleared");
    acknowledge("ok:clear");
    return true;
  }

  if (strcmp(command, "set_mode") == 0) {
    const String mode = document["mode"] | "";
    if (mode == "bluetooth" || (mode == "wifi" && !wifiSsid.isEmpty())) {
      preferences.putString("mode", mode);
      acknowledge("ok:mode");
      scheduleModeSwitch(mode);
      return true;
    } else {
      sendBleStatus("error:mode");
    }
    return false;
  }

  if (strcmp(command, "configure_wifi") == 0) {
    const String ssid = document["ssid"] | "";
    const String password = document["password"] | "";
    if (ssid.isEmpty() || ssid.length() > 32 || password.length() > 63) {
      sendBleStatus("error:wifi_credentials");
      return false;
    }
    preferences.putString("ssid", ssid);
    preferences.putString("password", password);
    preferences.putString("mode", "wifi");
    wifiSsid = ssid;
    wifiPassword = password;
    acknowledge("ok:wifi_saved");
    scheduleModeSwitch("wifi");
    return true;
  }

  sendBleStatus("error:unknown_command");
  return false;
}

class CommandCallbacks final : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *characteristic,
               NimBLEConnInfo & /*connectionInfo*/) override {
    const std::string value = characteristic->getValue();
    if (value.size() > MAX_COMMAND_BYTES || commandQueue == nullptr) {
      sendBleStatus("error:too_large");
      return;
    }
    QueuedCommand queued{};
    memcpy(queued.payload, value.data(), value.size());
    if (xQueueSend(commandQueue, &queued, 0) != pdTRUE) {
      sendBleStatus("error:busy");
    }
  }
};

class NavRideServerCallbacks final : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer * /*server*/,
                 NimBLEConnInfo &connectionInfo) override {
    bleConnected = true;
    Serial.printf("BLE: connected handle=%u\n", connectionInfo.getConnHandle());
  }

  void onDisconnect(NimBLEServer * /*server*/,
                    NimBLEConnInfo &connectionInfo, int reason) override {
    bleConnected = false;
    Serial.printf("BLE: disconnected handle=%u reason=%d\n",
                  connectionInfo.getConnHandle(), reason);
  }
};

void startBle() {
  if (bleStarted) {
    bleServer->advertiseOnDisconnect(true);
    NimBLEDevice::getAdvertising()->start();
    Serial.println("BLE: advertising restarted");
    return;
  }
  bleConnected = false;
  observedBleConnected = false;
  NimBLEDevice::init(BLE_NAME);
  NimBLEDevice::setMTU(185);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  bleServer = NimBLEDevice::createServer();
  static NavRideServerCallbacks serverCallbacks;
  bleServer->setCallbacks(&serverCallbacks);
  bleServer->advertiseOnDisconnect(true);
  NimBLEService *service = bleServer->createService(SERVICE_UUID);
  NimBLECharacteristic *command = service->createCharacteristic(
      COMMAND_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  static CommandCallbacks commandCallbacks;
  command->setCallbacks(&commandCallbacks);
  bleStatus = service->createCharacteristic(
      "7e6d0003-5b1a-4d8f-9a2c-320001000003",
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  bleStatus->setValue("ready");
  NimBLEAdvertising *advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->enableScanResponse(true);
  advertising->setName(BLE_NAME);
  advertising->start();
  bleStarted = true;
  Serial.println("BLE: advertising " + String(BLE_NAME));
}

void stopBle() {
  if (!bleStarted) return;
  NimBLEDevice::getAdvertising()->stop();
  if (bleServer != nullptr) {
    bleServer->advertiseOnDisconnect(false);
    for (const uint16_t handle : bleServer->getPeerDevices()) {
      bleServer->disconnect(handle);
    }
  }
  bleConnected = false;
  observedBleConnected = false;
  Serial.println("BLE: advertising stopped; stack retained for safe reuse");
}

void startHttp() {
  if (httpStarted) return;
  if (!httpConfigured) {
    server.on("/api/health", HTTP_GET, []() {
    JsonDocument document;
    document["connected"] = true;
    document["mode"] = activeMode;
    document["setup"] = activeMode == "setup";
    document["deviceName"] = BLE_NAME;
    document["firmware"] = FIRMWARE_VERSION;
    document["ssid"] = activeMode == "setup" ? SETUP_SSID : wifiSsid;
    document["ip"] = activeMode == "setup" ? WiFi.softAPIP().toString()
                                            : WiFi.localIP().toString();
    tm localTime{};
    char timeBuffer[20] = "";
    const time_t current = time(nullptr);
    if (clockValid() && localtime_r(&current, &localTime) != nullptr) {
      strftime(timeBuffer, sizeof(timeBuffer), "%d/%m/%Y %H:%M", &localTime);
    }
    document["localTime"] = timeBuffer;
    String body;
    serializeJson(document, body);
    sendJson(body);
  });
  server.on("/api/setup", HTTP_POST, []() {
    JsonDocument document;
    if (deserializeJson(document, server.arg("plain"))) {
      sendJson("{\"error\":\"invalid_json\"}", 400);
      return;
    }
    const String ssid = document["ssid"] | "";
    const String password = document["password"] | "";
    if (ssid.isEmpty() || ssid.length() > 32 || password.length() > 63) {
      sendJson("{\"error\":\"invalid_wifi\"}", 400);
      return;
    }
    preferences.putString("ssid", ssid);
    preferences.putString("password", password);
    preferences.putString("mode", "wifi");
    wifiSsid = ssid;
    wifiPassword = password;
    sendJson("{\"ok\":true,\"next\":\"wifi\"}");
    scheduleModeSwitch("wifi");
  });
  server.on("/api/command", HTTP_POST, []() {
    if (processCommand(server.arg("plain"))) {
      sendJson("{\"ok\":true}");
    } else {
      sendJson("{\"error\":\"invalid_command\"}", 400);
    }
  });
  server.on("/api/display-test", HTTP_POST, []() {
    runColorTest();
    clockFrameDrawn = false;
    renderClock();
    sendJson("{\"ok\":true,\"displayTest\":\"finished\"}");
  });
  server.onNotFound([]() {
    if (server.method() == HTTP_OPTIONS) {
      sendJson("{}", 204);
    } else {
      sendJson("{\"error\":\"not_found\"}", 404);
    }
  });
    httpConfigured = true;
  }
  server.begin();
  httpStarted = true;
  Serial.println("HTTP: server started on port 80");
}

void stopHttp() {
  if (!httpStarted) return;
  server.stop();
  httpStarted = false;
  Serial.println("HTTP: server stopped");
}

void startSetupMode() {
  menuView = MenuView::Closed;
  activeMode = "setup";
  wifiConnected = false;
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(SETUP_SSID, SETUP_PASSWORD);
  startHttp();
  startBle();
  Serial.printf("SETUP: AP IP=%s SSID=%s\n", WiFi.softAPIP().toString().c_str(),
                 SETUP_SSID);
  drawSetupScreen(true);
}

void prepareConnectionScreen(const String &title, const String &message) {
  menuView = MenuView::Closed;
  detailsUntil = 0;
  popupUntil = 0;
  navigationVisible = false;
  navigationOnScreen = false;
  clockFrameDrawn = false;
  setupFrameDrawn = false;
  renderClock();
  showPopup("connection", title, message);
}

void switchToWifi(bool useDefaultCredentials) {
  if (useDefaultCredentials && strlen(DEFAULT_WIFI_SSID) > 0) {
    wifiSsid = DEFAULT_WIFI_SSID;
    wifiPassword = DEFAULT_WIFI_PASSWORD;
    preferences.putString("ssid", wifiSsid);
    preferences.putString("password", wifiPassword);
  }
  if (wifiSsid.isEmpty()) {
    Serial.println("WIFI: no saved credentials");
    closeMenu();
    showPopup("connection", "WIFI", "NO SAVED NETWORK");
    return;
  }

  preferences.putString("mode", "wifi");
  activeMode = "wifi";
  stopHttp();
  stopBle();
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(true);
  WiFi.setAutoReconnect(true);
  WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
  wifiConnected = false;
  wifiAttemptStarted = millis();
  prepareConnectionScreen("WIFI", "CONNECTING " + wifiSsid);
  Serial.printf("MODE: WiFi only; connecting SSID=%s\n", wifiSsid.c_str());
}

void switchToBluetooth() {
  preferences.putString("mode", "bluetooth");
  activeMode = "bluetooth";
  stopHttp();
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_OFF);
  // A quick Bluetooth switch removes the old central and advertises again so
  // the next phone/navigation bridge has priority.
  stopBle();
  startBle();
  prepareConnectionScreen("BLUETOOTH", "READY TO CONNECT");
  Serial.println("MODE: Bluetooth LE only; fresh advertising started");
}

void handleConnectionState() {
  if (activeMode == "wifi") {
    const bool connected = WiFi.status() == WL_CONNECTED;
    if (connected && !wifiConnected) {
      wifiConnected = true;
      configTime(GMT_OFFSET_SECONDS, DAYLIGHT_OFFSET_SECONDS, "pool.ntp.org",
                 "time.nist.gov", "time.google.com");
      startHttp();
      if (menuView == MenuView::Info) {
        drawConnectionDetails();
      } else if (menuView == MenuView::Closed) {
        showPopup("connection", "WIFI", "CONNECTED TO " + wifiSsid);
        popupUntil = millis() + 2500;
      }
      Serial.printf("WIFI: connected SSID=%s IP=%s\n", wifiSsid.c_str(),
                    WiFi.localIP().toString().c_str());
    } else if (!connected) {
      if (wifiConnected) {
        wifiConnected = false;
        wifiAttemptStarted = millis();
        if (menuView == MenuView::Info) drawConnectionDetails();
        Serial.println("WIFI: connection lost; reconnecting");
      }
      if (millis() - wifiAttemptStarted >= WIFI_TIMEOUT_MS) {
        wifiAttemptStarted = millis();
        WiFi.disconnect(false, false);
        WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
        Serial.printf("WIFI: retrying SSID=%s\n", wifiSsid.c_str());
      }
    }
  } else if (activeMode == "bluetooth") {
    const bool connected = bleConnected;
    if (connected != observedBleConnected) {
      observedBleConnected = connected;
      bleDisconnectedAt = connected ? 0 : millis();
      if (menuView == MenuView::Info) {
        drawConnectionDetails();
      } else if (!navigationVisible && menuView == MenuView::Closed) {
        showPopup("connection", "BLUETOOTH",
                  connected ? "CONNECTED" : "READY TO CONNECT");
        popupUntil = millis() + (connected ? 2500 : POPUP_DURATION_MS);
      }
    }
    // An interrupted phone link must not leave an obsolete turn on a bike.
    // Short BLE hiccups get a grace period for automatic reconnection.
    if (!connected && bleDisconnectedAt != 0 && navigationVisible &&
        millis() - bleDisconnectedAt >= NAVIGATION_LINK_LOST_MS) {
      navigationVisible = false;
      navigationOnScreen = false;
      lastNavigationKey = "";
      if (menuView == MenuView::Closed && detailsUntil == 0 && popupUntil == 0)
        renderClock(true);
      Serial.println("DISPLAY: navigation cleared after BLE link loss");
    }
  }
  refreshConnectionIndicator();
}

void applyPendingModeSwitch() {
  if (pendingModeAt == 0 ||
      static_cast<int32_t>(millis() - pendingModeAt) < 0) {
    return;
  }
  const String mode = pendingMode;
  const bool useDefaultWifi = pendingDefaultWifi;
  pendingModeAt = 0;
  pendingMode = "";
  pendingDefaultWifi = false;
  if (mode == "bluetooth") {
    switchToBluetooth();
  } else if (mode == "wifi") {
    switchToWifi(useDefaultWifi);
  }
}

void setup() {
  Serial.begin(115200);
  delay(1200);
  setCpuFrequencyMhz(80);
  Serial.printf("\n%s firmware %s\n", BLE_NAME, FIRMWARE_VERSION);
  Serial.println("Display: ST7735 128x160");
  Serial.println("Button 1: tap GPIO38 for WiFi SuBo; menu next");
  Serial.println("Button 2: tap GPIO39 for fresh Bluetooth; menu select");
  Serial.println("Button 3: tap GPIO0 for menu; do not hold during reset");
  applyVietnamTimezone();
  Serial.println("TIME: timezone UTC+7 configured");

  pinMode(wifiButton.pin, INPUT_PULLUP);
  wifiButton.lastRawPressed = digitalRead(wifiButton.pin) == LOW;
  wifiButton.stablePressed = wifiButton.lastRawPressed;
  wifiButton.changedAt = millis();
  pinMode(bluetoothButton.pin, INPUT_PULLUP);
  bluetoothButton.lastRawPressed =
      digitalRead(bluetoothButton.pin) == LOW;
  bluetoothButton.stablePressed = bluetoothButton.lastRawPressed;
  bluetoothButton.changedAt = millis();
  pinMode(menuButton.pin, INPUT_PULLUP);
  menuButton.lastRawPressed = digitalRead(menuButton.pin) == LOW;
  menuButton.stablePressed = menuButton.lastRawPressed;
  menuButton.changedAt = millis();

  tftSPI.begin(TFT_SCLK, TFT_MISO, TFT_MOSI, TFT_CS);
  tft.initR(INITR_BLACKTAB);
  tft.setRotation(0);
  tft.invertDisplay(false);
  drawDisplayBootScreen();

  preferences.begin("monitor", false);
  applyTheme(preferences.getBool("lightTheme", false));
  commandQueue = xQueueCreate(4, sizeof(QueuedCommand));
  activeMode = preferences.isKey("mode") ? preferences.getString("mode", "") : "";
  wifiSsid = preferences.isKey("ssid") ? preferences.getString("ssid", "") : "";
  wifiPassword = preferences.isKey("password") ? preferences.getString("password", "") : "";

  if (activeMode.isEmpty() && wifiSsid.isEmpty() &&
      strlen(DEFAULT_WIFI_SSID) > 0) {
    wifiSsid = DEFAULT_WIFI_SSID;
    wifiPassword = DEFAULT_WIFI_PASSWORD;
    preferences.putString("ssid", wifiSsid);
    preferences.putString("password", wifiPassword);
    preferences.putString("mode", "wifi");
    activeMode = "wifi";
    Serial.printf("WIFI: using configured SSID=%s\n", wifiSsid.c_str());
  }

  if (activeMode == "wifi" && !wifiSsid.isEmpty()) {
    switchToWifi();
  } else if (activeMode == "bluetooth") {
    switchToBluetooth();
  } else {
    startSetupMode();
  }
}

void loop() {
  if (httpStarted) server.handleClient();
  QueuedCommand queued{};
  if (commandQueue != nullptr &&
      xQueueReceive(commandQueue, &queued, 0) == pdTRUE) {
    processCommand(queued.payload);
  }
  handleButtons();
  applyPendingModeSwitch();
  handleConnectionState();

  if (menuView != MenuView::Closed &&
      millis() - menuLastInput >= MENU_TIMEOUT_MS) {
    Serial.println("MENU: timeout");
    closeMenu();
  }

  if (detailsUntil != 0 &&
      static_cast<int32_t>(millis() - detailsUntil) >= 0) {
    Serial.println("DISPLAY: connection details timeout");
    restoreMainScreen();
  }

  if (detailsUntil == 0 && popupUntil != 0 &&
      static_cast<int32_t>(millis() - popupUntil) >= 0) {
    popupUntil = 0;
    if (navigationVisible) {
      drawNavigation(navigationManeuver, navigationDistanceMeters,
                     navigationStreet, navigationExitNumber, navigationTurnAngle);
      navigationOnScreen = true;
      Serial.println("DISPLAY: navigation restored after popup");
    } else {
      if (activeMode == "setup") drawSetupScreen(true);
      else renderClock(true);
    }
  }

  if (menuView == MenuView::Closed && detailsUntil == 0 && popupUntil == 0 &&
      millis() - lastDraw >= DRAW_INTERVAL_MS) {
    lastDraw = millis();
    if (activeMode == "setup") {
      drawSetupScreen();
    } else {
      renderClock();
    }
  }
  if (menuView == MenuView::Closed && navigationOnScreen &&
      detailsUntil == 0 && popupUntil == 0 &&
      blinkTurnArrow(navigationManeuver, navigationDistanceMeters) &&
      millis() - lastNavigationBlink >= NAVIGATION_BLINK_MS) {
    lastNavigationBlink = millis();
    navigationArrowVisible = !navigationArrowVisible;
    drawNavigationArrow(navigationManeuver, navigationDistanceMeters,
                        navigationArrowVisible, navigationExitNumber,
                        navigationTurnAngle);
  }
  delay(10);
}
