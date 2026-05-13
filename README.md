# RaidNexus WoW Add-on

Retail WoW add-on for RaidNexus guild management workflows.

## Current Features

- `/rnx roster`
  - Opens a copy popup containing all current raid members, one per line.
- `/rnx groups`
  - Opens a copy popup containing raid members grouped by raid group.
- `/rnx frontline`
  - Opens a paste-and-preview window for a boss roster copied from RaidNexus.
  - If you're raid leader or assist, it can sort the imported roster into groups `1-4`.
  - Anyone currently in groups `1-4` who is not on the imported roster gets moved into groups `5-8`.
- `/rnx simc`
  - Opens a SimulationCraft export for your current character.
  - Supports the same modifiers as `/simc`, including `nobags`, `merchant`, and linked item exports.
- Automatic combat logging
  - Enables WoW combat logging automatically in raids and dungeons.
  - Enables Advanced Combat Logging automatically.
  - Stops logging automatically after leaving supported content.
- `/rnx combatlog`
  - Shows combat logging status and whether automatic logging is enabled.
- `/rnx`
  - Opens a small quick-actions panel.
- Minimap button
  - Click opens the quick-actions panel.
  - Drag repositions the minimap button.

## Copy Flow

WoW does not expose a native clipboard API. For v1, the add-on opens a popup EditBox,
selects the generated text, and prompts the user to press `Ctrl+C`.

## Notes

- This add-on is raid-focused for the current RaidNexus Live Raid workflow.
- If the SimulationCraft add-on is not installed, RaidNexus also registers `/simc` directly.
- If the player is not in a raid, the add-on shows a friendly message instead of exporting.
- Frontline sorting requires raid leader or assist permissions and is intended for out-of-combat use.
- Settings/state are stored in `RaidNexusDB`.
