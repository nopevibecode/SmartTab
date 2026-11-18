# Changelog

## 1.0 - 2026-11-18

First release.

- Tab picks the best enemy where you aim: a front cone first, then score by
  angle and distance, with bonuses (melee range, in combat, raid marks) and
  penalties (neutral mobs, pets, totems, breakable crowd control).
- Aim with your character's facing or with the camera (nameplates on screen).
- Every press ranks again; mobs you just tabbed through are skipped for a few
  seconds, and turning starts a fresh cycle. Shift-Tab goes back.
- Falls back to UnitXP SP3's distance-aware targeting when nothing qualifies.
- Settings window (`/smarttab` or the minimap button) with a live preview of
  the ranking; every press logged to SavedVariables for tuning.
