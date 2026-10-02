# VESNA

Standalone Drawing API UI library with Crimson Rose styling, bento cards, configuration profiles, and native-chat-safe input.

Execute `Vesna.luau` to open the bundled demo. Version 1.10 uses a native 12-line header emblem: a 16×20 rose hexagon, white 8×10 diamond, and two connectors. Every stroke is retained, 1px thick, and owned by a destructible child. The header requires no image, filesystem, or HTTP loader. The sidebar avatar still uses an optional image with an initials fallback.

Window size: 695×452. RightControl toggles visibility. Close opens an unload confirmation. Requires a host providing Drawing and Roblox client services. Text uses Font 0.

Configuration files use `VesnaConfigs/<GameId>/`. Existing Obsidian profiles may be copied into this folder. Native Roblox text entry suppresses library hotkeys.

Validation: `lua Vesna.test.lua Vesna.luau work` (create the work folder first). Desktop mock rendering and live Potassium execution are separate checks; see `validation.txt` for details.
