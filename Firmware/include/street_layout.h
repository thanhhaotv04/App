#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

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
