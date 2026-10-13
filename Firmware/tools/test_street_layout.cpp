#include <cassert>
#include <string>

#include "../include/street_layout.h"

int main() {
  static_assert(STREET_ROWS_PER_PAGE == 3 && STREET_TOP + STREET_HEIGHT == 158,
                "Street names must use the old notification area");
  static_assert(STREET_TOP + 1 + (STREET_ROWS_PER_PAGE - 1) * STREET_ROW_STEP + 16 <= 158,
                "Three rows must fit above the display bottom");
  StreetLine lines[8]{};
  const char *longStreet = "Nguyen Thi Minh Khai";
  assert(wrapStreet(longStreet, 6, lines, 8) > 2);
  static_assert(STREET_COMPACT_CHAR_WIDTH == 9 && STREET_COMPACT_MAX_CHARS == 9,
                "Long street names need two extra pixels between letters");
  assert(wrapStreet(longStreet, STREET_COMPACT_MAX_CHARS, lines, 8) == STREET_ROWS_PER_PAGE);
  assert(wrapStreetCompactFill(longStreet, lines, 8) == STREET_ROWS_PER_PAGE);
  assert(std::string(longStreet + lines[0].start, lines[0].length) == "Nguyen");
  assert(std::string(longStreet + lines[1].start, lines[1].length) == "Thi Minh");
  assert(std::string(longStreet + lines[2].start, lines[2].length) == "Khai");
  assert(lines[1].length * STREET_COMPACT_CHAR_WIDTH <= 81);

  const char *shortStreet = "Nguyen Hue";
  assert(wrapStreet(shortStreet, 6, lines, 8) == 2);
  assert(std::string(shortStreet + lines[0].start, lines[0].length) == "Nguyen");
  assert(std::string(shortStreet + lines[1].start, lines[1].length) == "Hue");

  const char *unbroken = "ABCDEFGHIJKLMNOPQRST";
  assert(wrapStreet(unbroken, STREET_COMPACT_MAX_CHARS, lines, 8) == STREET_ROWS_PER_PAGE);
  assert(lines[0].length == 9 && lines[1].length == 9 && lines[2].length == 2);

  const char *threeRows = "Nguyen Thi Minh Khai Quan 1";
  const uint8_t count = wrapStreet(threeRows, STREET_COMPACT_MAX_CHARS, lines, 8);
  assert(count == 4);
  assert(std::string(threeRows + lines[0].start, lines[0].length) == "Nguyen");
  assert(std::string(threeRows + lines[1].start, lines[1].length) == "Thi Minh");
  assert(std::string(threeRows + lines[2].start, lines[2].length) == "Khai Quan");
  assert(std::string(threeRows + lines[3].start, lines[3].length) == "1");

  // Tên 80 ký tự vẫn được giữ đầy đủ qua các trang, không cắt ở dòng thứ 8.
  const std::string veryLong = std::string("1234567 1234567 1234567 1234567 1234567 ") +
                              "1234567 1234567 1234567 1234567 1234567";
  StreetLine longLines[16]{};
  const uint8_t longCount = wrapStreet(veryLong.c_str(), STREET_COMPACT_MAX_CHARS, longLines, 16);
  assert(longCount == 10);
  assert(longLines[longCount - 1].start + longLines[longCount - 1].length == veryLong.size());
  assert((longCount + STREET_ROWS_PER_PAGE - 1) / STREET_ROWS_PER_PAGE == 4);
  assert(wrapStreetCompactFill(veryLong.c_str(), longLines, 16) == longCount);
  for (uint8_t row = 0; row < longCount; ++row)
    assert(longLines[row].length <= STREET_COMPACT_MAX_CHARS);
  static_assert(STREET_COMPACT_MAX_CHARS * STREET_COMPACT_CHAR_WIDTH <= 81,
                "Bold compact lines must stay inside the road column");
}
