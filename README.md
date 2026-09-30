# TrackingAlert

Plays a ping the moment a gathering node comes into range on your minimap, so you can gather without watching it.

For WoW Forever 1.60.x only.

It listens to two sources, and you switch each one on or off by itself:

- **Minimap nodes.** Blips from Find Herbs, Find Minerals and other tracking, straight from the minimap.
- **GatherMate2 circles.** The moment GatherMate2 turns a known node into a tracking circle. This source stays idle until GatherMate2 runs on WoW Forever, which it does not yet.

## Features

**Catches the arrival, not the presence.** A node that was already on screen stays quiet. Only a node that just came into range makes a sound.

**One alert per node.** Walking away and coming back, circling a node, or sweeping past it a dozen times all stay silent for three minutes after you last saw it.

**One alert for a cluster.** A cooldown folds a group of nodes into a single ping.

**Sound, flash or both.** Pick one of six sounds, or turn the sound off and flash the minimap edge instead. The flash is gold for a minimap node and takes the colour of the GatherMate2 circle that caused it. By default the sound plays on the Master channel, so it is meant to come through while sound effects are muted. That is not yet confirmed in game.

**Quiet when it should be.** No alerts on flight paths, in combat, or for the first seconds after zoning.

**Gathering nodes only, by default.** Blips whose tooltip the game marks as a unit, such as party members and townsfolk, are skipped. Whether the game marks them that way on the minimap is not yet confirmed in game.

**Self-calibrating.** The first time you idly hover a blip near the minimap edge, the addon works out how to read the minimap and switches the minimap source on.

**GatherMate2 extras.** Per-node-type toggles, hide far node icons, merge stacked circles into one, and a larger circle size.

**Cheap.** The minimap source scans only while you move, mostly along the outer edge, a few points per frame.

## Installation

1. Copy the `TrackingAlert/` folder into the `Interface/AddOns/` folder of your WoW Forever install.
2. Restart the game or `/reload`.
3. Enable **Tracking Alert** in the AddOns list. Enable it for all characters if you want its entry in the addon menu under the minimap.

## First run

The minimap source starts idle. Hover your cursor over any tracked blip near the **edge** of the minimap for a second. It prints that it has calibrated, and minimap alerts go live from then on. The setting is saved per account, so this happens once. To force it, hover a blip and type `/tra calibrate`.

The GatherMate2 source needs no setup. It works as soon as GatherMate2 has node data for the zone.

## Settings

Open **Options → AddOns → Tracking Alert** or type `/tra`. You can also left-click **Tracking Alert** in the addon menu under the minimap, and right-click it there to turn alerts on or off.

The page uses the game's own settings list. Indented rows belong to the switch above them and grey out while it is off. Hover any row for its details.

### Alert

| Setting | Default | Effect |
| --- | --- | --- |
| Play a sound | on | Sound on each alert |
| Sound | Minimap Ping | One of six game sounds. Picking one plays it |
| Play while sound effects are muted | on | Plays on the Master channel instead of sound effects |
| Flash the minimap edge | on | Ring flash on each alert |
| Flash thickness | 4 | Ring from hairline (1) to bold (10) |
| Cooldown | 3 s | Shortest gap between two alerts |
| Preview | Test | Plays the sound and the flash |

### Minimap nodes

| Setting | Default | Effect |
| --- | --- | --- |
| Alert on minimap nodes | on | Minimap source switch |
| Only while moving | on | Skip scanning while standing still |
| Gathering nodes only | on | Skip blips whose tooltip the game marks as a unit |
| Also alert on vignettes | on | Rares and treasures that report themselves to the minimap |
| Full sweep | 5 s | How often the whole minimap is swept, for nodes that spawn inside the radius |
| Probes per frame | 8 | Work per frame. Lower is cheaper and slower to react |
| Calibration | Calibrate / Recalibrate | Forgets the calibration, so the next hover detects it again. The tooltip shows the current state |
| Remembered nodes | Reset | Forgets every remembered minimap node. The tooltip shows how many |

### GatherMate2

These rows are greyed out until GatherMate2 is installed and enabled.

| Setting | Default | Effect |
| --- | --- | --- |
| Alert on GatherMate2 circles | on | GatherMate2 source switch |
| Node types | All | Which GatherMate2 node types alert. Shown only with GatherMate2 |
| Hide node icons | off | Hide GatherMate2's far node icons |
| Merge stacked circles into one | on | Overlapping circles show as one, gold when mixed |
| Circle size | 1 | GatherMate2's native circle at 1, larger above |

**Defaults** at the top of the page, then **These Settings**, resets every setting on it, node types included, and keeps the calibration. Settings are saved per account.

## Commands

| Command | Does |
| --- | --- |
| `/tra` | Open the settings |
| `/tra calibrate` | Detect the minimap coordinate space from the blip under your cursor |
| `/tra recalibrate` | Forget the detected coordinate space and detect it again |
| `/tra status` | Print whether alerts are on, the calibration, how many nodes it remembers, and whether GatherMate2 is attached |
| `/tra types` | Print the tooltip types seen on blips so far |
| `/tra reset` | Forget every remembered minimap node |
| `/tra test` | Play the alert sound and flash |

## Requirements

WoW Forever 1.60.x (Interface `16001`). No libraries.

GatherMate2 is optional. Nothing needs it, and its source switches on by itself once a GatherMate2 build for WoW Forever is installed.

## Restrictions

**The minimap source needs calibrating once.** The game does not document how to address a point on the minimap, so the addon works it out by testing a blip you hover. Hover a blip near the edge, not near the centre.

**The minimap source yields to your cursor.** Reading the minimap moves the game's own minimap mouseover, so it pauses while your cursor is over the minimap.

**The minimap source may pause in restricted content.** Where the game hides your speed or a blip's name, the addon cannot read them, so it skips the scan (with **Only while moving** on) or that blip.

**Two minimap nodes of the same kind close together count as one.**

**With a rotating minimap** the minimap source needs your facing to place a node. When the game does not supply it, it falls back to one alert per node type until it recovers.

**The GatherMate2 source reads GatherMate2's internals.** If a GatherMate2 version moves them, the addon says so once and leaves that source off.

**Not yet run in game.** Every API this addon uses was checked against Blizzard's published 1.60.1 UI source, and the logic passes an offline test harness, but it has not been tested on a live character.
