# TrackingAlert — Memory

Updated 2026-09-30 after the Forever-only cleanup and the owner decisions of round 2 (still 2.1.0, not shipped).

TrackingAlert is WoW Forever 1.60.x only, and always was. The vanilla feature lives in the separate GatherMate2Alert addon. The audit and the cleanup verified against Gethe `forever` @ `966519cf` (1.60.1.70124) and Ketho `forever` @ `4149af64` (1.60.1.70009). The installed client is 1.60.1.70009. Nothing has run in a client. On 2026-09-30, after the round 2 decisions, `lua Tools/harness.lua` passed 88 of 88 (on Lua 5.5, not WoW's 5.1), which proves logic and wiring, not client behaviour.

## Current state

When a tracked node shows up, it pings and flashes the minimap. Two sources feed one alert:

- The minimap blip source runs the engine hit test on points on the minimap.
- The optional GatherMate2 source post-hooks `Display:addMiniPin`.

It also carries GatherMate2 circle tweaks: size, merge, and hiding icons.

Both sources write to one shared node memory (`Core/Memory.lua`), so a node that both report alerts once. See "Owner decisions, round 2".

| Item | State |
|---|---|
| Version | 2.1.0. `## Interface: 16001` only, `## Author: miyanko`, `## Category: Map`, `## OptionalDeps: GatherMate2`, Addon Compartment fields. No `X-Category` |
| Git | `main` holds 2.1.0 in three commits (2026-09-30, not pushed): `3ddd379` (cleanup and fixes), `2f75aaa` (chat prefix), then the cross-source memory. `origin/main` = `719eacf` (2.0.0). History: `f832441` (1.0.0, already `16001`) → `4702355` → `719eacf` (2.0.0) → 2.1.0. No tags, no releases, no forks. The repo never held a 1.15 version, so it has no `1.15.x-backup` and needs none. This is a deliberate exception to the branch convention |
| Vanilla | Users keep GatherMate2Alert (`github.com/miyankooo/GatherMate2Alert`, `## Interface: 11509`, `main` = `1.15.x-backup` = `a946251`, re-checked 2026-09-30). It isn't cloned on this Mac |

The blip source:

- The scanner frame registers unconditionally. `Minimap:UpdateMouseoverAtPoint`, `C_TooltipInfo.GetMinimapMouseover`, `C_Minimap.GetViewRadius` and `VIGNETTE_MINIMAP_UPDATED` all exist in 1.60.1, so the old `ns.canProbe` check is gone (TA-3).
- `UpdateMouseoverAtPoint` is `SecretArguments = "AllowedWhenUntainted"` and only receives plain numbers.
- Secret values go through `ns.IsSecret` (`Core/Config.lua`): `pcall(issecretvalue, value)`, where a raise counts as secret and nil is never secret. A secret speed counts as standing still, a secret blip name reads as no blip, and a secret `guid` falls back to the name as its key (TA-2).

The GatherMate2 source:

- It attaches only if GatherMate2 loads, and every internal it reads is guarded.
- The hook fields exist on both upstream branches (`Display.lua` master:482-507, classic:471-491). The port source is `GatherMate2Alert.lua:76-208`.
- The native circle size is read off the first circle: 10 px on GatherMate2 `classic`, 12 px on `master`.

Zoning has one handler, in `Core/Alert.lua`: it sets the 5-second quiet window, then runs the `ns.OnZoning` callbacks. The shared node memory is wiped, the scanner forgets its keys and rebuilds its geometry, and the GatherMate2 source forgets its circles (TA-8).

Options use Blizzard's native Settings vertical layout, with no canvas. This already matches the shared UI spec (item 7); the addon has no tool window, dialog or minimap button:

- Every control is a `Settings.RegisterProxySetting` over `ns.db`, so all 18 `TrackingAlertDB` keys keep their meaning. 17 have a control; `space` (the calibration) has none, so Defaults can't clear it. (Earlier notes said 19 keys; `Core/Config.lua` has 18.)
- Sections are Alert, Minimap nodes and GatherMate2. Child rows nest with `SetParentInitializer`.
- The node-type mute list is a multi-select `Settings.CreateDropdown`, like Blizzard's Nameplates page.
- Calibration status leads the Calibration tooltip. The button reads Calibrate or Recalibrate.
- `/tra` opens it with `Settings.OpenToCategory(category:GetID())`. The Addon Compartment entry stays (left-click opens, right-click toggles alerts).
- No hardcoded fonts, custom panel textures or hand-built widgets. The only custom texture is the minimap flash ring, the alert's own visual.

## Forever-only rework (done 2026-09-30, 2.1.0)

There was no Classic code to split out. This pass applied the audit fixes:

| ID | Severity | Finding | Done |
|---|---|---|---|
| TA-1 | High | With "Gathering nodes only" on (the default), `IsWanted` accepted only `Object` (4) or untyped data, but Forever's minimap tooltip most likely reports `Enum.TooltipDataType.MinimapMouseover` (21, `LuaEnum.lua:7733`; `SetMinimapMouseover` → `GetMinimapMouseover`, `TooltipDataHandler.lua:594`) | `IsWanted` also accepts 21. The harness fakes 21 and checks that a Unit-typed blip is skipped. The option stays; see issue 2 |
| TA-2 | Medium | `GetUnitSpeed` is `SecretWhenUnitStatsRestricted` (`UnitDocumentation.lua:335-338`), and the blip name was used unguarded as a table key | `ns.IsSecret` guard on speed, blip name and `guid` |
| TA-3 | Medium | `ns.canProbe` checked APIs every Forever build has | Removed, with the "no hit test" branch and its harness section |
| TA-4 | Medium | The GatherMate2 source is dormant: no GatherMate2 build declares 16001 | Decided 2026-09-30: keep the source and all three display tweaks (hide node icons, merge stacked circles, circle size) as they are. No code change |
| TA-5 | Medium | `MigrateLegacy` upgraded 1.0.0 saves that cannot exist | Removed, with its harness section |
| TA-6 | Low | A vignette leaving the minimap cleared its key, so it re-alerted on every re-entry | Both edges stamp the key, so the 3-minute window counts from when it was last on the minimap, and `Prune` ages it out |
| TA-7 | Low | Rotation ignored `C_Minimap.IsRotateMinimapIgnored()` | `GetCVarBool("rotateMinimap") and not C_Minimap.IsRotateMinimapIgnored()` (`MinimapDocumentation.lua:166`, non-nilable bool) |
| TA-8 | Low | Three frames handled the same zoning events | One handler in `Alert.lua` with `ns.OnZoning` callbacks |
| TA-9 | Low | Only `## X-Category` | `## Category: Map` (`AddonList.lua:456` reads `Category`). The Notes keep naming GatherMate2, since TA-4 keeps the source |
| TA-10 | Low | `Media/pulse_ring.tga` was 4 MB, uncompressed, mode 100755 | Re-encoded losslessly as RLE (type 10, 1024×1024, 32 bpp, descriptor `0x28` top-left with 8 alpha bits, no packet crosses a scanline): 4,194,322 → 339,652 bytes. The decoded pixels are byte-identical, checked by a round trip and independently via macOS `sips`. Git mode is now 100644 |
| TA-11 | Low | README claimed the sound plays with effects muted, and gave the `_classic_beta_` path | Hedged as "meant to, not yet confirmed". Install says "the `Interface/AddOns/` folder of your WoW Forever install". The Classic Era pointer to GatherMate2Alert is gone |

The harness now also covers: one zoning frame, the tooltip-type filter, secret speed and names (including a raising `issecretvalue`), vignette re-entry, an ignored rotation, and GatherMate2 circles forgotten on zoning. Each new check was mutation-tested: reverting its fix makes it fail.

Nothing to do:

- Clean for 1.60.x: a single `16001` toc, no client splits, no `WOW_PROJECT_*`, no Era templates, no bundled libs.
- The Settings API use, the Addon Compartment wiring, and all events and the vignette payload are verified.
- Load order is right: `EventUtil.ContinueOnAddOnLoaded`/`ContinueOnPlayerLogin`, and empty saved variables are safe.
- No taint: no protected frames, and the only `hooksecurefunc` targets GatherMate2's table.
- No alerts in combat or on a taxi.
- At most 8 hit tests per frame, only while moving.
- The map maths is correct.
- `.pkgmeta` excludes the harness.

## Owner decisions, round 2 (2026-09-30)

- TA-4: keep the GatherMate2 source and all three display tweaks unchanged. The `## Notes` line keeps naming GatherMate2.
- Vignette alerts stay as they are.
- Chat output: lines start with the shared yellow `[Tracking Alert]:` prefix from `YELLOW_FONT_COLOR`, and no hex colour codes remain. The harness stubs the colour object (`2f75aaa`).
- One ping per node across sources, done in `Core/Memory.lua`:
  - Both sources call `ns.SightNode(source, key, name, x, y)`. Positions are world yards from `C_Map.GetWorldPosFromMapPos` (`MapDocumentation.lua:506`; `CreateVector2D` from the loaded `Blizzard_SharedXML/Vector2D.lua`).
  - The blip source already derived world x,y from the player's map position (`ns.WorldFromOffset`). The GatherMate2 source converts `pin.zone` and `pin.x, pin.y`, which `getMiniPin` sets on both upstream branches (master:454-480, classic:443-469). `DecodeLoc` returns zone fractions from 0 to 1 on both branches (`GatherMate2.lua` master:669, classic:524, read-only `gh api`). `pin.x1, pin.y1` (HereBeDragons world coordinates) is not used, so both sources go through the same Blizzard call.
  - Matching: within `ns.MergeYards()`, the existing same-node radius of 20 px at the current zoom. The same source must also have the same key (blip: guid or name; GatherMate2: `nodeType:coords`). Across sources the node name must match (blip tooltip line 1 against `pin.title`, GatherMate2's name for the game object). So another kind of node inside the radius still alerts.
  - A match refreshes the stamp, whichever source sees it. Entries older than `ns.REMEMBER_FOR` (now in `Memory.lua`) are dropped during the scan. The GatherMate2 hook runs every frame, so each circle keeps its node in its own `seen[type][coords]` table and looks it up in the shared list only when that is stale.
  - Per-source logic is unchanged: GatherMate2 muted types and the circle-coloured flash, blip vignettes, and the no-position fallback. A blip without a world position keeps using `keyed[guid or name]`, and a GatherMate2 pin without one stands for itself. Neither can meet the other source.
  - Changed in the blip source: a blip with a guid now also goes through the shared memory. It is keyed by guid within the merge radius and refreshed on each re-see; before, it was keyed by guid only, with no refresh.
  - Reset (Remembered nodes) forgets the blip source's own entries only. A node GatherMate2 also remembers stays quiet.
  - Harness: blip then circle pings once, circle then blip pings once, another kind inside the radius still pings, two different nodes ping twice, a node the blip keeps seeing stays one node past `REMEMBER_FOR`, both expiry paths re-arm, and zoning wipes the shared memory. Each case was mutation-tested.

## Blockers, issues, challenges

1. GatherMate2 has no Forever build: upstream `master` is `120007,120100` and `classic` is `11509,20506,50504` (checked 2026-09-30, last push 2026-08-17). The GatherMate2 source, which the owner keeps (TA-4), stays dormant until it ships. So does the cross-source memory's GatherMate2 half.
2. The blip source depends on runtime unknowns:
   - the coordinate space of `UpdateMouseoverAtPoint`, self-calibrated from a hovered blip
   - the blip tooltip's `type` and `guid`. If every blip reports `MinimapMouseover` (21), including party members and townsfolk, then "Gathering nodes only" filters nothing and is dead weight. It only earns its place if units report `Unit` (2) or nodes report `Object` (4). `/tra types` settles this. Then keep the option, or remove it (with its key, row and README lines) if it can't tell nodes from units
   - the rotation sign with `rotateMinimap`
3. Unverified: does `PlaySound(id, "Master", true)` play with effects muted? No Blizzard file passes "Master".
4. The Settings page has only been checked against source, never seen rendered. `LIST_DELIMITER` is `","`, so a partial node-type pick may read without a space.
5. The compartment lists only addons enabled for all characters (`AddonCompartment.lua:80`).
6. Does probing change the `mouseover` unit or fire `UPDATE_MOUSEOVER_UNIT`? If so, it would disturb `@mouseover` macros. Unverified.
7. Unverified: whether `issecretvalue` raises for tainted addon code handed a secret (`FrameScriptDocumentation.lua:287-290` declares `SecretArguments = "AllowedWhenUntainted"`). The pcall makes either answer safe.
8. Unverified: when `C_Minimap.IsRotateMinimapIgnored()` returns true on Forever. The audit could not confirm that Forever uses the hybrid minimap. The call is documented and harmless when it returns false.
9. The RLE texture has not been seen in a client. Evidence that it loads: Questie 12.0.3, the Forever build installed here, ships 32-bit RLE TGAs (bottom-left origin); TradeSkillMaster ships top-left RLE TGAs on retail. Ours is top-left RLE. If the flash doesn't show, re-encode it uncompressed from `719eacf:Media/pulse_ring.tga`.
10. Cross-source matching needs GatherMate2's node names to equal the blip tooltip's first line, and a Forever GatherMate2 to keep `pin.zone` a uiMapID with `pin.x, pin.y` as 0-1 zone fractions. Unverified until GatherMate2 ships. If the names turn out to differ, position alone could decide: `return node.name == name` → `return true` in `IsSameNode`. That would merge any node kind within the radius: 20 minimap pixels, which is tens of yards at far zoom.

## Next steps

1. Review and push `main` (2.1.0).
2. Optionally tag `v1.0.0` at `4702355` and `v2.0.0` at `719eacf`.
3. Run `/console scriptErrors 1` first, with Find Herbs or Find Minerals on.
4. After the `/tra types` check, decide whether "Gathering nodes only" stays (issue 2).

Beta checks:

- [ ] Options → AddOns → Tracking Alert shows three section headers. Unticking a parent greys out its nested rows.
- [ ] The AddOns list shows Tracking Alert under the Map category.
- [ ] Picking a sound plays it, and picking the same one again stays silent. Test plays the sound and a gold flash. The flash ring shows at every thickness (TA-10).
- [ ] Hover a blip near the minimap edge: chat reports the calibration. The button then reads Recalibrate, and clicking it clears the calibration. This settles part of issue 2.
- [ ] Ride into nodes: one ping each. Leave and return within 3 minutes: silence. Reset in Remembered nodes makes them ping again.
- [ ] Run `/tra types` after a run and record the numbers: 21 = MinimapMouseover, 4 = Object, 2 = Unit. Then hover a node blip and a party member or townsfolk blip, and for each type `/dump C_TooltipInfo.GetMinimapMouseover()` without moving the cursor: record `type` and whether a `guid` shows. This settles TA-1 and issue 2.
- [ ] Rotating minimap on, turn in place: no repeat pings. Fly over nodes: silence. `/dump C_Minimap.IsRotateMinimapIgnored()` with rotation on (issue 8).
- [ ] A rare or treasure vignette that drifts off and back onto the minimap within 3 minutes pings once (TA-6).
- [ ] Mute sound effects and record whether the alert plays. This settles issue 3.
- [ ] Defaults → These Settings resets everything but keeps the calibration.
- [ ] Right-click the compartment entry with the page open: sound and flash flip live.
- [ ] Without GatherMate2: those rows are greyed out with a red tooltip notice, there's no Node types row, and nothing errors.
- [ ] In a battleground: `/dump C_Secrets.HasSecretRestrictions(), issecretvalue(GetUnitSpeed("player"))`. If the speed is secret, record that "Only while moving" then pauses the scan there. This settles TA-2.
- [ ] Watch `/eventtrace` for `UPDATE_MOUSEOVER_UNIT` while moving. This settles issue 6.
- [ ] Once GatherMate2 runs on Forever: ride towards a known node with Find Herbs on. The blip pings, and the GatherMate2 circle that follows stays silent. Then hover the circle and the blip and compare the names (issue 10).
