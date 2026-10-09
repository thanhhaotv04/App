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
#include <esp_timer.h>
#include <esp_system.h>

#include "secrets.h"
#include "qr_assets.h"
#include "clock_timers.h"
#include "speed_state.h"
#include "street_layout.h"
#include "hardware_pins.h"

SpeedState speedState;
String lastRenderedSpeed;

constexpr char SERVICE_UUID[] = "7e6d0001-5b1a-4d8f-9a2c-320001000001";
constexpr char COMMAND_UUID[] = "7e6d0002-5b1a-4d8f-9a2c-320001000002";
constexpr char BLE_NAME[] = "ESP32-NavRide";
constexpr char FIRMWARE_VERSION[] = "1.3.30";
constexpr char SETUP_SSID[] = "ESP32-NavRide-Setup";
constexpr size_t SETUP_PASSWORD_LENGTH = 12;
constexpr uint32_t WIFI_TIMEOUT_MS = 12000;
constexpr uint32_t DRAW_INTERVAL_MS = 1000;
constexpr uint32_t POPUP_DURATION_MS = 8000;
constexpr uint32_t DETAILS_DURATION_MS = 10000;
constexpr uint32_t MENU_TIMEOUT_MS = 30000;
constexpr uint32_t BUTTON_DEBOUNCE_MS = 60;
constexpr uint32_t MENU_HOLD_MS = 2000;
constexpr uint32_t CONNECTION_SEARCH_MS = 20000;
constexpr uint32_t AUTH_LOCK_MS = 60000;
constexpr uint32_t STATUS_BLINK_MS = 500;
constexpr uint32_t NAVIGATION_BLINK_MS = 500;
constexpr uint32_t NAVIGATION_LINK_LOST_MS = 15000;
constexpr uint32_t ROAD_PAGE_INTERVAL_MS = 3500;
constexpr int16_t CLOCK_HEIGHT = 32;
constexpr int16_t STREET_WIDTH = 81;
constexpr int16_t SPEED_X = 87;
constexpr int16_t SPEED_WIDTH = 39;
constexpr bool elapsedAtLeast(uint32_t now, uint32_t started, uint32_t duration) {
  return static_cast<uint32_t>(now - started) >= duration;
}
static_assert(!elapsedAtLeast(1999, 0, MENU_HOLD_MS) &&
                  elapsedAtLeast(2000, 0, MENU_HOLD_MS) &&
                  !elapsedAtLeast(19999, 0, CONNECTION_SEARCH_MS) &&
                  elapsedAtLeast(20000, 0, CONNECTION_SEARCH_MS) &&
                  elapsedAtLeast(15, UINT32_MAX - 19999, CONNECTION_SEARCH_MS),
              "Button hold and radio timeout must use wrap-safe boundaries");
static_assert(10 * 6 + 2 <= 64 && 5 * 6 <= 33 && 4 * 6 <= 28,
              "Date, timer badge and connection label must fit the top row");
static_assert(5 * 6 * 4 <= 128 && 10 * 6 * 2 <= 128,
              "Offline time and full date must fit the 128-pixel display");
static_assert(6 * 12 <= STREET_WIDTH && 13 * 6 <= STREET_WIDTH &&
                  2 + STREET_WIDTH < SPEED_X && SPEED_X + SPEED_WIDTH <= 126,
              "Street and speed columns must not overlap");
static_assert(2 * 6 * 3 <= SPEED_WIDTH && 3 * 6 * 2 <= SPEED_WIDTH &&
                  101 + 8 * 5 < 145,
              "Enlarged speed digits must fit above the unit");
static_assert(5 + (6 + SETUP_PASSWORD_LENGTH) * 6 <= 128,
              "Setup AP password must fit the TFT width");
constexpr uint32_t MODE_SWITCH_DELAY_MS = 250;
constexpr int TURN_ARROW_SHOW_METERS = 2000;
constexpr int TURN_ARROW_BLINK_METERS = 200;
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
                  !blinkTurnAt(200) && blinkTurnAt(199),
              "Navigation thresholds must be strict at 2 km and 200 m");
constexpr int roundaboutVisibleDegrees(int magnitude, int exitNumber) {
  // OsmAnd's small-icon minimum arc is about 49 degrees for an 8px entry.
  // Its zero-rotation case represents a full lap for exit 2+, not a first exit.
  return magnitude == 0 ? (exitNumber < 2 ? 49 : 311)
         : magnitude < 49 ? (exitNumber >= 3 ? 311 : 49)
         : magnitude > 311 ? (exitNumber <= 1 ? 49 : 311)
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
                  roundaboutSweepDegrees(-110, 3, false) == -290 &&
                  roundaboutSweepDegrees(90, 3, false) == -90 &&
                  roundaboutSweepDegrees(-90, 3, false) == -270 &&
                  roundaboutSweepDegrees(180, 1, false) == -49 &&
                  roundaboutSweepDegrees(180, 2, false) == -311,
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
uint32_t wifiDisconnectedAt = 0;
bool wifiSearching = false;
bool bleSearching = false;
bool setupSearching = false;
bool setupApActive = false;
uint32_t wifiSearchStartedAt = 0;
uint32_t bleSearchStartedAt = 0;
uint32_t setupSearchStartedAt = 0;
bool clockOnlyMode = false;
bool offlineFrameDrawn = false;
String lastOfflineTime;
String lastOfflineDate;
String activeMode = "setup";
String wifiSsid;
String wifiPassword;
String setupPassword;
uint32_t pairingPin = 0;
uint8_t authFailures = 0;
uint32_t authLockedUntil = 0;
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
uint32_t lastRoadPageAt = 0;
uint8_t roadPage = 0;
uint8_t roadPageCount = 1;
enum class MenuView : uint8_t {
  Closed, List, Info, QrList, QrCode, ClockList, Stopwatch,
  TimerList, TimerActive, TimerEdit, Alarm
};
MenuView menuView = MenuView::Closed;
uint8_t menuSelection = 0;
uint32_t menuLastInput = 0;
bool lightTheme = false;
uint32_t popupUntil = 0;
uint32_t navigationBannerUntil = 0;
bool deferredPopup = false;
uint32_t detailsUntil = 0;
uint32_t lastDraw = 0;
uint32_t wifiAttemptStarted = 0;
uint32_t pendingModeAt = 0;
String pendingMode;
bool pendingDefaultWifi = false;
bool clockFrameDrawn = false;
bool setupFrameDrawn = false;
String lastSetupStatus;
String lastRenderedTime;
String lastRenderedDate;
String lastRenderedStatus;
ClockTimers clockTimers;
String lastBadgeKey;
String lastClockToolValue;
String timerDescription;
uint8_t timerHour = 0;
uint8_t timerMinute = 0;
uint8_t timerEditField = 0;
bool timerEditorReady = false;
uint32_t lastAlarmFrame = 0;
uint32_t lastClockToolsDraw = 0;
bool alarmWhite = false;

uint64_t monotonicMs() { return static_cast<uint64_t>(esp_timer_get_time()) / 1000; }

struct ButtonState {
  uint8_t pin;
  bool stablePressed;
  bool lastRawPressed;
  uint32_t changedAt;
};

ButtonState wifiButton{BUTTON_WIFI, false, false, 0};
ButtonState bluetoothButton{BUTTON_BLUETOOTH, false, false, 0};
ButtonState menuButton{BUTTON_MENU, false, false, 0};
uint32_t menuPressedAt = 0;
bool menuLongHandled = false;

void showPopup(const String &kind, const String &title, const String &body);
void drawNavigationBanner();
void drawNavigation(const String &maneuver, int distanceMeters,
                    const String &street, int exitNumber = 0,
                    int turnAngle = 999);
void switchToBluetooth();
void switchToWifi(bool useDefaultCredentials = false);
void toggleClockOnlyMode();

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
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type,X-NavRide-Pin");
  server.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  server.send(code, "application/json", body);
}

