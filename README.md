# Vesna

A zero-Instance, modular Bento-grid interface framework engineered on Luau Drawing primitives.

Vesna renders and manages its interface through the executor-provided `Drawing` API. Layout, input routing, animation, persistence, and resource ownership remain outside the Roblox DataModel.

This reference describes version **1.10.0**.

## Technical specification

| Subsystem | Implementation |
|---|---|
| Render engine | `Drawing` objects; no `ScreenGui` or `Instance.new` |
| Layout | Six-column Bento grid with configurable card spans |
| Window | 695 × 452px; 158px sidebar |
| Palette | Onyx `#0D0E12` with Crimson Rose `#F43F5E` |
| Typography | Drawing Font 0; integer text sizes |
| Header logo | Twelve retained `Line` primitives; no image download |
| Input | Shared desktop mouse and keyboard dispatcher |
| Animation | Frame-rate-independent interpolation through `RenderStepped` |
| Persistence | Typed JSON profiles with a 0.5-second save debounce |
| Lifecycle | Hierarchical ownership of Drawing objects and library connections |

**Platform scope:** the current dispatcher supports desktop mouse and keyboard input. Mobile touch input is not implemented.

Interface geometry uses `Square`, `Circle`, `Line`, and `Text`. The optional player avatar uses `Drawing.new("Image")` with an initials fallback.

### Runtime requirements

The host must provide:

- Roblox client services, including `UserInputService`, `RunService`, and `HttpService`.
- `Drawing.new`, `ZIndex`, `Transparency`, `Visible`, and `Remove`.
- A desktop viewport of at least 711 × 468px.
- `loadstring` and `game:HttpGet` for the remote bootstrap below.
- Executor filesystem functions for configuration persistence.

Drawing implementations differ between hosts. Font rendering and primitive rasterization remain host-dependent.

## Quickstart

The distributed script opens its demonstration window when executed. This example unloads that window, then creates an application interface.

Callbacks run asynchronously and receive subsequent state changes. Set application defaults explicitly.

```lua
local Vesna = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ZeroDepTrai/VESNA/main/Vesna.luau"
))()

Vesna:Unload()

local state = {
    Enabled = true,
    Quality = 75,
    Preset = "Balanced",
}

local window = Vesna:CreateWindow({
    Title = "VESNA",
    ToggleKey = Enum.KeyCode.RightControl,
})

local overview = window:CreateTab("Overview", "+")

local session = overview:CreateCard({
    Name = "SESSION",
    Description = "Local workspace controls",
    Column = 1,
    ColumnSpan = 3,
    Row = 1,
    RowSpan = 3,
})

local tuning = overview:CreateCard({
    Name = "TUNING",
    Description = "Rendering preferences",
    Column = 4,
    ColumnSpan = 3,
    Row = 1,
    RowSpan = 3,
})

local enabled = session:AddToggle({
    Id = "session.enabled",
    Name = "Workspace enabled",
    Default = state.Enabled,
    Callback = function(value)
        state.Enabled = value
        print("Workspace enabled:", value)
    end,
})

session:AddKeybind({
    Id = "session.snapshotKey",
    Name = "Print snapshot",
    Default = Enum.KeyCode.F6,
    Callback = function(key)
        print(key.Name, state.Enabled, state.Quality, state.Preset)
    end,
})

session:AddButton({
    Name = "Toggle workspace",
    Callback = function()
        enabled:Set(not enabled:Get())
    end,
})

tuning:AddSlider({
    Id = "render.quality",
    Name = "Render quality",
    Min = 0,
    Max = 100,
    Default = state.Quality,
    Decimals = 0,
    Suffix = "%",
    Callback = function(value)
        state.Quality = value
    end,
})

tuning:AddDropdown({
    Id = "render.preset",
    Name = "Preset",
    Options = { "Balanced", "Quality", "Performance" },
    Default = state.Preset,
    Callback = function(value)
        state.Preset = value
    end,
})

window:CreateConfigTab()
```

Use an audited commit SHA instead of `main` when a deployment requires a fixed library revision.

The following examples extend the variables defined in this bootstrap.

## API reference

Signatures use Luau type notation to describe the public contract. The implementation does not export these types as a separate type package.

### Library and windows

```lua
Vesna:CreateWindow(config: {
    Title: string?,
    Position: Vector2?,
    ToggleKey: Enum.KeyCode?,
    Accent: Color3?,
    MouseOffset: Vector2?,
    RespectProcessed: boolean?,
    Font: number?,
    ProfileCallback: ((player: Player) -> ())?,
}?): Window

Vesna:Unload(): ()
```

`CreateWindow` starts the shared input and rendering dispatcher when needed. Window dimensions are fixed by the library metrics.

`Font` must be omitted or set to `0`. `MouseOffset` adapts hosts whose mouse coordinates differ from Drawing screen coordinates.

