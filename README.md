# TrackingAlert

Plays a ping the moment a new tracked node blip appears on your minimap, so you can gather without watching it.

## Features

**Catches the arrival, not the presence.** A blip that was already on screen stays quiet. Only a node that just came into range makes a sound.

**One ping per node.** Walking away and coming back, circling a node, or sweeping past it a dozen times all stay silent. The same node never pings twice.

**Gathering nodes only, by default.** Party members, NPCs and townsfolk blips are filtered out. Turn the filter off if you want every blip.

**Self-calibrating.** The first time you idly hover a blip near the minimap edge, the addon works out how to read the minimap and switches itself on. No setup.

**Also catches vignettes.** Rares and treasures that announce themselves to the minimap get the same ping.

**Cheap.** It scans only while you are moving, only the outer edge of the minimap in the hot path, and only a few points per frame.

## Installation

1. Copy the `TrackingAlert/` folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`.
2. Restart the game or `/reload`.
3. Enable **Tracking Alert** in the AddOns list.

## First run

The addon starts idle and says nothing. Hover your cursor over any tracked blip near the **edge** of the minimap for a second. It prints that it has calibrated, and alerts go live from then on. The setting is saved per account, so this happens once.

If you would rather not wait for it to happen by itself, hover a blip and type `/tra calibrate`.

## Settings

Open **Options → AddOns → Tracking Alert**, or type `/trackingalert` (short form `/tra`).

| Setting | Default | Effect |
| --- | --- | --- |
| Enabled | on | Master switch |
| Only while moving | on | Skip scanning while standing still. A blip can only cross the minimap edge while you move |
| Gathering nodes only | on | Ping only for blips whose tooltip is a world object, not a unit |
| Also ping for vignettes | on | Alert on rares and treasures that report themselves to the minimap |
| Alert cooldown | 0.75s | Shortest gap between two pings |
| Full sweep interval | 5s | How often the whole minimap is swept, to catch nodes that spawn inside the radius |
| Probes per frame | 8 | How much work each frame. Lower is cheaper and slower to react |

Settings are saved per account.

## Commands

| Command | Does |
| --- | --- |
| `/tra` | Open the options panel |
| `/tra calibrate` | Detect the minimap coordinate space from the blip under your cursor |
| `/tra recalibrate` | Forget the detected coordinate space and detect it again |
| `/tra status` | Print whether it is enabled, what it calibrated to, and how many nodes it remembers |
| `/tra types` | Print the tooltip types seen on blips so far, for tuning the node filter |
| `/tra reset` | Forget every remembered node |
| `/tra test` | Play the alert sound |

## Requirements

WoW Forever 1.60.x (Interface `16001`). No libraries, no dependencies. You need a tracking type switched on for there to be anything to alert about.

## Restrictions

**It needs calibrating once.** The game does not document how to address a point on the minimap, so the addon works it out by testing a blip you hover. Until that happens it stays silent. Hover a blip near the edge, not near the centre, where the candidate readings are indistinguishable.

**It yields to your cursor.** Reading the minimap moves the game's own minimap mouseover, so scanning stops completely while your cursor is over the minimap, and resumes when you move it away.

**Two nodes of the same kind close together count as one.** At roughly twenty minimap pixels apart they are one ping's worth of information.

**With a rotating minimap** the addon needs your facing to place a node, and the game does not always supply it. When it cannot, it falls back to one alert per node type until it recovers.

**Not yet run in game.** Every API this addon uses was checked against Blizzard's published 1.60.1 UI source and the client binary, and the logic passes an offline test harness, but it has not been tested on a live character.