bool authorizeHttp() {
  const uint32_t now = millis();
  if (authLockedUntil != 0 && static_cast<int32_t>(now - authLockedUntil) < 0) {
    sendJson("{\"error\":\"too_many_attempts\"}", 429);
    return false;
  }
  authLockedUntil = 0;
  char expected[7];
  snprintf(expected, sizeof(expected), "%06u", static_cast<unsigned>(pairingPin));
  if (server.header("X-NavRide-Pin") != expected) {
    if (++authFailures >= 5) {
      authFailures = 0;
      authLockedUntil = now + AUTH_LOCK_MS;
    }
    sendJson("{\"error\":\"pairing_required\"}", 401);
    return false;
  }
  authFailures = 0;
  return true;
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

void drawClockBadge(bool force = false) {
  if (clockOnlyMode || menuView != MenuView::Closed ||
      detailsUntil != 0 || popupUntil != 0 ||
      clockTimers.ringing) return;
  const uint64_t now = monotonicMs();
  const uint64_t elapsed = clockTimers.elapsed(now);
  const String sw = clockTimers.stopwatchRunning || elapsed > 0
      ? String(clockTimers.stopwatchRunning ? "SW" : "PA") +
            String(static_cast<unsigned long>(elapsed / 60000)) + "m" : "";
  const String timer = clockTimers.timerRunning
      ? "TM" + String(static_cast<unsigned long>(ClockTimers::remainingMinutes(
            clockTimers.remaining(now)))) + "m" : "";
  const bool showStopwatch = !sw.isEmpty() &&
      (timer.isEmpty() || (millis() / 3000) % 2 == 0);
  String badge = showStopwatch ? sw : timer;
  if (badge.length() > 5 && badge.endsWith("m")) badge.remove(badge.length() - 1);
  if (badge.length() > 5) badge = badge.substring(0, 4) + "~";
  if (!force && badge == lastBadgeKey) return;
  lastBadgeKey = badge;
  tft.fillRect(66, 0, 33, 14, COLOR_BACKGROUND);
  drawText(badge, 66 + (33 - badge.length() * 6) / 2, 3, 1,
           showStopwatch && !clockTimers.stopwatchRunning ? COLOR_WAIT : COLOR_ACCENT);
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
    if (!wifiSearching) return "OFF";
    return (millis() / STATUS_BLINK_MS) % 2 == 0 ? "WifiWait" : "";
  }
  if (activeMode == "bluetooth") {
    if (bleConnected) return "BLT";
    if (!bleSearching) return "OFF";
    return (millis() / STATUS_BLINK_MS) % 2 == 0 ? "BLTWait" : "";
  }
  return "SET";
}

void drawClockStaticLayout() {
  // The clock occupies exactly one fifth of the 160-pixel display.
  tft.drawFastHLine(4, CLOCK_HEIGHT - 1, 120, COLOR_PANEL);
}

void resetClockRenderCache() {
  lastRenderedTime = "";
  lastRenderedDate = "";
  lastRenderedStatus = "";
  lastRenderedSpeed = "";
}

void drawSpeed(bool force = false) {
  if (clockOnlyMode || menuView != MenuView::Closed ||
      detailsUntil != 0 || popupUntil != 0 ||
      clockTimers.ringing || activeMode == "setup") return;
  const bool connected = activeMode == "bluetooth" ? bleConnected
                       : activeMode == "wifi" && WiFi.status() == WL_CONNECTED;
  const int speed = speedState.visible(millis(), connected);
  const String label = speed < 0 ? "--" : String(speed);
  const String key = label + (navigationOnScreen ? ":nav" : ":clock");
  if (!force && key == lastRenderedSpeed) return;
  lastRenderedSpeed = key;
  const uint16_t bg = navigationOnScreen ? COLOR_PANEL : COLOR_BACKGROUND;
  if (force) {
    tft.fillRect(SPEED_X, 100, SPEED_WIDTH, 60, bg);
    if (navigationOnScreen)
      tft.drawFastVLine(85, 100, 59, COLOR_BACKGROUND);
    drawText("km/h", SPEED_X + (SPEED_WIDTH - 24) / 2, 146, 1, COLOR_ACCENT, bg);
  } else {
    tft.fillRect(SPEED_X, 100, SPEED_WIDTH, 42, bg);
  }
  const uint8_t scaleX = label.length() == 1 ? 5 : label.length() == 2 ? 3 : 2;
  const int16_t x = SPEED_X + (SPEED_WIDTH - label.length() * 6 * scaleX) / 2;
  tft.setTextSize(scaleX, 5);
  tft.setTextColor(speed < 0 ? COLOR_WAIT : COLOR_TEXT, bg);
  tft.setCursor(x, 101);
  tft.print(label);
}

void drawClockStatus(const String &status) {
  tft.fillRect(100, 0, 28, 14, COLOR_BACKGROUND);
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
  } else if (status == "OFF") {
    drawText("OFF", 106, 3, 1, COLOR_WAIT);
  }
  lastRenderedStatus = status;
}

void refreshConnectionIndicator() {
  if (clockOnlyMode || !clockFrameDrawn || detailsUntil != 0 ||
      menuView != MenuView::Closed || activeMode == "setup") return;
  const String status = clockStatusKey();
  if (status != lastRenderedStatus) drawClockStatus(status);
  if (!clockTimers.ringing) drawSpeed();
}