`ProfileCallback` replaces the sidebar profile card's default action.

`Unload` destroys every window managed by this library instance.

```lua
Window:CreateTab(name: string, icon: string?): Tab
Window:SelectTab(tab: Tab): ()
Window:SetVisible(visible: boolean): ()
Window:SetAccent(color: Color3): ()
Window:Destroy(): ()
```

`icon` is a text marker, not an image asset.

```lua
local diagnostics = window:CreateTab("Diagnostics", "=")
window:SelectTab(diagnostics)
```

### Bento cards

```lua
Tab:CreateCard(config: {
    Name: string?,
    Description: string?,
    Column: number?,
    ColumnSpan: number?,
    Row: number?,
    RowSpan: number?,
}): Card

Tab:CreateSection(name: string): Card
```

The current API accepts a configuration table. It does not implement `CreateCard(title, description)`.

| Argument | Default | Meaning |
|---|---:|---|
| `Name` | `"CARD"` | Card heading |
| `Description` | `""` | Secondary heading text |
| `Column` | `1` | Starting column |
| `ColumnSpan` | `3` | Number of occupied columns |
| `Row` | `1` | Starting row |
| `RowSpan` | `2` | Number of occupied rows |

Coordinates and spans must be positive integers. Cards cannot overlap or extend beyond the six-column, six-row grid.

Card widths derive from their column spans. Card heights derive from row spans and the tab's highest occupied row. Internal padding is 14px; the inter-card gap is 10px.

A tab containing one card docks it to the left and caps its width at **325px**. Narrower declared spans remain narrower.

Multiple cards use their declared positions; they are not automatically rearranged into a 2 × 2 layout. For that arrangement, use:

| Card | Column | ColumnSpan | Row | RowSpan |
|---|---:|---:|---:|---:|
| Top left | 1 | 3 | 1 | 3 |
| Top right | 4 | 3 | 1 | 3 |
| Bottom left | 1 | 3 | 4 | 3 |
| Bottom right | 4 | 3 | 4 | 3 |

`CreateSection` is a convenience method that alternates three-column cards across successive two-row bands.

```lua
local metrics = diagnostics:CreateCard({
    Name = "METRICS",
    Description = "Local diagnostics",
    Column = 1,
    ColumnSpan = 6,
    RowSpan = 3,
})
```

### Common control behavior

Persisted controls accept these additional fields:

| Field | Purpose |
|---|---|
| `Id: string?` | Stable configuration identifier |
| `Persist: boolean?` | Set `false` to exclude the control from profiles |

Without an explicit `Id`, persistence derives an identifier from the tab, card, and control names. Renaming those labels therefore changes the identifier.

Stateful controls expose:

```lua
Control:Get(): boolean | number | string | Enum.KeyCode | nil
Control:Set(value, silent: boolean?): ()
Control:Destroy(): ()
Control:Remove(): ()
```

The accepted value type depends on the control. `Set(value, true)` suppresses callbacks and the auto-save notification.

Callbacks are deferred and protected with error handling. They are not called during initial default assignment.

### Toggle

```lua
Card:AddToggle(config: {
    Name: string,
    Default: boolean,
    Callback: ((state: boolean) -> ())?,
    Id: string?,
    Persist: boolean?,
}): Toggle
```

The 34 × 18px track comprises two filled circles and a bridging square. A white circle with radius 6px moves between the two endpoints.

The active state uses solid Crimson Rose fill. There is no exterior accent stroke, outline frame, or glow halo.

```lua
enabled:Set(false)
print(enabled:Get())
```

### Slider

```lua
Card:AddSlider(config: {
    Name: string,
    Min: number,
    Max: number,
    Default: number,
    Suffix: string?,
    Decimals: number?,
    Callback: ((value: number) -> ())?,
    Id: string?,
    Persist: boolean?,
}): Slider
```

Values are constrained to the configured range and decimal precision.

The numeric readout is right-aligned text without a pill container. The track is 4px thick with a 12px-diameter thumb. Visual interpolation smooths the fill while callbacks report the current logical value.

```lua
local scale = tuning:AddSlider({
    Id = "render.scale",
    Name = "Scale",
    Min = 0.5,
    Max = 2,
    Default = 1,
    Decimals = 2,
    Suffix = "x",
    Callback = function(value)
        print("Scale:", value)
    end,
})

scale:Set(1.25)
```

### Dropdown

```lua
Card:AddDropdown(config: {
    Name: string,
    Options: {string},
    Default: string,
    Callback: ((selected: string) -> ())?,
    Id: string?,
    Persist: boolean?,
}): Dropdown

Dropdown:SetOptions(options: {string}): ()
Dropdown:Close(): ()
```

The selected value must belong to `Options`. Floating options render above card content. Long option lists support scrolling.

