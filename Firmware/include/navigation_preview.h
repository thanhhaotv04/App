#pragma once

#include <stddef.h>
#include <stdio.h>

inline void formatPreviewNumber(int meters, char *text, size_t capacity) {
  if (meters < 1000) snprintf(text, capacity, "%d", meters);
  else snprintf(text, capacity, "%d.%d", meters / 1000, (meters % 1000) / 100);
}

// IDs match the public OsmAnd ADirectionInfo turn types (1..14).
inline const char *maneuverForTurnType(int type) {
  static constexpr const char *names[] = {
      "", "straight", "left", "slight_left", "sharp_left", "right",
      "slight_right", "sharp_right", "keep_left", "keep_right", "u_turn",
      "u_turn_right", "off_route", "roundabout", "roundabout_left"};
  return type >= 1 && type <= 14 ? names[type] : "";
}

struct TurnPreview {
  int turnType = 0;
  int distanceMeters = -1;
  int exitNumber = 0;
  int turnAngle = 999;

  bool valid() const {
    return turnType >= 1 && turnType <= 14 && turnType != 12 &&
           distanceMeters > 0 && distanceMeters <= 999999 &&
           exitNumber >= 0 && exitNumber <= 99 &&
           (turnAngle == 999 || (turnAngle >= -180 && turnAngle <= 180));
  }

  bool operator==(const TurnPreview &other) const {
    return turnType == other.turnType && distanceMeters == other.distanceMeters &&
           exitNumber == other.exitNumber && turnAngle == other.turnAngle;
  }
};
