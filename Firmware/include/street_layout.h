#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

constexpr uint8_t STREET_ROWS_PER_PAGE = 3;
constexpr int16_t STREET_TOP = 100;
constexpr int16_t STREET_HEIGHT = 58;
constexpr uint8_t STREET_ROW_STEP = 19;
constexpr uint8_t STREET_COMPACT_CHAR_WIDTH = 9;
constexpr uint8_t STREET_COMPACT_MAX_CHARS = 9;
constexpr int16_t NEXT_TURN_X = 62;
constexpr int16_t NEXT_TURN_TOP = 69;
constexpr int16_t NEXT_TURN_WIDTH = 64;
constexpr int16_t NEXT_TURN_HEIGHT = 31;
constexpr int16_t NEXT_ICON_WIDTH = 24;
constexpr int16_t NEXT_ICON_HEIGHT = 30;
constexpr int16_t STREET_PAGE_MARKER_Y = 156;

struct StreetLine {
  uint8_t start;
  uint8_t length;
};

inline uint8_t wrapStreet(const char *text, uint8_t maxChars,
                          StreetLine *lines, uint8_t capacity) {
  if (maxChars == 0 || capacity == 0) return 0;
  const size_t length = strlen(text);
  size_t start = 0;
  uint8_t count = 0;
  while (start < length && count < capacity) {
    const size_t end = start + maxChars < length ? start + maxChars : length;
    size_t split = end;
    if (end < length) {
      for (size_t pos = end; pos > start; --pos) {
        if (text[pos] == ' ') {
          split = pos;
          break;
        }
      }
    }
    lines[count++] = {static_cast<uint8_t>(start),
                      static_cast<uint8_t>(split - start)};
    start = split;
    while (start < length && text[start] == ' ') ++start;
  }
  return count;
}

inline uint8_t wrapStreetCompactFill(const char *text, StreetLine *lines,
                                     uint8_t capacity) {
  uint8_t count = wrapStreet(text, STREET_COMPACT_MAX_CHARS, lines, capacity);
  if (count != 2) return count;
  // Prefer three readable rows over leaving the third street row empty.
  for (uint8_t width = STREET_COMPACT_MAX_CHARS - 1; width >= 7; --width) {
    count = wrapStreet(text, width, lines, capacity);
    if (count == STREET_ROWS_PER_PAGE) return count;
  }
  return wrapStreet(text, STREET_COMPACT_MAX_CHARS, lines, capacity);
}