```lua
local mode = tuning:AddDropdown({
    Id = "render.mode",
    Name = "Mode",
    Options = { "Automatic", "Manual" },
    Default = "Automatic",
    Callback = function(selected)
        print("Mode:", selected)
    end,
})

mode:Set("Manual")
mode:Close()
```

### Keybind

```lua
Card:AddKeybind(config: {
    Name: string,
    Default: Enum.KeyCode?,
    Callback: ((key: Enum.KeyCode) -> ())?,
    OnChanged: ((key: Enum.KeyCode?) -> ())?,
    Id: string?,
    Persist: boolean?,
}): Keybind
```

`Callback` runs when the assigned key is pressed. `OnChanged` runs when the binding changes.

The bracketless keycap is 22px tall and at least 42px wide. Longer key names expand its width to the measured text width plus 16px.

Click the keycap to listen for a binding:

- A key assigns the new binding.
- `Escape` cancels listening.
- `Backspace` clears the binding.
- Listening displays `...` with an accent pulse.

Bindings are suppressed during native Roblox text entry, library text editing, rebinding, hidden-window states, and confirmation modals. Component shortcuts apply to the active tab.

```lua
local shortcut = session:AddKeybind({
    Id = "session.toggleKey",
    Name = "Toggle workspace",
    Default = Enum.KeyCode.F7,
    Callback = function()
        enabled:Set(not enabled:Get())
    end,
    OnChanged = function(key)
        print("Assigned key:", key and key.Name or "None")
    end,
})

shortcut:Set(Enum.KeyCode.F8)
```

### Action button

```lua
Card:AddButton(config: {
    Name: string,
    Callback: (() -> ())?,
}): Button
```

Buttons use a centered label, elevated background, and 1px perimeter stroke. Hover brightens the surface; pressing produces a short accent flash and downward depression.

The callback runs on release inside the button.

```lua
session:AddButton({
    Name = "Disable workspace",
    Callback = function()
        enabled:Set(false)
    end,
})
```

### Text input

```lua
Card:AddInput(config: {
    Name: string,
    Default: string?,
    Callback: ((value: string) -> ())?,
    Id: string?,
    Persist: boolean?,
}): Input
```

Text entry supports caret navigation, selection, held-key repeat, `Ctrl+A`, and clipboard shortcuts when the host provides clipboard functions. Active library text entry consumes keyboard shortcuts.

```lua
local profileName = session:AddInput({
    Id = "profile.name",
    Name = "Profile name",
    Default = "default",
    Callback = function(value)
        print("Profile name:", value)
    end,
})
```

## Live telemetry

```lua
Card:AddStatusItem(
    id: string,
    label: string,
    initialValue: string,
    initialColor: Color3?
): Status

Status:SetText(newText: string): ()
Status:SetColor(newColor: Color3): ()
Status:Destroy(): ()
```

Status identifiers must be unique within a card. Status items are excluded from configuration profiles.

Updates modify retained text and color properties. They do not reconstruct the card or allocate replacement Drawing objects.

```lua
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local fpsStatus = metrics:AddStatusItem(
    "fps", "FPS", "Measuring...", Color3.fromRGB(190, 195, 210)
)

local pingStatus = metrics:AddStatusItem(
    "ping", "Network ping", "Measuring...", Color3.fromRGB(190, 195, 210)
)

local frames = 0
local elapsed = 0

local telemetryConnection = RunService.RenderStepped:Connect(function(dt)
    frames += 1
    elapsed += dt

    if elapsed < 0.5 then
        return
    end

    fpsStatus:SetText(string.format("%.0f", frames / elapsed))
    fpsStatus:SetColor(Color3.fromRGB(255, 255, 255))

    local ok, seconds = pcall(function()
        return player:GetNetworkPing()
    end)

    if ok and type(seconds) == "number" then
        pingStatus:SetText(string.format("%.0f ms", seconds * 1000))
    else
        pingStatus:SetText("Unavailable")
    end

    frames = 0
    elapsed = 0
end)

-- Attach application-owned cleanup to every window destruction path.
local destroyWindow = window.Destroy

function window:Destroy()
    if telemetryConnection then
        telemetryConnection:Disconnect()
        telemetryConnection = nil
    end

    destroyWindow(self)
end

window.Remove = window.Destroy
```

The ping value is the network measurement returned by Roblox, converted from seconds to milliseconds.

Application-created connections are owned by the application. The wrapper above disconnects telemetry when the modal, `Vesna:Unload()`, or application code destroys this window.

## Configuration and state persistence

Profiles are stored locally:

```text
VesnaConfigs/
└── <GameId>/
    ├── default.json
    └── <ConfigName>.json
```

Each window receives a configuration manager at `window.Config`.

Required filesystem functions are `isfolder`, `makefolder`, `writefile`, `readfile`, and `listfiles`. Deletion additionally requires `delfile`; automatic default-profile detection uses `isfile`.

