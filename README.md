# SmartTab

Tab targeting for World of Warcraft 1.12.1 (built on OctoWoW) that picks the
enemy **where you are looking**, weighed by **how far it is**, instead of the
client's erratic cycling.

## Requirements

- **SuperWoW** (required): facing, unit positions, nameplate GUIDs and
  targeting by GUID.
- **UnitXP SP3** (optional): exact distances and line of sight, and the
  fallback when no enemy qualifies.

## Setup

1. Install into `Interface\AddOns\SmartTab` and restart the game.
2. Key Bindings → **SmartTab**: bind *Smart target (best / next)* to Tab and
   *Smart target (previous)* to Shift-Tab.
3. Open the settings with `/smarttab` or the minimap button.

## How it picks

- **Candidates:** attackable, living enemies with a nameplate, in line of
  sight, within max range. Critters are skipped; idle neutral mobs are optional.
- **Front cone first:** mobs within the cone (±30° by default, wider in melee
  range) always come before mobs outside it.
- **Score:** `facing weight × angle score + distance weight × distance score`,
  plus bonuses (melee range, in combat, raid mark, skull) and minus penalties
  (neutral, pet, totem, breakable crowd control such as Polymorph, Sap, Blind).
- **Aim:** your character's facing, or the camera (from where nameplates sit
  on screen; set your field of view in the window).
- **Cycling:** every press ranks again. Mobs you tabbed through are skipped
  for a few seconds after your last press, and turning more than a set angle
  starts a fresh cycle. Shift-Tab goes back through the mobs you visited.
- It only acts when you press its key; it never changes your target on its own.

## Commands

| Command | Effect |
|---|---|
| `/smarttab` | settings window with a live preview |
| `/smarttab list` | settings in chat |
| `/smarttab <setting> <value>` | change one, e.g. `/smarttab cone 40` |
| `/smarttab debug` | one chat line per press |
| `/smarttab reset` | defaults |
| `/smarttab clearlog` | empty the press log |

Macros: `/run SmartTab_Next()` and `/run SmartTab_Prev()`.

Each press is logged (candidates, angles, scores) to `SmartTabLog` in
SavedVariables, written on `/reload` or logout.
