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
  assert(wrapStreet(longStreet, 13, lines, 8) == 2);
  assert(std::string(longStreet + lines[0].start, lines[0].length) == "Nguyen Thi");
  assert(std::string(longStreet + lines[1].start, lines[1].length) == "Minh Khai");

  const char *shortStreet = "Nguyen Hue";
  assert(wrapStreet(shortStreet, 6, lines, 8) == 2);
  assert(std::string(shortStreet + lines[0].start, lines[0].length) == "Nguyen");
  assert(std::string(shortStreet + lines[1].start, lines[1].length) == "Hue");

  const char *unbroken = "ABCDEFGHIJKLMNOPQRST";
  assert(wrapStreet(unbroken, 13, lines, 8) == 2);
  assert(lines[0].length == 13 && lines[1].length == 7);

  const char *threeRows = "Duong Nguyen Thi Minh Khai Quan 1";
  const uint8_t count = wrapStreet(threeRows, 13, lines, 8);
  assert(count == STREET_ROWS_PER_PAGE);
  assert(std::string(threeRows + lines[0].start, lines[0].length) == "Duong Nguyen");
  assert(std::string(threeRows + lines[1].start, lines[1].length) == "Thi Minh Khai");
  assert(std::string(threeRows + lines[2].start, lines[2].length) == "Quan 1");

  // Tên 80 ký tự vẫn được giữ đầy đủ qua các trang, không cắt ở dòng thứ 8.
  const std::string veryLong = std::string("1234567 1234567 1234567 1234567 1234567 ") +
                              "1234567 1234567 1234567 1234567 1234567";
  StreetLine longLines[16]{};
  const uint8_t longCount = wrapStreet(veryLong.c_str(), 13, longLines, 16);
  assert(longCount == 10);
  assert(longLines[longCount - 1].start + longLines[longCount - 1].length == veryLong.size());
  assert((longCount + STREET_ROWS_PER_PAGE - 1) / STREET_ROWS_PER_PAGE == 4);
  for (uint8_t row = 0; row < longCount; ++row) assert(longLines[row].length <= 13);
}