### Auto-save

```lua
window.Config:SetAutoSave(enabled: boolean): ()
```

Enabling auto-save schedules a write to `default.json`. Each persisted state change resets a 0.5-second countdown. The write occurs after changes stop for that interval.

```lua
window.Config:SetAutoSave(true)
```

The debounce reduces write frequency during slider dragging and text editing. Filesystem writes are synchronous; debounce does not make disk I/O nonblocking.

### Serialization

| Control state | JSON representation |
|---|---|
| Toggle | Boolean |
| Slider | Number |
| Dropdown | String |
| Text input | String |
| Keybind | KeyCode name, or `"NONE"` when unbound |

Profiles also contain the schema version, GameId, auto-save setting, and each control's kind.

Loading validates applicable entries before changing controls. It checks value types, slider ranges, dropdown membership, and key names. Unknown control identifiers are ignored.

Loading invokes control callbacks while suppressing recursive auto-save scheduling.

### Manual operations

```lua
window.Config:Save(name: string): (boolean, string)
window.Config:Load(name: string): (boolean, number | string)
window.Config:List(): (boolean, {string} | string)
window.Config:Delete(name: string): (boolean, any)
```

On failure, operations return `false` followed by an error string. Successful saves return the path; successful loads return the number of applied controls; listing returns sorted names without `.json`.

Names must contain 1–48 ASCII letters, numbers, spaces, underscores, or hyphens.

The library does not expose native `SaveConfig`, `LoadConfig`, or `GetConfigs` methods. These application helpers provide those names:

```lua
local function SaveConfig(name: string)
    return window.Config:Save(name)
end

local function LoadConfig(name: string)
    return window.Config:Load(name)
end

local function GetConfigs()
    return window.Config:List()
end

local saved, saveResult = SaveConfig("workspace")
if not saved then
    warn(saveResult)
end

local listed, configs = GetConfigs()
if listed then
    for _, name in ipairs(configs) do
        print(name)
    end
else
    warn(configs)
end

local loaded, loadResult = LoadConfig("workspace")
if not loaded then
    warn(loadResult)
end
```

### Configuration interface

```lua
Window:CreateConfigTab(): Tab
```

Creates the auto-save switch, file dropdown, name input, and Save, Load, Delete, and Refresh actions.

The bundled demo attempts to load an existing `default.json`. Custom windows should load a profile explicitly after constructing their persisted controls.

## Global controls and lifecycle

### Visibility

`Enum.KeyCode.RightControl` is the default visibility shortcut.

Set a different key during construction:

```lua
local secondaryWindow = Vesna:CreateWindow({
    Title = "VESNA",
    ToggleKey = Enum.KeyCode.Insert,
})

secondaryWindow:Destroy()
```

An existing window can be rebound directly:

```lua
window.ToggleKey = Enum.KeyCode.Insert
window:SetVisible(false)
window:SetVisible(true)
```

Visibility changes apply to all owned Drawing objects and cancel active editing, rebinding, dropdown, and drag interactions. Hidden windows remain allocated and can be shown again.

Native Roblox text entry suppresses the visibility shortcut.

### Close confirmation

Clicking the header `X` opens a dimmed confirmation modal:

- **Cancel** closes the modal.
- **Unload** destroys that window and reports completion to the console.

`Escape` dismisses the modal. Other component interactions are blocked while it is open.

Programmatic `window:Destroy()` performs immediate teardown without prompting.

### Destruction and ownership

```lua
window:Destroy()
Vesna:Unload()
```

Destruction is idempotent. Each node owns its children and Drawing records.

Teardown:

1. Cancels owned avatar-loading work.
2. Clears input captures and active editing state.
3. Recursively destroys child components.
4. Calls `Remove()` on every owned Drawing object.
5. Removes the window from dispatcher routing.
6. Disconnects the shared rendering and input connections when no windows remain.

Individual tabs, cards, controls, profile widgets, and vector logos also support destruction through the ownership hierarchy.

Library teardown releases library-owned resources. It does not disconnect connections or remove objects created independently by application callbacks.

## Verification

Version 1.10.0 passed:

| Check | Result |
|---|---|
| Desktop mock regression | 2,623 assertions |
| Live Potassium regression | 12,800 checks |
| Targeted vector-logo validation | 6,288 checks |
| Vector drag tracking | 120 frames |
| Vector redraw allocation | No new Drawing objects |
| Tested teardown paths | No remaining owned Drawing objects or connections |

Run the desktop suite from a checkout:

```sh
mkdir work
lua Vesna.test.lua Vesna.luau work
```

Desktop previews simulate Drawing output. The connected Potassium tooling provided execution and console inspection, but no client screenshot capture. These checks verify runtime behavior, geometry, and resource cleanup; they do not establish identical rasterization across Drawing hosts.
