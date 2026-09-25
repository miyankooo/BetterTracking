# TrackingAlert — Memory

Updated 2026-09-25. Decision: TrackingAlert is WoW Forever 1.60.x only; the vanilla feature lives in the separate GatherMate2Alert addon. Verified against Gethe `forever` @ `bd2470a` (1.60.1.70009) and Ketho `forever`. Nothing has run in a client. `lua Tools/harness.lua` passes 79 of 79, which proves logic and wiring, not client behaviour.

## Current state

When a tracked node shows up, it pings and flashes the minimap. Two sources feed one alert:

- The minimap blip source runs the engine hit test on points on the minimap.
- The optional GatherMate2 source post-hooks `Display:addMiniPin`.

It also carries GatherMate2 circle tweaks: size, merge, and hiding icons.

| Item | State |
|---|---|
| Version | 2.0.0, TrackingAlert and GatherMate2Alert merged. `## Interface: 16001` only, `## Author: miyanko`, `## OptionalDeps: GatherMate2`, Addon Compartment fields |
| Git | Committed and pushed on 2026-09-25: `main` = `origin/main`. The previous release is 1.0.0 at `4702355` (blip source only) |
| Vanilla | Users keep GatherMate2Alert (`github.com/miyankooo/GatherMate2Alert`, `main` = `1.15.x-backup` = `a946251`) |

The blip source rests on one capability check, `ns.canProbe` (`Core/Probe.lua:5-7`). It covers `Minimap:UpdateMouseoverAtPoint`, `C_TooltipInfo.GetMinimapMouseover`, `C_Minimap.GetViewRadius` and `VIGNETTE_MINIMAP_UPDATED`, all of which are in 1.60.1.

The GatherMate2 source:

- It attaches only if GatherMate2 loads, and every internal it reads is guarded.
- The native circle size is read off the first circle: 10 px on GatherMate2 `classic`, 12 px on `master`.

Options use Blizzard's native Settings vertical layout, with no canvas:

- Every control is a `Settings.RegisterProxySetting` over `ns.db`, so all 19 `TrackingAlertDB` keys keep their meaning.
- Sections are Alert, Minimap nodes and GatherMate2. Child rows nest with `SetParentInitializer`.
- The node-type mute list is a multi-select `Settings.CreateDropdown`, like Blizzard's Nameplates page.
- Calibration status leads the Calibration tooltip. The button reads Calibrate or Recalibrate.

A one-time 1.0.0 → 2.0.0 migration (`MigrateLegacy` in `Core/Config.lua`) is keyed on the `enabled` field, which only 1.0.0 saved:

- `enabled` becomes `blips`.
- 1.0.0's `sound` meant "default ping" (`false`) or a sound id, so it becomes `sound = true` plus `soundId`.
- `cooldown` snaps to whole seconds, minimum 1.
- The obsolete keys are dropped.

## Blockers, issues, challenges

1. GatherMate2 has no Forever build: upstream `master` is `120007,120100`, last pushed 2026-08-17. The GatherMate2 source stays dormant until it ships.
2. The blip source depends on three runtime unknowns: the coordinate space of `UpdateMouseoverAtPoint` (self-calibrated from a hovered blip), the blip tooltip's `type` and `guid`, and the rotation sign with `rotateMinimap`.
3. Unverified: does `PlaySound(id, "Master", true)` play with effects muted?
4. The Settings page has only been checked against source, never seen rendered. `LIST_DELIMITER` is `","`, so a partial node-type pick may read without a space.
5. The compartment lists only addons enabled for all characters.
6. The installed beta is 69913, the source is 70009.

## Next steps

1. Run `/console scriptErrors 1` first, with Find Herbs or Find Minerals on. Beta checks:

- [ ] Options → AddOns → Tracking Alert shows three section headers. Unticking a parent greys out its nested rows.
- [ ] Picking a sound plays it, and picking the same one again stays silent. Test plays the sound and a gold flash.
- [ ] Hover a blip near the minimap edge: chat reports the calibration. The button then reads Recalibrate, and clicking it clears the calibration. This settles part of issue 2.
- [ ] Ride into nodes: one ping each. Leave and return within 3 minutes: silence. Reset in Remembered nodes makes them ping again.
- [ ] Run `/tra types` after a run and record the tooltip types and whether a `guid` shows.
- [ ] Rotating minimap on, turn in place: no repeat pings. Fly over nodes: silence.
- [ ] Mute sound effects and record whether the alert plays. This settles issue 3.
- [ ] Defaults → These Settings resets everything but keeps the calibration.
- [ ] Right-click the compartment entry with the page open: sound and flash flip live.
- [ ] Without GatherMate2: those rows are greyed out with a red tooltip notice, there's no Node types row, and nothing errors.
- [ ] Upgrading a 1.0.0 save keeps the sound on.
