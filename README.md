# Better Tracking

Tracks herbs and ore at once by swapping Find Herbs and Find Minerals as you move, and pings the moment a node or rare comes into range on your minimap, so you can gather both without watching it.

## Features

- Herb and ore swap: alternates Find Herbs and Find Minerals every 2 or 4 seconds while you move, so a character with Herbalism and Mining sees both on the minimap. WoW Forever allows only one tracking at a time.
- Pings when a tracked blip from Find Herbs, Find Minerals or other tracking first comes into range. A node already on screen when you zoom or turn on tracking yourself stays quiet.
- One alert per node: walking away and back, circling a node or sweeping past it stays silent for three minutes after you last saw it.
- One alert for a cluster: a cooldown folds a group of nodes into a single ping.
- Sound, flash or both. Pick one of six sounds, played on the Master channel, or flash the minimap edge instead.
- Pings for rares and treasures that show on the minimap.
- Quiet on flight paths, in combat, while dead and for the first seconds after zoning.
- Optional GatherMate2 source that pings at spots GatherMate2 remembers, useful for a second profession you are not tracking.
- A minimap button that shows what you track right now. Its tooltip names the last node that pinged and why the swap waits. Middle-click turns the swap on or off, right-click pauses alerts.

## Installation

1. Install it with the CurseForge app under WoW Forever, or copy the `BetterTracking` folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`.
2. Restart the game or type `/reload`.
3. Enable Better Tracking in the AddOns list.

## Usage

1. Turn on Find Herbs or Find Minerals.
2. Hover any tracked blip near the edge of the minimap for a second. Chat says "Ready. Minimap alerts are on." This happens once per account.
3. With Herbalism and Mining, middle-click the minimap button or type `/tra swap` to swap herb and ore tracking.
4. Ride through a gathering area. Each new node pings once.
5. Right-click the minimap button to pause or resume alerts.

## Herb and Ore Swap

The swap casts Find Herbs and Find Minerals in turn while you move, so the minimap shows both node types. Each node that a swap reveals pings once, and a node you saw in the last three minutes stays quiet on every later swap.

- Turn it on with Swap Herbs and Minerals in the settings, a middle-click on the minimap button or `/tra swap`. It is off by default and saved per account.
- Swap Every sets how long each tracking stays on: 4 seconds by default, or 2 seconds.
- Each swap is a cast and costs a global cooldown, about 1.5 seconds.
- Herbs come first when neither is on.
- It waits while you are in combat, dead or a ghost, on a flight, in an instance, resting in a town or inn, standing still, casting, channeling or looting, while you target an enemy you can attack or have one under your cursor, and while the global cooldown runs. A pull never starts on a cooldown the swap spent.
- It never replaces another tracking. With Find Fish, Find Treasure or Track Beasts on, it waits until you turn that off.
- It needs both spells. On a character without one of them it stays on but waits.
- The minimap button tooltip and `/tra status` say why it waits.

If Blizzard blocks a timed swap, or timed swaps do not take twice in a row, the addon says so once and moves the swap onto your movement keys and mouse clicks: each key press or click runs at most one due swap. While you only hold a key or autorun, no new input arrives, so the swap pauses until your next one. If Blizzard shows a warning about the addon, choose Ignore: Disable turns the addon off and reloads the UI.

## Commands

| Command | Does |
| --- | --- |
| `/tra` | Opens the settings |
| `/tra swap` | Turns the herb and ore swap on or off |
| `/tra minimap` | Hides or shows the minimap button |
| `/tra calibrate` | Learns how to read the minimap from the blip under your cursor |
| `/tra recalibrate` | Forgets that, so the next hover learns it again |
| `/tra status` | Prints whether alerts are on, whether the swap runs or why it waits, the minimap reading, how many nodes are remembered, the last alert and whether GatherMate2 is attached |
| `/tra types` | Prints the tooltip types seen on blips so far |
| `/tra reset` | Forgets every remembered node, from both sources |
| `/tra test` | Plays the alert sound and flash |

`/bettertracking` works as well.

## Settings

Open Options, AddOns, Better Tracking, type `/tra`, or left-click the minimap button or Better Tracking in the addon menu. Indented rows belong to the switch above them and grey out while it is off.

| Section | Setting | Default | Effect |
| --- | --- | --- | --- |
| Herb and Ore Swap | Swap Herbs and Minerals | off | Alternates Find Herbs and Find Minerals while you move |
| Herb and Ore Swap | Swap Every | 4 Seconds | How long each tracking stays on, 2 or 4 seconds |
| Alert | Play a Sound | on | Sound on each alert, on the Master channel |
| Alert | Sound | Minimap Ping | One of six game sounds. Picking one plays it |
| Alert | Flash the Minimap Edge | on | Ring flash on each alert |
| Alert | Cooldown | 3 s | Shortest gap between two alerts |
| Alert | Preview | Test | Plays the sound and the flash |
| Minimap Nodes | Alert on Minimap Nodes | on | Minimap source switch |
| Minimap Nodes | Gathering Nodes Only | on | Skips blips the game marks as a unit |
| Minimap Nodes | Rares and Treasures | on | Pings when a rare or treasure shows on the minimap |
| Minimap Nodes | Calibration | Calibrate | Forgets how to read the minimap, so the next hover learns it again. Before the first hover it says how to start |
| Minimap Nodes | Remembered Nodes | Reset | Forgets every node both sources remember |
| GatherMate2 | Also Ping at Spots GatherMate2 Remembers | off | GatherMate2 source switch |
| GatherMate2 | Node Types | All | Herb Gathering, Mining, Fishing and Treasure. Shown only with GatherMate2 |

Defaults resets every setting and keeps the calibration, the pause and the minimap button. Settings are saved per account.

## Requirements

WoW Forever 1.60.x (Interface `16001`).

[GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) is optional. Its WoW Forever support ships in its alpha builds.

## Restrictions

The minimap source needs one hover. The game does not document how to address a point on the minimap, so the addon works it out from a blip you hover near the edge.

The minimap source yields to your cursor. Reading the minimap moves the game's own minimap mouseover, so it pauses while your cursor is over the minimap.

The minimap source scans only while you move. Where the game hides your speed or a blip's name, it skips the scan or that blip.

Two minimap nodes of the same kind close together count as one.

A minimap blip and a GatherMate2 spot count as one node when they carry the same name and sit close together. Without a map position, as in some instances, each source keeps to itself.

With a rotating minimap the addon needs your facing to place a node. When the game does not supply it, it falls back to one alert per node type until it recovers.

GatherMate2 spots are remembered locations, so they ping even when the node is gone. The GatherMate2 source reads GatherMate2's internals; if a version moves them, the addon says so once and leaves that source off.

The herb and ore swap casts spells on a timer. If Blizzard blocks that, it runs on your movement keys instead, and if Blizzard blocks that too, it stays off until `/reload`.

## Development

Run the offline harness from the addon folder after every change:

```sh
lua Tools/harness.lua
```

## License

MIT. See [LICENSE](LICENSE).