void renderClock(bool restorePopupRegion = false) {
  if (clockOnlyMode) return;
  if (clockTimers.ringing) return;
  const bool frameChanged = !clockFrameDrawn || restorePopupRegion;
  // The full frame is drawn only when entering the clock. Normal ticks and
  // popup restoration update only the dirty rectangles below.
  if (!clockFrameDrawn) {
    tft.fillScreen(COLOR_BACKGROUND);
    drawClockStaticLayout();
    clockFrameDrawn = true;
    resetClockRenderCache();
  } else if (restorePopupRegion) {
    // Notifications live below the clock, so restoring one never touches the
    // date, connection indicator or clock in the top fifth.
    tft.fillRect(0, CLOCK_HEIGHT, 128, 160 - CLOCK_HEIGHT, COLOR_BACKGROUND);
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

  if (dateText != lastRenderedDate) {
    tft.fillRect(0, 0, 64, 14, COLOR_BACKGROUND);
    drawText(dateText, 2, 3, 1,
             valid ? COLOR_TEXT : COLOR_WAIT);
    lastRenderedDate = dateText;
  }
  if (timeText != lastRenderedTime) {
    tft.fillRect(0, 14, 128, 17, COLOR_BACKGROUND);
    drawCentered(timeText, 15, 2, valid ? COLOR_TEXT : COLOR_WAIT);
    lastRenderedTime = timeText;
  }
  drawSpeed(frameChanged);

  const String status = clockStatusKey();
  if (status != lastRenderedStatus) drawClockStatus(status);
  drawClockBadge(frameChanged);
}

void renderOfflineClock() {
  if (!clockOnlyMode || clockTimers.ringing || menuView != MenuView::Closed) return;
  if (!offlineFrameDrawn) {
    tft.fillScreen(COLOR_BACKGROUND);
    offlineFrameDrawn = true;
    lastOfflineTime = "";
    lastOfflineDate = "";
  }
  String timeText = "--:--";
  String dateText = "--/--/----";
  const bool valid = clockValid();
  if (valid) {
    tm localTime{};
    const time_t current = time(nullptr);
    localtime_r(&current, &localTime);
    char timeBuffer[8];
    char dateBuffer[16];
    strftime(timeBuffer, sizeof(timeBuffer), "%H:%M", &localTime);
    strftime(dateBuffer, sizeof(dateBuffer), "%d/%m/%Y", &localTime);
    timeText = timeBuffer;
    dateText = dateBuffer;
  }
  if (timeText != lastOfflineTime) {
    tft.fillRect(0, 0, 128, 40, COLOR_BACKGROUND);
    drawCentered(timeText, 2, 4, valid ? COLOR_TEXT : COLOR_WAIT);
    lastOfflineTime = timeText;
  }
  if (dateText != lastOfflineDate) {
    tft.fillRect(0, 53, 128, 20, COLOR_BACKGROUND);
    drawCentered(dateText, 55, 2, valid ? COLOR_ACCENT : COLOR_WAIT);
    lastOfflineDate = dateText;
  }
}

void drawSetupStatus() {
  const char *label = bleConnected ? "BLE CONNECTED"
      : setupApActive && WiFi.softAPgetStationNum() > 0 ? "AP CONNECTED"
      : setupSearching && (millis() / STATUS_BLINK_MS) % 2 == 0
          ? "WiFi BLT" : "";
  if (lastSetupStatus == label) return;
  lastSetupStatus = label;
  tft.fillRect(0, 124, 128, 11, COLOR_BACKGROUND);
  if (label[0] != '\0')
    drawCentered(label, 126, 1,
                 setupSearching && !bleConnected ? COLOR_WAIT : COLOR_OK);
}

void drawSetupScreen(bool force = false) {
  if (clockTimers.ringing) return;
  if (setupFrameDrawn && !force) return;
  tft.fillScreen(COLOR_BACKGROUND);
  if (!setupSearching && !setupApActive && !bleConnected) {
    drawCentered("SEARCH OFF", 13, 2, COLOR_WAIT);
    drawCentered("No active link", 50, 1);
    drawCentered("2: Retry Bluetooth", 75, 1, COLOR_ACCENT);
    drawCentered("Hold 3: Clock", 91, 1, COLOR_ACCENT);
    drawCentered("Restart for setup AP", 118, 1, COLOR_WAIT);
    setupFrameDrawn = true;
    clockFrameDrawn = false;
    return;
  }
  drawCentered("SETUP", 8, 2, COLOR_ACCENT);
  drawText(setupApActive ? "IP: 192.168.4.1" : "WIFI AP: OFF", 5, 34, 1);
  if (setupApActive) {
    drawText("WIFI AP:", 5, 46, 1);
    drawText(SETUP_SSID, 5, 58, 1);
    drawText("Pass: " + setupPassword, 5, 70, 1);
  }
  drawText("BLE: " + String(BLE_NAME), 5, 85, 1, COLOR_ACCENT);
  drawText("PIN: " + String(pairingPin), 5, 102, 1, COLOR_ACCENT);
  drawText("Use WiFi or BLE", 5, 114, 1, COLOR_WAIT);
  tft.drawFastHLine(4, 135, 120, COLOR_PANEL);
  lastSetupStatus = "#";
  drawSetupStatus();
  setupFrameDrawn = true;
  clockFrameDrawn = false;
}

String clippedText(const String &value, size_t maxLength) {
  if (value.length() <= maxLength) return value;
  if (maxLength < 2) return value.substring(0, maxLength);
  return value.substring(0, maxLength - 1) + "~";
}

void restoreMainScreen() {
  if (clockTimers.ringing) return;
  menuView = MenuView::Closed;
  detailsUntil = 0;
  popupUntil = 0;
  clockFrameDrawn = false;
  setupFrameDrawn = false;
  if (clockOnlyMode) {
    offlineFrameDrawn = false;
    renderOfflineClock();
  } else if (activeMode == "setup") {
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

  if (clockOnlyMode) {
    method = "CLOCK";
    state = "LINKS OFF";
    ssid = "--";
    ip = "--";
  } else if (activeMode == "wifi") {
    const bool connected = WiFi.status() == WL_CONNECTED;
    method = "WIFI";
    state = connected ? "CONNECTED" : wifiSearching ? "SEARCHING" : "OFF";
    ssid = wifiSsid.isEmpty() ? WiFi.SSID() : wifiSsid;
    ip = connected ? WiFi.localIP().toString() : "--";
    rssi = connected ? String(WiFi.RSSI()) + " dBm" : "--";
  } else if (activeMode == "bluetooth") {
    method = "BLT";
    state = bleConnected ? "CONNECTED" : bleSearching ? "SEARCHING" : "OFF";
    ssid = "--";
    ip = "--";
  }

  tft.fillScreen(COLOR_BACKGROUND);
  drawCentered("ESP32 INFO", 5, 2, COLOR_ACCENT);
  tft.drawFastHLine(4, 25, 120, COLOR_PANEL);
  drawText("DEV: " + String(BLE_NAME), 4, 31, 1);
  drawText("METHOD: " + method, 4, 45, 1,
           method == "WIFI" ? COLOR_OK : COLOR_ACCENT);
  drawText("STATE: " + state, 4, 59, 1,
           state == "CONNECTED" ? COLOR_OK : COLOR_WAIT);
  drawText("SSID: " + clippedText(toDisplayAscii(ssid), 14), 4, 73, 1);
  drawText("IP: " + ip, 4, 87, 1, COLOR_WAIT);
  drawText("RSSI: " + rssi, 4, 101, 1);
  drawText("PIN: " + String(pairingPin), 4, 115, 1, COLOR_ACCENT);
  drawText("FW: " + String(FIRMWARE_VERSION), 4, 129, 1);
  tft.drawFastHLine(4, 143, 120, COLOR_PANEL);
  drawText("B3: MENU", 4, 149, 1, COLOR_ACCENT);

  Serial.println("MENU: connection details displayed");
}

String durationText(uint64_t seconds) {
  char value[24];
  snprintf(value, sizeof(value), "%02llu:%02u:%02u",
           static_cast<unsigned long long>(seconds / 3600),
           static_cast<unsigned>((seconds / 60) % 60),
           static_cast<unsigned>(seconds % 60));
  return String(value);
}

void drawClockTool(bool force = false) {
  const bool stopwatch = menuView == MenuView::Stopwatch;
  const uint64_t now = monotonicMs();
  const String value = durationText(stopwatch ? clockTimers.elapsed(now) / 1000
      : (clockTimers.remaining(now) + 999) / 1000);
  if (force) {
    tft.fillScreen(COLOR_BACKGROUND);
    drawCentered(stopwatch ? "STOPWATCH" : "TIMER", 8, 2, COLOR_ACCENT);
    drawText(stopwatch ? "1 Reset" : "1 Cancel", 8, 111, 1);
    drawText(stopwatch ? (clockTimers.stopwatchRunning ? "2 Pause" : "2 Start / Resume")
                       : "2 Background", 8, 126, 1);
    drawText("3 Background", 8, 149, 1, COLOR_WAIT);
    lastClockToolValue = "";
  }
  if (value == lastClockToolValue) return;
  lastClockToolValue = value;
  tft.fillRect(2, 41, 124, 54, COLOR_BACKGROUND);
  drawCentered(value, 44, 2);
  drawCentered(stopwatch ? (clockTimers.stopwatchRunning ? "Running"
                             : clockTimers.elapsed(now) == 0 ? "Ready" : "Paused")
                         : (clockTimers.timerRunning ? timerDescription : "No timer"),
               78, 1, COLOR_WAIT);
}

void drawTimerEditor() {
  tft.fillScreen(COLOR_BACKGROUND);
  drawCentered("AT TIME", 8, 2, COLOR_ACCENT);
  if (!timerEditorReady) {
    drawCentered("Sync time first", 52, 1, COLOR_WAIT);
    drawCentered("Connect phone", 75, 1);
    drawCentered("or WiFi", 88, 1);
    drawText("2 Retry", 8, 126, 1);
  } else {
    char value[6];
    snprintf(value, sizeof(value), "%02u:%02u", timerHour, timerMinute);
    drawCentered(value, 48, 3);
    drawCentered(timerEditField == 0 ? "Set hour (24h)"
                 : timerEditField == 1 ? "Set minute" : "Ready to start", 83, 1, COLOR_WAIT);
    if (timerEditField < 2)
      tft.drawFastHLine(timerEditField == 0 ? 19 : 73, 75, 36, COLOR_ACCENT);
    drawText(timerEditField == 2 ? "1 Change" : "1 Increase", 8, 112, 1);
    drawText(timerEditField == 2 ? "2 Start" : "2 Next", 8, 126, 1);
  }
  drawText("3 Back", 8, 149, 1, COLOR_WAIT);
}

void openTimerEditor() {
  menuView = MenuView::TimerEdit;
  timerEditField = 0;
  timerEditorReady = clockValid();
  if (timerEditorReady) {
    time_t initial = time(nullptr) + 300;
    tm local{};
    localtime_r(&initial, &local);
    timerHour = local.tm_hour;
    timerMinute = local.tm_min;
  }
  drawTimerEditor();
}

void startClockTimer(uint64_t duration, const String &description) {
  clockTimers.startTimer(monotonicMs(), duration);
  timerDescription = description;
  menuView = MenuView::TimerActive;
  lastBadgeKey = "";
  drawClockTool(true);
  Serial.printf("CLOCK: timer started %llu seconds (%s)\n",
                static_cast<unsigned long long>(duration / 1000), description.c_str());
}

bool updateClockTools() {
  if (clockTimers.update(monotonicMs())) {
    menuView = MenuView::Alarm;
    popupUntil = 0;
    deferredPopup = false;
    navigationBannerUntil = 0;
    detailsUntil = 0;
    navigationOnScreen = false;
    clockFrameDrawn = false;
    setupFrameDrawn = false;
    lastAlarmFrame = millis() - 700;
    Serial.println("CLOCK: timer expired; press any button to dismiss");
  }
  if (!clockTimers.ringing) return false;
  if (millis() - lastAlarmFrame >= 700 || menuView != MenuView::Alarm) {
    menuView = MenuView::Alarm;
    lastAlarmFrame = millis();
    alarmWhite = !alarmWhite;
    const uint16_t bg = alarmWhite ? ST77XX_WHITE : ST77XX_BLACK;
    const uint16_t fg = alarmWhite ? ST77XX_BLACK : ST77XX_WHITE;
    tft.fillScreen(bg);
    drawCentered("TIME UP", 52, 2, fg, bg);
    drawCentered("Press any button", 97, 1, fg, bg);
    drawCentered("to stop", 112, 1, fg, bg);
  }
  return true;
}

constexpr uint8_t MENU_ITEM_COUNT = 6;
constexpr uint8_t nextMenuItem(uint8_t index, uint8_t count = MENU_ITEM_COUNT) {
  return (index + 1) % count;
}
static_assert(nextMenuItem(5) == 0 && nextMenuItem(1, 2) == 0,
              "Main and QR menu selections must wrap");

bool isListMenu() {
  return menuView == MenuView::List || menuView == MenuView::QrList ||
         menuView == MenuView::ClockList || menuView == MenuView::TimerList;
}

uint8_t menuItemCount() {
  return menuView == MenuView::QrList || menuView == MenuView::ClockList
             ? 2 : MENU_ITEM_COUNT;
}

void drawQrCode() {
  const bool bank = menuSelection == 0;
  const uint8_t size = bank ? BANK_QR_SIZE : PROFILE_QR_SIZE;
  if (size == 0) {
    tft.fillScreen(ST77XX_WHITE);
    drawCentered(bank ? "BANK" : "PROFILE", 8, 1, ST77XX_BLACK, ST77XX_WHITE);
    drawCentered("QR not set", 70, 1, ST77XX_BLACK, ST77XX_WHITE);
    drawCentered("Button 3: Back", 146, 1, ST77XX_BLACK, ST77XX_WHITE);
    return;
  }
  const uint8_t *bits = bank ? BANK_QR_BITS : PROFILE_QR_BITS;
  const uint8_t scale = 128 / (size + 8);
  const int16_t side = (size + 8) * scale;
  const int16_t x0 = (128 - side) / 2 + 4 * scale;
  const int16_t y0 = 17 + (124 - side) / 2 + 4 * scale;
  // Preserve a four-module white quiet zone at integer scale in both themes.
  // No timed redraw while scanning; navigation keeps updating behind the menu.
  tft.fillScreen(ST77XX_WHITE);
  drawCentered(bank ? "BANK" : "PROFILE", 3, 1,
               ST77XX_BLACK, ST77XX_WHITE);
  const uint8_t rowBytes = (size + 7) / 8;
  tft.startWrite();
  for (uint8_t y = 0; y < size; ++y) {
    for (uint8_t x = 0; x < size; ++x) {
      if (pgm_read_byte(bits + y * rowBytes + x / 8) & (0x80 >> (x % 8)))
        tft.writeFillRect(x0 + x * scale, y0 + y * scale, scale, scale,
                          ST77XX_BLACK);
    }
  }
  tft.endWrite();
  if (bank) drawCentered(BANK_QR_CAPTION, 137, 1, ST77XX_BLACK, ST77XX_WHITE);
  drawCentered("1 NEXT 3 BACK", 149, 1, ST77XX_BLACK, ST77XX_WHITE);
  Serial.printf("MENU: QR %s modules=%u scale=%u\n",
                bank ? "Bank" : "Profile", size, scale);
}

static_assert((BANK_QR_SIZE == 0 || ((BANK_QR_SIZE + 8) * (128 / (BANK_QR_SIZE + 8)) <= 124 &&
                  128 / (BANK_QR_SIZE + 8) >= 2)) &&
                  (PROFILE_QR_SIZE == 0 || ((PROFILE_QR_SIZE + 8) * (128 / (PROFILE_QR_SIZE + 8)) <= 124 &&
                  128 / (PROFILE_QR_SIZE + 8) >= 2)),
              "QR codes must fit with quiet zones and at least 2px modules");

void drawMenuRow(uint8_t index) {
  const int16_t y = 32 + index * 18;
  const bool selected = index == menuSelection;
  const uint16_t background = selected ? COLOR_ACCENT : COLOR_PANEL;
  const uint16_t foreground = selected ? COLOR_BACKGROUND : COLOR_TEXT;
  tft.fillRect(4, y, 120, 17, background);
  const char *timerLabels[] = {"5 min", "15 min", "30 min", "60 min", "At time", "View timer"};
  const String label = menuView == MenuView::QrList ? (index == 0 ? "Bank" : "Profile")
                       : menuView == MenuView::ClockList ? (index == 0 ? "Stopwatch" : "Timer")
                       : menuView == MenuView::TimerList ? timerLabels[index]
                       : index == 0 ? "WiFi"
                       : index == 1 ? "Bluetooth"
                       : index == 2 ? (lightTheme ? "Theme: Light" : "Theme: Dark")
                       : index == 3 ? "ESP32 Info" : index == 4 ? "QR" : "Clock";
  drawText(label, 9, y + 5, 1, foreground, background);
  if (menuView == MenuView::List && !clockOnlyMode &&
      ((index == 0 && activeMode == "wifi") ||
       (index == 1 && activeMode == "bluetooth"))) {
    const bool connected = index == 0 ? WiFi.status() == WL_CONNECTED : bleConnected;
    const bool searching = index == 0 ? wifiSearching : bleSearching;
    drawText(connected ? "ON" : searching ? "..." : "OFF", 104, y + 5, 1,
             selected ? foreground : connected ? COLOR_OK : COLOR_WAIT,
             background);
  }
}

void drawMenu() {
  tft.fillScreen(COLOR_BACKGROUND);
  drawCentered(menuView == MenuView::QrList ? "QR"
               : menuView == MenuView::ClockList ? "CLOCK"
               : menuView == MenuView::TimerList ? "TIMER" : "MENU", 5, 2, COLOR_ACCENT);
  tft.drawFastHLine(4, 29, 120, COLOR_PANEL);
  const uint8_t count = menuItemCount();
  for (uint8_t index = 0; index < count; ++index) {
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
  navigationBannerUntil = 0;
  navigationOnScreen = false;
  drawMenu();
  Serial.println("MENU: opened");
}

void closeMenu() {
  if (menuView == MenuView::Closed) return;
  Serial.println("MENU: closed");
  restoreMainScreen();
  if (deferredPopup) {
    deferredPopup = false;
    const String kind = popupKind;
    const String title = popupTitle;
    const String body = popupBody;
    showPopup(kind, title, body);
  }
}

void selectMenuItem() {
  menuLastInput = millis();
  if (menuView == MenuView::ClockList) {
    if (menuSelection == 0) {
      menuView = MenuView::Stopwatch;
      drawClockTool(true);
    } else {
      menuView = MenuView::TimerList;
      menuSelection = 0;
      drawMenu();
    }
    return;
  }
  if (menuView == MenuView::TimerList) {
    if (menuSelection < 4) {
      const uint8_t minutes[] = {5, 15, 30, 60};
      startClockTimer(static_cast<uint64_t>(minutes[menuSelection]) * 60000,
                       String(minutes[menuSelection]) + " min");
    } else if (menuSelection == 4) {
      openTimerEditor();
    } else {
      menuView = MenuView::TimerActive;
      drawClockTool(true);
    }
    return;
  }
  if (menuView == MenuView::QrList) {
    menuView = MenuView::QrCode;
    menuLastInput = millis();
    drawQrCode();
    return;
  }
  if (menuView != MenuView::List) return;
  menuLastInput = millis();
  if (menuSelection == 0) {
    if (activeMode == "wifi" && !clockOnlyMode &&
        (wifiSearching || WiFi.status() == WL_CONNECTED)) {
      closeMenu();
    } else {
      switchToWifi();
    }
  } else if (menuSelection == 1) {
    if (activeMode == "bluetooth" && !clockOnlyMode &&
        (bleSearching || bleConnected)) {
      closeMenu();
    } else {
      switchToBluetooth();
    }
  } else if (menuSelection == 2) {
    applyTheme(!lightTheme);
    preferences.putBool("lightTheme", lightTheme);
    drawMenu();
    Serial.printf("MENU: theme=%s\n", lightTheme ? "light" : "dark");
  } else if (menuSelection == 3) {
    menuView = MenuView::Info;
    drawConnectionDetails();
    Serial.println("MENU: device info");
  } else if (menuSelection == 4) {
    menuView = MenuView::QrList;
    menuSelection = 0;
    drawMenu();
    Serial.println("MENU: QR list");
  } else {
    menuView = MenuView::ClockList;
    menuSelection = 0;
    drawMenu();
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
  if (menuChanged && menuButton.stablePressed) {
    menuPressedAt = menuButton.changedAt;
    menuLongHandled = false;
  }

  if (clockTimers.ringing) {
    if ((wifiChanged && !wifiButton.stablePressed) ||
        (bluetoothChanged && !bluetoothButton.stablePressed) ||
        (menuChanged && !menuButton.stablePressed)) {
      clockTimers.cancelTimer();
      lastBadgeKey = "";
      restoreMainScreen();
      Serial.println("CLOCK: alarm dismissed; theme restored");
    }
    return;
  }

  if (menuButton.stablePressed && !menuLongHandled &&
      elapsedAtLeast(millis(), menuPressedAt, MENU_HOLD_MS)) {
    menuLongHandled = true;
    toggleClockOnlyMode();
    return;
  }
  const bool shortMenuPress = menuChanged && !menuButton.stablePressed &&
                              !menuLongHandled;
  if (menuChanged && !menuButton.stablePressed) menuLongHandled = false;
  if (shortMenuPress) {
    menuLastInput = millis();
    if (menuView == MenuView::Closed) {
      openMenu();
    } else if (menuView == MenuView::Info) {
      menuView = MenuView::List;
      drawMenu();
    } else if (menuView == MenuView::QrCode) {
      menuView = MenuView::QrList;
      drawMenu();
    } else if (menuView == MenuView::QrList) {
      menuView = MenuView::List;
      menuSelection = 4;
      drawMenu();
    } else if (menuView == MenuView::ClockList) {
      menuView = MenuView::List;
      menuSelection = 5;
      drawMenu();
    } else if (menuView == MenuView::TimerList) {
      menuView = MenuView::ClockList;
      menuSelection = 1;
      drawMenu();
    } else if (menuView == MenuView::TimerEdit) {
      menuView = MenuView::TimerList;
      menuSelection = 4;
      drawMenu();
    } else {
      closeMenu();
    }
  }
  if (wifiChanged && !wifiButton.stablePressed) {
    if (isListMenu()) {
      const uint8_t previous = menuSelection;
      menuSelection = nextMenuItem(menuSelection, menuItemCount());
      menuLastInput = millis();
      drawMenuRow(previous);
      drawMenuRow(menuSelection);
      Serial.printf("MENU: selected %u\n", menuSelection);
    } else if (menuView == MenuView::Stopwatch) {
      clockTimers.resetStopwatch();
      lastBadgeKey = "";
      drawClockTool(true);
      Serial.println("CLOCK: stopwatch reset");
    } else if (menuView == MenuView::TimerActive) {
      clockTimers.cancelTimer();
      lastBadgeKey = "";
      menuView = MenuView::TimerList;
      menuSelection = 0;
      menuLastInput = millis();
      drawMenu();
      Serial.println("CLOCK: timer cancelled");
    } else if (menuView == MenuView::TimerEdit && timerEditorReady) {
      if (timerEditField == 0) timerHour = (timerHour + 1) % 24;
      else if (timerEditField == 1) timerMinute = (timerMinute + 1) % 60;
      else timerEditField = 0;
      drawTimerEditor();
    } else if (menuView == MenuView::QrCode) {
      menuSelection = nextMenuItem(menuSelection, 2);
      menuLastInput = millis();
      drawQrCode();
    } else if (menuView == MenuView::Closed) {
      if (activeMode == "wifi" && wifiSsid == DEFAULT_WIFI_SSID &&
          WiFi.status() == WL_CONNECTED) {
        Serial.println("BUTTON G38: saved WiFi already connected");
      } else {
        Serial.println("BUTTON G38: quick saved WiFi");
        switchToWifi(true);
      }
    }
  }
  if (bluetoothChanged && !bluetoothButton.stablePressed) {
    if (isListMenu()) {
      selectMenuItem();
    } else if (menuView == MenuView::Stopwatch) {
      clockTimers.toggleStopwatch(monotonicMs());
      lastBadgeKey = "";
      drawClockTool(true);
      Serial.printf("CLOCK: stopwatch %s\n", clockTimers.stopwatchRunning ? "running" : "paused");
    } else if (menuView == MenuView::TimerActive) {
      closeMenu();
    } else if (menuView == MenuView::TimerEdit) {
      if (!timerEditorReady) openTimerEditor();
      else if (timerEditField < 2) {
        ++timerEditField;
        drawTimerEditor();
      } else if (!clockValid()) {
        timerEditorReady = false;
        drawTimerEditor();
      } else {
        time_t current = time(nullptr);
        tm local{};
        localtime_r(&current, &local);
        const uint32_t duration = ClockTimers::secondsUntil(
            local.tm_hour, local.tm_min, local.tm_sec, timerHour, timerMinute);
        char target[20];
        snprintf(target, sizeof(target), "%s %02u:%02u",
                 duration >= static_cast<uint32_t>(86400 - local.tm_hour * 3600 -
                        local.tm_min * 60 - local.tm_sec) ? "Tomorrow" : "Until",
                 timerHour, timerMinute);
        startClockTimer(static_cast<uint64_t>(duration) * 1000, String(target));
      }
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

void drawPopup() {
  // Keep the compact clock visible above all notification content.
  tft.fillRect(2, CLOCK_HEIGHT + 2, 124, 158 - CLOCK_HEIGHT, COLOR_PANEL);
  const String header = popupKind == "task"
                            ? "TASK"
                            : popupKind == "navigation" ? "NAVIGATION"
                            : popupKind == "connection" ? "CONNECTION"
                                                          : "NOTIFICATION";
  drawText(header, 7, 47, 1, COLOR_ACCENT, COLOR_PANEL);
  drawWrapped(popupTitle, 63, COLOR_TEXT, COLOR_PANEL, 2);
  drawWrapped(popupBody, 95, COLOR_WAIT, COLOR_PANEL, 5);
}

void drawNavigationBanner() {
  tft.fillRect(2, 136, STREET_WIDTH, 22, COLOR_PANEL);
  drawText("NOTICE", 4, 137, 1, COLOR_WAIT, COLOR_PANEL);
  drawText(clippedText(popupTitle, 13), 4, 148, 1, COLOR_TEXT, COLOR_PANEL);
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
  tft.fillRect(62, 34, 64, 35, COLOR_PANEL);
  const String distance = formatNavigationDistance(distanceMeters);
  const int split = distance.indexOf(' ');
  const String number = distance.substring(0, split);
  // Five digits fit this half-width region; very long distances stay legible.
  const uint8_t size = number.length() <= 5 ? 2 : 1;
  drawText(number, 62 + (64 - number.length() * 6 * size) / 2, 39, size,
           COLOR_WAIT, COLOR_PANEL);
  drawText(distance.substring(split + 1), 88, 59, 1, COLOR_WAIT, COLOR_PANEL);
}

bool isTurnManeuver(const String &maneuver) {
  return maneuver == "left" || maneuver == "right" ||
         maneuver == "slight_left" || maneuver == "slight_right" ||
         maneuver == "sharp_left" || maneuver == "sharp_right" ||
         maneuver == "keep_left" || maneuver == "keep_right" ||
         maneuver == "u_turn" || maneuver == "u_turn_right" ||
         maneuver == "roundabout" || maneuver == "roundabout_left";
}

bool showTurnArrow(const String &maneuver, int distanceMeters) {
  return isTurnManeuver(maneuver) && showTurnAt(distanceMeters);
}

bool blinkTurnArrow(const String &maneuver, int distanceMeters) {
  return isTurnManeuver(maneuver) && blinkTurnAt(distanceMeters);
}

void drawThickLine(int16_t x0, int16_t y0, int16_t x1, int16_t y1,
                   int16_t width, uint16_t color) {
  const float dx = x1 - x0;
  const float dy = y1 - y0;
  const float length = sqrtf(dx * dx + dy * dy);
  if (length == 0) return;
  const int16_t ox = lroundf(-dy * width / (2 * length));
  const int16_t oy = lroundf(dx * width / (2 * length));
  tft.fillTriangle(x0 + ox, y0 + oy, x0 - ox, y0 - oy,
                   x1 + ox, y1 + oy, color);
  tft.fillTriangle(x1 + ox, y1 + oy, x0 - ox, y0 - oy,
                   x1 - ox, y1 - oy, color);
  tft.fillCircle(x0, y0, width / 2, color);
  tft.fillCircle(x1, y1, width / 2, color);
}

void drawNavigationArrow(const String &maneuver, int distanceMeters,
                         bool visible, int exitNumber = 0,
                         int turnAngle = 999) {
  // The arrow is the only region touched by the 500 ms blink.
  tft.fillRect(2, 34, 58, 66, COLOR_PANEL);
  if (!visible) return;
  if (maneuver == "off_route") {
    // OsmAnd OFFR: an interrupted forward arrow, never a turn.
    tft.fillRect(26, 88, 8, 11, COLOR_TEXT);
    tft.fillRect(26, 69, 8, 12, COLOR_TEXT);
    tft.fillTriangle(30, 46, 16, 70, 44, 70, COLOR_TEXT);
  } else if (showTurnArrow(maneuver, distanceMeters) &&
             (maneuver == "slight_left" || maneuver == "slight_right" ||
              maneuver == "sharp_left" || maneuver == "sharp_right" ||
              maneuver == "keep_left" || maneuver == "keep_right")) {
    const bool right = maneuver.endsWith("right");
    const bool keep = maneuver.startsWith("keep");
    const bool sharp = maneuver.startsWith("sharp");
    const int16_t startX = right ? 22 : 38;
    const int16_t bendX = right ? 42 : 18;
    drawThickLine(startX, 95, startX, 78, 8, COLOR_TEXT);
    drawThickLine(startX, 78, bendX, 62, 8, COLOR_TEXT);
    if (keep) {
      drawThickLine(bendX, 62, bendX, 55, 8, COLOR_TEXT);
      tft.fillTriangle(bendX, 45, bendX - 12, 62, bendX + 12, 62,
                       COLOR_TEXT);
    } else if (sharp) {
      // Sharp turn folds back after the approach, unlike a slight turn.
      const int16_t tipX = right ? 51 : 9;
      drawThickLine(bendX, 62, tipX, 77, 8, COLOR_TEXT);
      if (right) tft.fillTriangle(55, 89, 39, 77, 54, 68, COLOR_TEXT);
      else tft.fillTriangle(5, 89, 21, 77, 6, 68, COLOR_TEXT);
    } else {
      if (right) tft.fillTriangle(53, 50, 34, 52, 48, 70, COLOR_TEXT);
      else tft.fillTriangle(7, 50, 26, 52, 12, 70, COLOR_TEXT);
    }
  } else if (showTurnArrow(maneuver, distanceMeters) &&
      (maneuver == "left" || maneuver == "right")) {
    const bool right = maneuver == "right";
    // Approach from the bottom, follow a rounded 90-degree corner, then turn.
    const int16_t cornerX = right ? 22 : 38;
    tft.fillCircle(cornerX, 70, 12, COLOR_TEXT);
    tft.fillCircle(cornerX, 70, 4, COLOR_PANEL);
    if (right) {
      tft.fillRect(22, 58, 13, 25, COLOR_PANEL);
      tft.fillRect(10, 70, 25, 13, COLOR_PANEL);
      tft.fillRect(10, 69, 9, 30, COLOR_TEXT);
      tft.fillRect(22, 58, 20, 9, COLOR_TEXT);
      tft.fillTriangle(56, 62, 39, 50, 39, 74, COLOR_TEXT);
    } else {
      tft.fillRect(26, 58, 12, 25, COLOR_PANEL);
      tft.fillRect(26, 70, 25, 13, COLOR_PANEL);
      tft.fillRect(41, 69, 9, 30, COLOR_TEXT);
      tft.fillRect(18, 58, 20, 9, COLOR_TEXT);
      tft.fillTriangle(4, 62, 21, 50, 21, 74, COLOR_TEXT);
    }
  } else if (showTurnArrow(maneuver, distanceMeters) &&
             (maneuver == "u_turn" || maneuver == "u_turn_right")) {
    // Mirror the return lane for OsmAnd's TU and TRU types.
    const bool right = maneuver == "u_turn_right";
    tft.fillCircle(29, 71, 18, COLOR_TEXT);
    tft.fillCircle(29, 71, 11, COLOR_PANEL);
    tft.fillRect(9, 71, 41, 24, COLOR_PANEL);
    tft.fillRoundRect(right ? 41 : 9, 66, 8, 27, 4, COLOR_TEXT);
    tft.fillRoundRect(right ? 9 : 41, 66, 8, 32, 4, COLOR_TEXT);
    if (right) tft.fillTriangle(45, 99, 33, 88, 54, 88, COLOR_TEXT);
    else tft.fillTriangle(13, 99, 4, 88, 25, 88, COLOR_TEXT);
  } else if (showTurnArrow(maneuver, distanceMeters) &&
             (maneuver == "roundabout" || maneuver == "roundabout_left")) {
    // Exit ordinal alone does not determine direction. Only a real OsmAnd
    // turn angle may place the exit arrow; notifications have no such angle.
    constexpr int16_t centerX = 30;
    constexpr int16_t centerY = 71;
    constexpr int16_t outerRadius = 19;
    constexpr int16_t innerRadius = 12;
    const bool clockwise = maneuver == "roundabout_left";
    tft.fillRoundRect(centerX - 4, centerY + outerRadius - 1, 8, 10, 3,
                      COLOR_TEXT);
    if (turnAngle < -180 || turnAngle > 180) {
      tft.drawCircle(centerX, centerY, outerRadius, COLOR_TEXT);
      tft.drawCircle(centerX, centerY, innerRadius, COLOR_TEXT);
    } else {
      const int angle = turnAngle;
      const uint16_t ringOutline = lightTheme ? 0xAD55 : 0x630C;
      tft.drawCircle(centerX, centerY, outerRadius, ringOutline);
      tft.drawCircle(centerX, centerY, innerRadius, ringOutline);
      // OsmAnd uses t + 180 for left-hand circulation and t - 180 for
      // right-hand circulation. Clamp near the entry so the exit stays legible.
      const int sweep = roundaboutSweepDegrees(angle, exitNumber,
                                               clockwise);
      // OsmAnd draws the exits passed before the chosen one as outline steps.
      if (exitNumber > 1) {
        // Keep at most five passed-exit ticks readable on the small TFT.
        const int steps = min(exitNumber, 6);
        for (int ordinal = 1; ordinal < steps; ++ordinal) {
          const float theta = (sweep * ordinal / steps) * DEG_TO_RAD;
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
    tft.fillCircle(29, 73, 20, COLOR_TEXT);
    tft.fillCircle(29, 73, 12, COLOR_PANEL);
    tft.fillCircle(29, 73, 5, COLOR_OK);
  } else {
    tft.fillRect(25, 62, 9, 37, COLOR_TEXT);
    tft.fillTriangle(29, 44, 12, 66, 46, 66, COLOR_TEXT);
  }
}

void drawNavigationStreet(const String &street, bool resetPage) {
  String name = toDisplayAscii(street);
  name.trim();
  if (name.isEmpty()) name = "--";
  StreetLine lines[8]{};
  uint8_t count = wrapStreet(name.c_str(), 6, lines, 8);
  const bool compact = count > 2;
  if (compact) count = wrapStreet(name.c_str(), 13, lines, 8);
  roadPageCount = (count + 1) / 2;
  if (resetPage || roadPage >= roadPageCount) roadPage = 0;
  lastRoadPageAt = millis();
  tft.fillRect(2, 100, STREET_WIDTH, 34, COLOR_PANEL);
  for (uint8_t row = 0; row < 2; ++row) {
    const uint8_t index = roadPage * 2 + row;
    if (index < count) {
      const uint8_t scaleX = compact ? 1 : 2;
      const String line = name.substring(lines[index].start,
                                         lines[index].start + lines[index].length);
      tft.setTextSize(scaleX, 2);
      tft.setTextColor(COLOR_TEXT, COLOR_PANEL);
      tft.setCursor(2 + (STREET_WIDTH - line.length() * 6 * scaleX) / 2,
                    101 + row * 16);
      tft.print(line);
    }
  }
  tft.fillRect(98, 92, 28, 8, COLOR_PANEL);
  if (roadPageCount > 1) {
    for (uint8_t page = 0; page < roadPageCount; ++page)
      tft.drawFastHLine(100 + page * 5, 96, 3,
                       page == roadPage ? COLOR_TEXT : COLOR_WAIT);
  }
}

void drawNavigation(const String &maneuver, int distanceMeters,
                    const String &street, int exitNumber, int turnAngle) {
  if (clockTimers.ringing) return;
  tft.fillRect(2, CLOCK_HEIGHT + 2, 124, 158 - CLOCK_HEIGHT, COLOR_PANEL);
  navigationArrowVisible = true;
  lastNavigationBlink = millis();
  drawNavigationArrow(maneuver, distanceMeters, true, exitNumber, turnAngle);
  const bool roundabout = maneuver == "roundabout" || maneuver == "roundabout_left";
  drawText(roundabout && exitNumber > 0 ? "EXIT " + String(exitNumber)
                                      : maneuver == "left" ? "LEFT"
                                      : maneuver == "slight_left" ? "SL LEFT"
                                      : maneuver == "sharp_left" ? "SH LEFT"
                                      : maneuver == "keep_left" ? "KEEP L"
                                      : maneuver == "right" ? "RIGHT"
                                      : maneuver == "slight_right" ? "SL RIGHT"
                                      : maneuver == "sharp_right" ? "SH RIGHT"
                                      : maneuver == "keep_right" ? "KEEP R"
                                      : maneuver == "u_turn" ? "U-TURN"
                                      : maneuver == "u_turn_right" ? "U-TURN R"
                                      : maneuver == "off_route" ? "OFF ROUTE"
                                      : maneuver == "arrive" ? "ARRIVE" : "AHEAD",
           65, 75, 1, COLOR_TEXT, COLOR_PANEL);
  drawText("ONTO", 65, 89, 1, COLOR_WAIT, COLOR_PANEL);
  drawNavigationStreet(street, true);
  drawNavigationDistance(distanceMeters);
  navigationOnScreen = true;
  drawClockBadge(true);
  drawSpeed(true);
  if (navigationBannerUntil != 0) drawNavigationBanner();
}

void showPopup(const String &kind, const String &title, const String &body) {
  if (clockTimers.ringing) return;
  popupKind = kind;
  popupTitle = toDisplayAscii(title);
  popupBody = toDisplayAscii(body);
  if (detailsUntil != 0 || menuView != MenuView::Closed) {
    deferredPopup = true;
    return;
  }
  if (navigationVisible) {
    if (!navigationOnScreen) {
      drawNavigation(navigationManeuver, navigationDistanceMeters,
                     navigationStreet, navigationExitNumber, navigationTurnAngle);
    }
    navigationBannerUntil = millis() + 3000;
    drawNavigationBanner();
    return;
  }
  navigationOnScreen = false;
  popupUntil = millis() + POPUP_DURATION_MS;
  drawPopup();
  Serial.println("DISPLAY: popup displayed");
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
  Serial.println("DISPLAY: navigation updated");
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
  if (clockOnlyMode) return false;
  JsonDocument document;
  if (payload.length() > MAX_COMMAND_BYTES ||
      deserializeJson(document, payload)) {
    sendBleStatus("error:invalid_json");
    return false;
  }

  const char *command = document["command"] | "";
  const int requestId = document["requestId"] | 0;
  const auto acknowledge = [requestId, &document](const String &status) {
    // Invalid commands must not change the local clock.
    if (document["timestamp"].is<long>()) {
      const time_t incoming = document["timestamp"].as<time_t>();
      if (incoming > 1700000000) {
        timeval now{incoming, 0};
        settimeofday(&now, nullptr);
      }
    }
    sendBleStatus(requestId > 0 ? status + ":" + String(requestId) : status);
  };
  if (!document["apiVersion"].is<int>() ||
      document["apiVersion"].as<int>() != 1) {
    sendBleStatus("error:api_version");
    return false;
  }
  if (strcmp(command, "ping") == 0) {
    acknowledge("ok:ping");
    return true;
  }

  if (strcmp(command, "speed") == 0) {
    if (document["kmh"].isUnbound() ||
        (!document["kmh"].isNull() && (!document["kmh"].is<int>() ||
          document["kmh"].as<int>() < 0 || document["kmh"].as<int>() > 300))) {
      sendBleStatus("error:speed");
      return false;
    }
    const int value = document["kmh"].isNull() ? -1 : document["kmh"].as<int>();
    const bool changed = value != speedState.kmh;
    speedState.update(value, millis());
    if (changed) Serial.println("DISPLAY: speed updated");
    if (clockFrameDrawn && menuView == MenuView::Closed && detailsUntil == 0 &&
        popupUntil == 0 &&
        !clockTimers.ringing && activeMode != "setup") drawSpeed();
    acknowledge("ok:speed");
    return true;
  }

  if (strcmp(command, "push_notification") == 0 ||
      strcmp(command, "push_task") == 0) {
    const String title = document["title"] | BLE_NAME;
    const String body = document["body"] | (strcmp(command, "push_task") == 0
                                                ? "You have a new task"
                                                : "New notification");
    Serial.printf("COMMAND: %s\n", command);
    showPopup(strcmp(command, "push_task") == 0 ? "task" : "notice", title,
              body);
    acknowledge("ok:popup");
    return true;
  }

  if (strcmp(command, "navigation") == 0) {
    const String maneuver = document["maneuver"] | "straight";
    if (maneuver != "left" && maneuver != "right" &&
        maneuver != "straight" && maneuver != "u_turn" &&
        maneuver != "slight_left" && maneuver != "slight_right" &&
        maneuver != "sharp_left" && maneuver != "sharp_right" &&
        maneuver != "keep_left" && maneuver != "keep_right" &&
        maneuver != "u_turn_right" && maneuver != "off_route" &&
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
    if (clearPopup) {
      popupUntil = 0;
      navigationBannerUntil = 0;
      deferredPopup = false;
    } else {
      navigationVisible = false;
      navigationOnScreen = false;
      navigationBannerUntil = 0;
      lastNavigationKey = "";
    }
    if (menuView == MenuView::Closed && popupUntil == 0) {
      if (detailsUntil != 0) {
        if (clearPopup) restoreMainScreen();
      } else if (navigationVisible) {
        drawNavigation(navigationManeuver, navigationDistanceMeters,
                       navigationStreet, navigationExitNumber, navigationTurnAngle);
      } else if (activeMode == "setup") {
        drawSetupScreen(true);
      } else {
        renderClock(true);
      }
    }
    Serial.println(clearPopup ? "DISPLAY: popup cleared"
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
               NimBLEConnInfo &connectionInfo) override {
    if (!connectionInfo.isAuthenticated()) {
      sendBleStatus("error:pairing_required");
      return;
    }
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
  bleSearching = true;
  bleSearchStartedAt = millis();
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
  NimBLEDevice::setSecurityAuth(true, true, false);
  NimBLEDevice::setSecurityPasskey(pairingPin);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY);
  bleServer = NimBLEDevice::createServer();
  static NavRideServerCallbacks serverCallbacks;
  bleServer->setCallbacks(&serverCallbacks);
  bleServer->advertiseOnDisconnect(true);
  NimBLEService *service = bleServer->createService(SERVICE_UUID);
  NimBLECharacteristic *command = service->createCharacteristic(
      COMMAND_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_AUTHEN);
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
  bleSearching = false;
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
    static const char *requestHeaders[] = {"X-NavRide-Pin"};
    server.collectHeaders(requestHeaders, 1);
    server.on("/api/health", HTTP_GET, []() {
    if (!authorizeHttp()) return;
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
    if (!authorizeHttp()) return;
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
    if (!authorizeHttp()) return;
    if (processCommand(server.arg("plain"))) {
      sendJson("{\"ok\":true}");
    } else {
      sendJson("{\"error\":\"invalid_command\"}", 400);
    }
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
  clockOnlyMode = false;
  offlineFrameDrawn = false;
  wifiConnected = false;
  wifiSearching = false;
  startBle();
  if (setupPassword.length() != SETUP_PASSWORD_LENGTH) {
    char generated[SETUP_PASSWORD_LENGTH + 1];
    snprintf(generated, sizeof(generated), "NR%08lX%02X",
             static_cast<unsigned long>(esp_random()),
             static_cast<unsigned>(esp_random() & 0xFF));
    setupPassword = generated;
    preferences.putString("apPassword", setupPassword);
  }
  WiFi.mode(WIFI_AP);
  setupApActive = WiFi.softAP(SETUP_SSID, setupPassword.c_str());
  setupSearching = true;
  setupSearchStartedAt = millis();
  if (setupApActive) startHttp();
  Serial.println("SETUP: access point ready");
  drawSetupScreen(true);
}

void prepareConnectionScreen(const String &title, const String &message) {
  menuView = MenuView::Closed;
  detailsUntil = 0;
  popupUntil = 0;
  deferredPopup = false;
  navigationBannerUntil = 0;
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
  clockOnlyMode = false;
  offlineFrameDrawn = false;
  setupSearching = false;
  setupApActive = false;
  speedState.update(-1, millis());
  stopHttp();
  stopBle();
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(true);
  WiFi.setAutoReconnect(false);
  WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
  wifiConnected = false;
  wifiDisconnectedAt = 0;
  wifiSearching = true;
  wifiSearchStartedAt = millis();
  wifiAttemptStarted = millis();
  prepareConnectionScreen("WIFI", "CONNECTING " + wifiSsid);
  Serial.println("MODE: WiFi only; connecting to saved network");
}

void switchToBluetooth() {
  preferences.putString("mode", "bluetooth");
  activeMode = "bluetooth";
  clockOnlyMode = false;
  offlineFrameDrawn = false;
  setupSearching = false;
  setupApActive = false;
  wifiSearching = false;
  wifiDisconnectedAt = 0;
  speedState.update(-1, millis());
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

void toggleClockOnlyMode() {
  if (clockOnlyMode) {
    clockOnlyMode = false;
    offlineFrameDrawn = false;
    if (activeMode == "wifi") switchToWifi();
    else if (activeMode == "bluetooth") switchToBluetooth();
    else startSetupMode();
    Serial.println("CLOCK: leaving offline-only display");
    return;
  }
  clockOnlyMode = true;
  menuView = MenuView::Closed;
  detailsUntil = 0;
  popupUntil = 0;
  deferredPopup = false;
  navigationBannerUntil = 0;
  pendingModeAt = 0;
  pendingMode = "";
  navigationVisible = false;
  navigationOnScreen = false;
  lastNavigationKey = "";
  speedState.update(-1, millis());
  stopHttp();
  stopBle();
  WiFi.disconnect(true, false);
  if (setupApActive) WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_OFF);
  wifiConnected = false;
  wifiSearching = false;
  setupSearching = false;
  setupApActive = false;
  clockFrameDrawn = false;
  setupFrameDrawn = false;
  offlineFrameDrawn = false;
  renderOfflineClock();
  Serial.println("CLOCK: offline-only display; WiFi off, BLE advertising off");
}

void handleConnectionState() {
  if (clockOnlyMode) return;
  if (activeMode == "wifi") {
    const bool connected = WiFi.status() == WL_CONNECTED;
    if (connected) {
      wifiSearching = false;
      wifiDisconnectedAt = 0;
      if (!wifiConnected) {
        wifiConnected = true;
        configTime(GMT_OFFSET_SECONDS, DAYLIGHT_OFFSET_SECONDS, "pool.ntp.org",
                   "time.nist.gov", "time.google.com");
        startHttp();
        if (menuView == MenuView::Info) {
          drawConnectionDetails();
        } else if (menuView == MenuView::Closed) {
          showPopup("connection", "WIFI", "CONNECTED TO " + wifiSsid);
          if (!navigationVisible && !deferredPopup) popupUntil = millis() + 2500;
        }
        Serial.println("WIFI: connected");
      }
    } else {
      if (wifiConnected) {
        wifiConnected = false;
        wifiDisconnectedAt = millis();
        stopHttp();
        wifiSearching = true;
        wifiSearchStartedAt = millis();
        wifiAttemptStarted = millis();
        WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
        if (menuView == MenuView::Info) drawConnectionDetails();
        Serial.println("WIFI: connection lost; reconnecting");
      }
      if (wifiSearching && elapsedAtLeast(millis(), wifiSearchStartedAt,
                                          CONNECTION_SEARCH_MS)) {
        wifiSearching = false;
        WiFi.disconnect(true, false);
        WiFi.mode(WIFI_OFF);
        Serial.println("WIFI: 20s search expired; radio off");
      } else if (wifiSearching &&
                 elapsedAtLeast(millis(), wifiAttemptStarted, WIFI_TIMEOUT_MS)) {
        wifiAttemptStarted = millis();
        WiFi.disconnect(false, false);
        WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
        Serial.println("WIFI: retrying saved network");
      }
      if (wifiDisconnectedAt != 0 && navigationVisible &&
          elapsedAtLeast(millis(), wifiDisconnectedAt, NAVIGATION_LINK_LOST_MS)) {
        navigationVisible = false;
        navigationOnScreen = false;
        navigationBannerUntil = 0;
        lastNavigationKey = "";
        if (menuView == MenuView::Closed && detailsUntil == 0 && popupUntil == 0)
          renderClock(true);
        Serial.println("DISPLAY: navigation cleared after WiFi link loss");
      }
    }
  } else if (activeMode == "bluetooth") {
    const bool connected = bleConnected;
    if (connected != observedBleConnected) {
      observedBleConnected = connected;
      bleDisconnectedAt = connected ? 0 : millis();
      bleSearching = !connected;
      if (!connected) bleSearchStartedAt = millis();
      if (menuView == MenuView::Info) {
        drawConnectionDetails();
      } else if (!navigationVisible && menuView == MenuView::Closed) {
        showPopup("connection", "BLUETOOTH",
                  connected ? "CONNECTED" : "READY TO CONNECT");
        if (!navigationVisible && !deferredPopup)
          popupUntil = millis() + (connected ? 2500 : POPUP_DURATION_MS);
      }
    }
    if (!connected && bleSearching &&
        elapsedAtLeast(millis(), bleSearchStartedAt, CONNECTION_SEARCH_MS)) {
      bleSearching = false;
      bleServer->advertiseOnDisconnect(false);
      NimBLEDevice::getAdvertising()->stop();
      Serial.println("BLE: 20s advertising expired; press Button 2 to retry");
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
  } else if (activeMode == "setup") {
    bool changed = false;
    if (bleConnected != observedBleConnected) {
      observedBleConnected = bleConnected;
      changed = true;
    }
    if (bleConnected && setupApActive) {
      stopHttp();
      WiFi.softAPdisconnect(true);
      WiFi.mode(WIFI_OFF);
      setupApActive = false;
      changed = true;
      Serial.println("SETUP: BLE connected; WiFi AP stopped");
    } else if (setupApActive && WiFi.softAPgetStationNum() > 0 && bleSearching) {
      stopBle();
      changed = true;
      Serial.println("SETUP: WiFi client connected; BLE advertising stopped");
    }
    if (setupSearching && elapsedAtLeast(millis(), setupSearchStartedAt,
                                         CONNECTION_SEARCH_MS)) {
      setupSearching = false;
      if (bleStarted) {
        bleServer->advertiseOnDisconnect(false);
        if (!bleConnected) NimBLEDevice::getAdvertising()->stop();
      }
      bleSearching = false;
      changed = true;
      Serial.println("SETUP: 20s discovery expired; idle radios stopped");
    }
    if (!setupSearching && setupApActive && WiFi.softAPgetStationNum() == 0) {
      stopHttp();
      WiFi.softAPdisconnect(true);
      WiFi.mode(WIFI_OFF);
      setupApActive = false;
      changed = true;
      Serial.println("SETUP: unused WiFi AP stopped");
    }
    if (menuView == MenuView::Closed) {
      if (changed) drawSetupScreen(true);
      else if (setupFrameDrawn && setupSearching) drawSetupStatus();
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
  Serial.println("Button 1: tap GPIO38 for saved WiFi; menu next");
  Serial.println("Button 2: tap GPIO39 for fresh Bluetooth; menu select");
  Serial.println("Button 3: tap GPIO0 for menu, hold 2s for offline clock; release before reset");
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
  menuPressedAt = millis();

  tftSPI.begin(TFT_SCLK, TFT_MISO, TFT_MOSI, TFT_CS);
  tft.initR(INITR_BLACKTAB);
  // Reduce runtime SPI ringing with the display's jumper wiring.
  tft.setSPISpeed(TFT_SPI_HZ);
  tft.setRotation(0);
  tft.invertDisplay(false);
  drawDisplayBootScreen();

  preferences.begin("monitor", false);
  pairingPin = preferences.getUInt("pin", 0);
  if (pairingPin < 100000 || pairingPin > 999999) {
    pairingPin = 100000 + esp_random() % 900000;
    preferences.putUInt("pin", pairingPin);
  }
  setupPassword = preferences.getString("apPassword", "");
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
    Serial.println("WIFI: using configured network");
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

  if (updateClockTools()) {
    delay(10);
    return;
  }
  if (millis() - lastClockToolsDraw >= 250) {
    lastClockToolsDraw = millis();
    if (menuView == MenuView::Stopwatch || menuView == MenuView::TimerActive)
      drawClockTool();
    drawClockBadge();
  }

  if ((isListMenu() || menuView == MenuView::Info) &&
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
    if (clockOnlyMode) {
      offlineFrameDrawn = false;
      renderOfflineClock();
    } else if (navigationVisible) {
      drawNavigation(navigationManeuver, navigationDistanceMeters,
                     navigationStreet, navigationExitNumber, navigationTurnAngle);
      navigationOnScreen = true;
      Serial.println("DISPLAY: navigation restored after popup");
    } else {
      if (activeMode == "setup") drawSetupScreen(true);
      else renderClock(true);
    }
  }

  if (navigationBannerUntil != 0 &&
      static_cast<int32_t>(millis() - navigationBannerUntil) >= 0) {
    navigationBannerUntil = 0;
    if (navigationOnScreen && menuView == MenuView::Closed)
      tft.fillRect(2, 136, STREET_WIDTH, 22, COLOR_PANEL);
  }

  if (menuView == MenuView::Closed && detailsUntil == 0 && popupUntil == 0 &&
      millis() - lastDraw >= DRAW_INTERVAL_MS) {
    lastDraw = millis();
    if (clockOnlyMode) {
      renderOfflineClock();
    } else if (activeMode == "setup") {
      drawSetupScreen();
    } else {
      renderClock();
    }
  }
  if (menuView == MenuView::Closed && navigationOnScreen &&
      detailsUntil == 0 && popupUntil == 0 && roadPageCount > 1 &&
      millis() - lastRoadPageAt >= ROAD_PAGE_INTERVAL_MS) {
    roadPage = (roadPage + 1) % roadPageCount;
    drawNavigationStreet(navigationStreet, false);
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
