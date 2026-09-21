# TrackingAlert — Development Memory

The single persistent note for this addon. Read it before touching the code instead of re-deriving anything. Written 2026-09-21, the day the addon was created.

**Verified against:** `forever` @ `70ef1b2` (1.60.1.69913), 2026-09-21.

**Shared 1.60 client facts are not in this file.** They live in one place: `Cortex/WoW/Forever Client Facts.md` in the Obsidian vault (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/`). Read that first — this note records only what is specific to this addon. Run `../check-client-facts.sh` to see whether any of it has gone stale.

---

## 1. Status on 2026-09-21

| Item | State |
|---|---|
| Version | 1.0.0, **not committed**, no repo yet |
| Targets | WoW Forever 1.60.x only. `## Interface: 16001`, game type camelot |
| Size | 875 lines: `Core/Config.lua` 52, `Core/Probe.lua` 116, `Core/Geometry.lua` 91, `Core/Scanner.lua` 202, `UI/Options.lua` 113, `Tools/harness.lua` 210, toc 18, README 73 |
| Sources verified | `Gethe/wow-ui-source` `forever` @ `70ef1b2` and the string table of the installed beta binary |
| Offline checks | All five shipped Lua files parse under Lua 5.4. `Tools/harness.lua` 13/13 pass |
| In-game checks | **None. Nothing in this addon has ever been drawn or executed by the client** |
| Blocking unknown | The coordinate space of `Minimap:UpdateMouseoverAtPoint` — see section 4 |

---

## 2. How to resume

1. Log in, gather with Find Herbs or Find Minerals up.
2. Hover a blip near the **minimap edge**. Expect a chat line saying it calibrated, naming one of the three spaces.
3. If nothing prints, `/tra calibrate` and read the failure reason. If it says no candidate reproduced the hit, section 4 is wrong and the mechanism needs rethinking.
4. `/tra types` after a gathering run. If node blips come back untyped, consider defaulting `objectsOnly` off.

---

## 3. What the addon does

Scans the minimap with the engine's own hit test and pings when a blip appears that was not there before.

Load order in the toc is the dependency order: `Config` owns saved settings, `Probe` owns the coordinate-space question, `Geometry` turns the minimap into probe points and world positions, `Scanner` drives the probes and decides what is new.

---

## 4. The one undocumented thing

`Minimap:UpdateMouseoverAtPoint(pointX, pointY)` is in `MinimapFrameAPIDocumentation.lua` on the `forever` branch, and the binary carries the symbol. The documentation gives two bare numbers and **does not say what space they are in**.

`Probe.lua` handles this by trying three readings — centre-relative pixels, frame-local pixels, normalised -1 to 1 — against ground truth, which is a blip the player's own cursor is already on. The winner must reproduce the hovered tooltip at the cursor's offset **and** miss at the mirrored offset, because a space that merely landed on something else would otherwise pass. The sample is rejected within 40% of the radius of centre, where all three candidates land in roughly the same place.

A space whose arguments the engine rejects is dropped for the session via `pcall`, so a wrong guess costs one error rather than one per probe.

---

## 5. Decisions that are not obvious from the code

**Edge ring as the hot path.** A blip becomes newly visible by crossing the minimap edge, by spawning inside the radius, or because the view changed. The first dominates and always happens at the edge, so the ring is ~64 points instead of the disc's ~220. The disc runs on `discInterval` for interior spawns, and silently once after a zone change so already-visible nodes are recorded rather than announced.

**Dedup by proximity, not by bucket.** The first implementation keyed on name plus a quantised world position. The harness caught it: a node straddling a bucket edge alerted twice, because two probes that hit the same blip disagree about its position by up to the blip's width, which can be two buckets, and the ±1 neighbour check did not cover it. Replaced with an explicit distance test.

**The tolerance is in pixels, converted to yards.** A blip is a fixed size in pixels while a pixel is worth more yards the further the minimap is zoomed out, so a fixed yard tolerance breaks on zoom. `ns.MergeYards()` recomputes it from `C_Minimap.GetViewRadius()` each time. `MERGE_PIXELS` is 20.

**The scanner yields entirely while the cursor is over the minimap.** Probing rewrites the engine's minimap mouseover, which would fight the player's own tooltip. That idle moment is also the only chance to calibrate, so the same branch does both.

**Vignettes are a second channel.** `VIGNETTE_MINIMAP_UPDATED` reports minimap arrival directly with a GUID. Vanilla content probably never uses it, but it is free when it never fires.

---

## 6. Verified API facts behind the design

| Fact | Evidence |
|---|---|
| No API enumerates minimap blips | `GetNumBlips`, `SetBlipTexture`, `GetBlipTexture` all score 0 in the binary |
| `Minimap:UpdateMouseoverAtPoint` exists | `MinimapFrameAPIDocumentation.lua`, binary = 2 |
| `C_TooltipInfo.GetMinimapMouseover()` → `TooltipData`, `MayReturnNothing` | `TooltipInfoDocumentation.lua:619`, binary = 2 |
| `GameTooltip:SetMinimapMouseover` is a Lua wrapper only | `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua` maps it to the getter; C symbol = 0 |
| `data.lines[i].leftText` is readable without surfacing | No `SurfaceArgs` anywhere in `TooltipDataHandler.lua`; it reads `lineData.leftText` directly |
| `Enum.TooltipDataType.Object` = 4, `Unit` = 2 | `TooltipInfoSharedDocumentation.lua:89` |
| `C_Minimap.GetViewRadius()` returns yards | `MinimapDocumentation.lua` |
| `C_Map.GetWorldPosFromMapPos` exists | `MapDocumentation.lua:506` |
| `GetPlayerFacing()` return is nilable | `PlayerScriptDocumentation.lua:761` |
| `VIGNETTE_MINIMAP_UPDATED(guid, onMinimap)` exists | `VignetteInfoDocumentation.lua` |
| Tracking on camelot is the retail `C_Minimap` system | `Blizzard_Minimap.toc` loads Mainline files; `GetTrackingTexture` = 0; cvar `minimapTrackedInfov4` present |

---

## 7. Dead ends, already checked

- `Minimap:GetChildren()` returns addon buttons only. Blips are engine-drawn.
- `hooksecurefunc(Minimap, "UpdateBlips", …)` fires only when Lua calls it, which the stock UI does once, on `PLAYER_TARGET_CHANGED`. Engine-side refreshes never pass through Lua.
- `C_WorldLootObject` is keyed by `unitToken` and returns only `inventoryType`, `atMaxQuality`, `isUpgrade`. It is the loot-sparkle upgrade indicator, not a node enumerator.
- No pixel readback exists anywhere in the widget API.
- `PLAYER_SOFT_INTERACT_CHANGED` works and is free, but fires at interact range, far too late to be an approach warning.

---

## 8. Open questions for the first in-game session

1. Which coordinate space wins.
2. Whether blip `TooltipData` carries a `guid`. If it does, `Consider` can drop the position maths entirely and key on it.
3. What `data.type` is for a node blip. If untyped, the `objectsOnly` default needs revisiting.
4. Whether an 8-pixel disc spacing reliably hits a blip, or whether `discSpacing` needs lowering.
5. Whether the rotation sign in `ns.WorldFromOffset` is right with `rotateMinimap` on. A wrong sign degrades dedup without breaking detection, so it will show up as repeat pings rather than silence.
