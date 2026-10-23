# BetterTracking

## Target

- WoW Forever 1.60.x only, `## Interface: 16001`. No client branches, no `WOW_PROJECT_*`, no Era templates, no API probes.
- `main` is the only branch. The repo never held a Classic version, so it has no `1.15.x-backup`.
- The Classic Era feature lives in the separate GatherMate2Alert repo. The README has no Classic Era pointer.
- Verify every API against Gethe `wow-ui-source` and Ketho `BlizzardInterfaceResources`, branch `forever`. Check GatherMate2 internals on both its upstream branches, `master` and `classic`.

## Rules

- Both sources report nodes through `ns.SightNode` into the shared memory in `Core/Memory.lua`. Positions are world yards from `C_Map.GetWorldPosFromMapPos`, never HereBeDragons' `pin.x1` and `pin.y1`.
- Secret values go through `ns.IsSecret`, which wraps `issecretvalue` in `pcall`. A raise counts as secret, nil never does. A secret `guid` falls back to the name as the key.
- `Minimap:UpdateMouseoverAtPoint` is `SecretArguments = "AllowedWhenUntainted"`. Pass it plain numbers only.
- Hooks are `hooksecurefunc` only: GatherMate2's `Display:addMiniPin`, and Blizzard's movement and steering globals once the swap is in input mode. No protected frames. Guard every GatherMate2 internal the source reads.
- Keep the GatherMate2 source, off by default because its circles mark remembered spots, and keep vignette alerts. Never restyle GatherMate2's own pins. Node types are limited to Forever's four. The toc `## Notes` keeps naming GatherMate2.
- Tuning stays hardcoded: probe budget 8, full sweep 5 s, scan only while moving, sound on the Master channel, flash ring cell 4. No settings for them.
- Coordinate-space calibration and `/tra types` stay until the in-game test settles the space, then the measured space is hardcoded and both go.
- Zoning has one handler, in `Core/Alert.lua`. Other modules react through `ns.OnZoning` callbacks.
- Options use the native Settings vertical layout, no canvas. Every control is a `Settings.RegisterProxySetting` over `ns.db`. The state keys `space`, `paused`, `hinted` and `minimap` have no control, so Defaults keeps them.
- Known Blizzard bug on build 70532, found 2026-10-21: picking a value in any addon's native settings dropdown taints Blizzard's own settings until /reload, and nameplates then raise secret-value errors. Checkboxes and sliders stay clean. The three dropdowns stay for their UX until Blizzard fixes it. Retest before the first CurseForge release. If it still fails, move them into an own panel like Social Shortcuts.
- Setting names, headings and buttons use Title Case. Tooltips and chat use sentence case and end with a period.
- The launcher is `UI.CreateLauncher` from LibNativeUI-1.0: a LibDBIcon minimap button, shown by default, plus the addon menu entry it registers. No `## AddonCompartmentFunc*` toc keys, or the addon shows twice. Its position lives in `BetterTrackingDB.minimap`, and `/tra minimap` flips it through `setShown`.
- Launcher clicks: left opens the settings, middle toggles the swap, right toggles `paused`, never the sound or flash settings. The icon is the active spell tracking's texture, set on `MINIMAP_UPDATE_TRACKING` and through `ns.OnZoning` at login, through the LibDataBroker object, else `Interface\Icons\Ability_Tracking`, which is also the toc `IconTexture`.
- At most one chat line per action. The only login line is the first-run hint, once per account. The hint, the launcher status and the Calibrate button share one string, `ns.HOVER_HINT`, which names turning tracking on first.
- The space label (`ns.SpaceLabel`) shows only in `/tra status`, never in chat lines or tooltips.
- A settings open in combat prints "Opens after combat." and waits through `EventUtil.RegisterOnceFrameEventAndCallback` behind a `waitingForCombat` guard, the same shape as the sibling settings addons.
- No tool window or dialog. No hardcoded fonts, custom panel textures or hand-built widgets. The only custom texture is the flash ring, `Media/pulse_ring.tga`.
- Chat lines start with the shared yellow `[Better Tracking]:` prefix from `YELLOW_FONT_COLOR`. No literal `|cff` codes.
- Globals: `BetterTrackingDB`, `SLASH_BETTERTRACKING1` (`/bettertracking`), `SLASH_BETTERTRACKING2` (`/tra`) and `SlashCmdList.BETTERTRACKING`. Setting variables start with `BETTER_TRACKING_`.
- The toc version stays 1.0.0 until the first CurseForge release.
- Licence: MIT (LICENSE).

