#include <cassert>
#include <string>

#include "../include/navigation_preview.h"
#include "../include/street_layout.h"

int main() {
  static_assert(NEXT_TURN_TOP == 34 + 35, "Preview must start below primary distance");
  static_assert(NEXT_ICON_WIDTH >= 24 && NEXT_ICON_HEIGHT >= 30,
                "Next-turn arrow must remain large enough to read");
  static_assert(NEXT_TURN_TOP + NEXT_TURN_HEIGHT <= STREET_TOP,
                "Preview must stay above the street and speed columns");
  static_assert(NEXT_TURN_X + NEXT_TURN_WIDTH <= 126 &&
                    NEXT_ICON_HEIGHT <= NEXT_TURN_HEIGHT &&
                    NEXT_TURN_WIDTH - NEXT_ICON_WIDTH - 3 >= 3 * 6 * 2 &&
                    NEXT_TURN_WIDTH - NEXT_ICON_WIDTH - 3 >= 5 * 6,
                "Icon and longest distance must fit on TFT");
  static_assert(STREET_PAGE_MARKER_Y >= STREET_TOP + 1 +
                    (STREET_ROWS_PER_PAGE - 1) * STREET_ROW_STEP + 16 &&
                    STREET_PAGE_MARKER_Y < STREET_TOP + STREET_HEIGHT,
                "Page markers must sit below the third street row");
  for (int distance : {1, 50, 999, 1000, 1600, 9999, 10000, 999999}) {
    char number[8];
    formatPreviewNumber(distance, number, sizeof(number));
    const size_t length = std::string(number).size();
    assert(length * 6 * previewNumberScaleX(length) <= NEXT_TURN_WIDTH - NEXT_ICON_WIDTH - 3);
  }
  char number[8];
  formatPreviewNumber(1600, number, sizeof(number));
  assert(std::string(number) == "1.6");
  assert(previewNumberScaleX(3) == 2 && previewNumberScaleX(5) == 1);
  assert(!TurnPreview{}.valid());
  assert((TurnPreview{2, 1600}.valid()));
  assert((TurnPreview{13, 1200, 4, -90}.valid()));
  assert((TurnPreview{13, 1200, 4, 999}.valid()));
  assert(!(TurnPreview{12, 300}.valid()));
  assert(!(TurnPreview{5, 0}.valid()));
  assert(!(TurnPreview{5, -1}.valid()));
  assert(!(TurnPreview{5, 1000000}.valid()));
  assert(!(TurnPreview{15, 300}.valid()));
  assert(!(TurnPreview{13, 300, 100, 0}.valid()));
  assert(!(TurnPreview{13, 300, 2, 181}.valid()));
  assert((TurnPreview{2, 1600} == TurnPreview{2, 1600}));
  assert(!(TurnPreview{2, 1600} == TurnPreview{5, 1600}));
  for (int type = 1; type <= 14; ++type) assert(std::string(maneuverForTurnType(type)) != "");
  assert(std::string(maneuverForTurnType(2)) == "left");
  assert(std::string(maneuverForTurnType(5)) == "right");
  assert(std::string(maneuverForTurnType(13)) == "roundabout");
  assert(std::string(maneuverForTurnType(14)) == "roundabout_left");
  assert(std::string(maneuverForTurnType(-1)) == "");
  assert(std::string(maneuverForTurnType(15)) == "");
}
