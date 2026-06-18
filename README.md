# RaidRIP

RaidRIP is a lightweight WoW Classic TBC addon that plays a configurable local sound when a raid or party member dies.

## What it does

- Watches the combat log for death events
- Shares death events over addon chat
- Plays a per-player custom sound on every client that has the addon installed
- Supports a fallback/default sound

## Install

Copy the addon folder into your Classic TBC addons directory:

`World of Warcraft\_classic_\Interface\AddOns\`

The addon folder should contain:

- `RaidRIP.toc`
- `RaidRIP.lua`

## Slash commands

Use:

`/rds help`

Useful commands:

```text
/rds set Tankname Sound\Interface\RaidWarning.ogg
/rds set Healername Sound\Spells\PVPFlagTaken.ogg
/rds default Sound\Interface\RaidWarning.ogg
/rds sync on
/rds list
```

## Notes

- Everyone who wants the sounds must have the addon installed and enabled.
- The sound path must exist on the client.
- If you want consistent raid behavior, use the same mappings on all clients.