## Herb and ore swap

- `Core/Swap.lua` owns it. `swap` is off by default and account-wide, `swapInterval` is 2 or 4 seconds. A 0.5 s `C_Timer` ticker runs only while it is on and timed swaps work.
- Find the herb and ore entries by `spellID` (herb 2383 and 8387, ore 2580 and 8388) through `C_Minimap.GetNumTrackingTypes` and `GetTrackingInfo` on every swap, because indices shift. Only `type == "spell"` entries count.
- Swap only with `C_Minimap.SetTracking(index, true)` for the type that is off, herbs first. Never `SetTracking(..., false)` and never `CastSpellByID`: casting the other spell replaces the active one.
- Never override another tracking. Another active spell tracking holds the swap.
- Guards in this order, each with its reason for the tooltip and `/tra status`: both spells, another tracking, combat, dead, flight, instance, resting, standing still (`ns.IsMoving`), casting or channeling, `LootFrame` shown, a living attackable `target` or `mouseover`, the spell's cooldown or the GCD (`isActive`, which is NeverSecret). A secret speed or cast counts as the waiting state. The cooldown is normal running, so the status text never reports it.
- The swap never prints while it waits. Toggling prints one line and calls `Settings.NotifyUpdate` so an open panel follows.
- Block fallback: `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN` naming this addon during a swap, or two timed swaps in a row with neither a `UNIT_SPELLCAST_SUCCEEDED` for the swapped spell nor an active read 1.5 s later, move the swap to input mode once a session: the ticker stops and `hooksecurefunc` post-hooks on the movement and steering globals from `Bindings_Camelot.xml` run at most one due swap per input, with the same guards. Keys that start travel skip only the standing-still guard. A block there too stops the swap until /reload. A FORBIDDEN line tells the player to choose Ignore, because Blizzard's popup offers Disable first.
- With the swap on, `MINIMAP_UPDATE_TRACKING` queues an alerting disc sweep 0.3 s later, so swapped-in nodes ping and node memory keeps them quiet after. Zoom changes, and tracking changes with the swap off, keep the silent reprime.

## Checks

- Run `luac -p` on every Lua file and `lua Tools/harness.lua` after every change. The harness runs on Lua 5.5 and proves logic and wiring, not client behaviour. It loads the real LibStub and LibNativeUI-1.0 and stubs CallbackHandler, LibDataBroker, LibDBIcon and AceAddon. A new client API needs a stub there.
- Give every fix a harness case, and confirm the case fails with the fix reverted.
- `.pkgmeta` keeps `CLAUDE.md`, `Tests` and `Tools` out of the package and lists GatherMate2 as an optional dependency.
- `.github/workflows/release.yml` stays byte-identical to ChatScan's copy.
- Turn on `/console scriptErrors 1` and Find Herbs or Find Minerals before testing in game.

## Libraries

- `Libs/` holds tracked, unedited upstream copies, byte-identical to ChatScan's. LibDBIcon-1.0, LibDataBroker-1.1 and CallbackHandler-1.0 stay for `UI.CreateLauncher` and load before LibNativeUI-1.0.
- LibNativeUI-1.0's reference copy lives in ChatScan, so never edit it here. `shasum */Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua` must print one hash.
