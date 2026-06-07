# VietNam Map Flutter Implementation Plan

Source app: `D:\thanhhao_ws\App\App_VietNam_Map`

Target app: `D:\thanhhao_ws\App\App_VietNam_Map_Flutter\vietnam_map_01`

Guideline used: `D:\thanhhao_ws\App\andrej-karpathy-skills\skills\karpathy-guidelines\SKILL.md`

## Assumptions

- The Flutter app should preserve the web MVP behavior before adding larger mobile-only features.
- Web/desktop support is currently important because Windows Smart App Control has blocked some native build hooks before.
- Native image picking and EXIF should be restored only after the web-safe Flutter build remains stable.

## Success Criteria

- `flutter analyze` passes.
- `flutter test` passes.
- Map orientation matches the original web projection.
- Hovering a province on web/desktop shows that province's name and check-in count.
- Tapping a province opens the check-in form with province prefilled.
- Local check-ins can be added, listed, filtered, opened in detail, marked synced, and deleted.
- Backend sync uses the same API surface as `server.js`.

## Feature Parity Checklist

| Area | Web MVP | Flutter Status | Verify |
| --- | --- | --- | --- |
| Warm visual theme | Done | Done | Visual check |
| Top shell/nav | Done | Partial | Visual check |
| Stats cards | Done | Done | Add/delete check-ins |
| GeoJSON province map | Done | Done | Hover/tap provinces |
| Correct map projection | Done | Done | Compare orientation |
| Province hover tooltip | Done | Done | Hover map |
| Province color by count | Done | Done | Add check-ins |
| Theme toggle | Done | Done | Press app bar theme icon |
| Province-based markers | Web pins empty | Removed | Visited provinces use fill color, not dots |
| Hover recent photos | Done | Done | Hover visited province with photos |
| Map hover performance | Basic SVG events | Done | Cached paths, no per-pixel rebuild |
| Click province to check in | Done | Done | Tap province |
| Recent list | Done | Done | Filter/search |
| Search/source filter | Done | Done | Filter rows/markers |
| Check-in modal | Done | Partial | Save manual check-in |
| Detail drawer | Done | Done | Tap marker/list row |
| Mark synced | Done | Done local | Tap drawer action |
| Delete one | Done | Done local | Tap drawer action |
| Delete all | Done | Pending | Add History/Settings action |
| Import/export JSON | Done | Pending | Add web-safe JSON actions |
| Load sample | Done | Pending | Add seed action |
| Logs tab | Done | Pending | Add lightweight log panel |
| Settings tab | Done | Pending | Add settings route |
| Backend GET sync | Done | Partial | Fetch remote into local |
| Backend POST sync | Done | Partial | POST unsynced items |
| Photo upload | Done | Deferred | Restore after native strategy |

## Next Implementation Order

1. Finish backend parity.
   Verify: add remote fetch, seed, delete all, mark synced endpoints, then run `flutter analyze`.

2. Finish web controls.
   Verify: import/export JSON, load sample, clear data, and a simple logs/settings screen.

3. Restore photo support safely.
   Verify: use separate web file input and native mobile picker paths so Chrome builds do not pull blocked native hooks.

4. Add focused widget tests.
   Verify: app boots, repository add/delete works, filter logic works, and sync service parses backend JSON.
