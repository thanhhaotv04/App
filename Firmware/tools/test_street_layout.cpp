#include <cassert>
#include <string>

#include "../include/street_layout.h"

int main() {
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
}
