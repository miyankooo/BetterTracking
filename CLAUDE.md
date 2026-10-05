# TrackingAlert

## Target

- WoW Forever 1.60.x only, `## Interface: 16001`. No client branches, no `WOW_PROJECT_*`, no Era templates, no API probes.
- `main` is the only branch. The repo never held a Classic version, so it has no `1.15.x-backup`.
- The Classic Era feature lives in the separate GatherMate2Alert repo. The README has no Classic Era pointer.
- Verify every API against Gethe `wow-ui-source` and Ketho `BlizzardInterfaceResources`, branch `forever`. Check GatherMate2 internals on both its upstream branches, `master` and `classic`.

## Rules

- Both sources report nodes through `ns.SightNode` into the shared memory in `Core/Memory.lua`. Positions are world yards from `C_Map.GetWorldPosFromMapPos`, never HereBeDragons' `pin.x1` and `pin.y1`.
- Secret values go through `ns.IsSecret`, which wraps `issecretvalue` in `pcall`. A raise counts as secret, nil never does. A secret `guid` falls back to the name as the key.
- `Minimap:UpdateMouseoverAtPoint` is `SecretArguments = "AllowedWhenUntainted"`. Pass it plain numbers only.
- The only hook is a `hooksecurefunc` on GatherMate2's `Display:addMiniPin`. No protected frames. Guard every GatherMate2 internal the source reads.
- Keep the GatherMate2 source with its three display tweaks, and keep vignette alerts. The toc `## Notes` keeps naming GatherMate2.
- Zoning has one handler, in `Core/Alert.lua`. Other modules react through `ns.OnZoning` callbacks.
- Options use the native Settings vertical layout, no canvas. Every control is a `Settings.RegisterProxySetting` over `ns.db`. The calibration key `space` has no control, so Defaults keeps it.
- No tool window, dialog or minimap button. No hardcoded fonts, custom panel textures or hand-built widgets. The only custom texture is the flash ring, `Media/pulse_ring.tga`.
- Chat lines start with the shared yellow `[Tracking Alert]:` prefix from `YELLOW_FONT_COLOR`. No literal `|cff` codes.

## Checks

- Run `lua Tools/harness.lua` after every change. It runs on Lua 5.5 and proves logic and wiring, not client behaviour.
- Give every fix a harness case, and confirm the case fails with the fix reverted.
- `.pkgmeta` keeps `Tools/` out of the package.
- Turn on `/console scriptErrors 1` and Find Herbs or Find Minerals before testing in game.
