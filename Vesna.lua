-- Vesna / Drawing-only Crimson Rose Bento UI / 1.10
-- Host contract: Drawing.new supports Square, Text, Circle, Line, ZIndex,
-- Transparency (1 = opaque), Visible and :Remove(). No Roblox GUI instances.
-- All geometry uses screen coordinates. MouseOffset adapts viewport-space hosts.
-- This file intentionally uses the Lua 5.4-compatible subset of Luau for testing.

-- ============================================================================
-- 1. Math & Drawing helpers
-- ============================================================================
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = game:GetService("Players").LocalPlayer
local HttpService = game:GetService("HttpService")
local V2 = Vector2.new
local RGB = Color3.fromRGB
local Math = {}
local Metrics = { Width=755, Height=493, Header=38, Sidebar=158,
    Padding=14, Gap=10, RowGap=3, ToggleRow=34, SliderRow=34 }
local function pixel(v) return V2(math.floor(v.X+0.5),math.floor(v.Y+0.5)) end

function Math.isHovered(point, position, size)
    return point.X >= position.X and point.Y >= position.Y
        and point.X < position.X + size.X and point.Y < position.Y + size.Y
end

function Math.lerp(a, b, t) return a + (b - a) * t end
function Math.damp(a, b, speed, dt)
    -- Exponential response is stable at different refresh rates and cannot overshoot.
    return Math.lerp(a, b, 1 - math.exp(-speed * math.max(0, dt)))
end
function Math.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function Math.round(v, decimals)
    local scale = 10 ^ decimals
    return math.floor(v * scale + 0.5) / scale
end

local Theme = {
    Background = RGB(13, 14, 18), Surface = RGB(20, 22, 29),
    Raised = RGB(28, 31, 40), Border = RGB(36, 40, 52),
    Header = RGB(245, 245, 247), Text = RGB(245, 245, 250),
    Muted = RGB(190, 195, 210), Quiet = RGB(105, 111, 128),
    Accent = RGB(244, 63, 94), AccentHover = RGB(255, 90, 120),
    AccentGlow = RGB(225, 29, 72), Status = RGB(255,255,255),
}

local function detach(list, item)
    for i = #list, 1, -1 do
        if list[i] == item then table.remove(list, i); return end
    end
end

local function finite(v)
    return type(v) == "number" and v == v and math.abs(v) < math.huge
end

local function assertLive(owner)
    assert(not owner.Destroyed, "Vesna: object has been destroyed")
end

local function keyName(key)
    if not key then return "None" end
    local names = { LeftControl = "L CTRL", RightControl = "R CTRL",
        LeftShift = "L SHIFT", RightShift = "R SHIFT", Space = "SPACE" }
    return names[key.Name] or string.upper(key.Name)
end

local function validKey(key)
    return typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode
        and key ~= Enum.KeyCode.Unknown
end

-- Owned retained drawings: allocate once, update changed properties only.
local Paint = {}
function Paint.make(owner, kind, props)
    local raw = Drawing.new(kind)
    local record = { Raw = raw, Cache = {}, Wanted = false, Layer = 0 }
    table.insert(owner.Drawings, record) -- register before assigning any property
    props = props or {}
    props.Visible = false
    props.Transparency = props.Transparency or 1
    if kind == "Text" then
        props.Font = 0 -- hardcoded across EVERY Text, including the profile
        props.Size = 14
        props.Outline = false
        props.OutlineColor = RGB(0,0,0)
        props.Center = false
    elseif kind == "Square" or kind == "Circle" then
        props.Filled = props.Filled ~= false
        props.Thickness = props.Thickness or 1
        if kind == "Circle" then props.NumSides = 32 end
    elseif kind == "Line" then
        props.Thickness = props.Thickness or 1
    end
    for k, v in pairs(props) do raw[k] = v; record.Cache[k] = v end
    return record
end

function Paint.set(record, props)
    for key, value in pairs(props) do
        if record.Cache[key] ~= value then
            record.Raw[key] = value
            record.Cache[key] = value
        end
    end
end

function Paint.show(owner, record, layer, props)
    record.Wanted = true
    record.Layer = layer
    Paint.set(record, props)
    Paint.set(record, { ZIndex = owner.Window.Order * 2000 + layer })
end

function Paint.box(owner, record, p, s, color, z)
    Paint.show(owner, record, z, { Position = pixel(p), Size = pixel(s), Color = color })
end

function Paint.text(owner, record, p, text, color, size, z, width)
    assert(size>=11 and size<=16 and size%1==0,"Typography uses integer 11..16px (12px keycaps and slider values) sizes")
    text = tostring(text)
    local sourceText = text
    local fit = record.Fit
    -- Cache measured truncation: static labels no longer rewrite Text or query
    -- TextBounds repeatedly while the pointer or an unrelated animation moves.
    if fit and fit.Source==text and fit.Size==size and fit.Width==width then
        Paint.show(owner,record,z,{Position=pixel(p),Text=fit.Text,Color=color,Size=size})
        return
    end
    Paint.set(record, { Text = text, Size = size })
    -- Drawing.TextBounds gives the actual host font metrics. Truncate by UTF-8
    -- codepoint boundaries so Unicode names never produce invalid byte strings.
    if width and record.Raw.TextBounds.X > width then
        local ends = { 0 }
        for byte in utf8.codes(text) do
            if byte > 1 then table.insert(ends, byte - 1) end
        end
        table.insert(ends, #text)
        local low, high, best = 1, #ends, ""
        while low <= high do
            local middle = math.floor((low + high) / 2)
            local candidate = text:sub(1, ends[middle]) .. "..."
            Paint.set(record, { Text = candidate })
            if record.Raw.TextBounds.X <= width then
                best = candidate; low = middle + 1
            else high = middle - 1 end
        end
        text = best
    end
    record.Fit={Source=sourceText,Size=size,Width=width,Text=text}
    Paint.show(owner, record, z, { Position = pixel(p), Text = text, Color = color, Size = size })
end

function Paint.centerText(owner,record,p,s,text,color,size,z,padding)
    Paint.set(record,{Center=true})
    local height=record.Fit and record.Fit.Size==size and record.Raw.TextBounds.Y or size
    Paint.text(owner,record,p+V2(s.X/2,(s.Y-height)/2),text,color,size,z,math.max(0,s.X-(padding or 0)*2))
    local measured=record.Raw.TextBounds.Y
    if measured~=height then Paint.set(record,{Position=pixel(p+V2(s.X/2,(s.Y-measured)/2))}) end
end

function Paint.circle(owner, record, p, radius, color, z)
    Paint.show(owner, record, z, { Position = pixel(p), Radius = radius, Color = color })
end

function Paint.line(owner, record, a, b, color, z)
    Paint.show(owner, record, z, { From = pixel(a), To = pixel(b), Color = color })
end

function Paint.capsule(owner)
    return { Paint.make(owner, "Square"), Paint.make(owner, "Circle"),
        Paint.make(owner, "Circle") }
end

function Paint.pill(owner, parts, p, s, color, z)
    local r = s.Y / 2
    Paint.box(owner, parts[1], p + V2(r, 0), V2(math.max(0, s.X - 2*r), s.Y), color, z)
    Paint.circle(owner, parts[2], p + V2(r, r), r, color, z)
    Paint.circle(owner, parts[3], p + V2(s.X-r, r), r, color, z)
end

-- Retained pseudo-glow. Construct once inside guarded setup; redraw updates
-- existing outline passes. Never allocate Drawing objects from RenderStepped.
-- radius > 0 selects a circle centered at position+size/2; radius=0 is a box.
local Glow = {}; Glow.__index=Glow
local GlowAlpha = {0.15,0.08,0.03}
function Paint.newGlow(owner, shape, layers, z)
    local glow=setmetatable({Owner=owner,Passes={},Shape=shape,Z=z},Glow)
    for i=1,layers do glow.Passes[i]=Paint.make(owner,shape,{Filled=false,Thickness=1,Transparency=GlowAlpha[i] or 0.03*math.exp(-(i-3))}) end
    return glow
end
function Glow:DrawGlow(position,size,color,radius,layers,opacity)
    opacity=opacity or 1
    layers=math.min(layers or #self.Passes,#self.Passes)
    for i=layers,1,-1 do
        local pass=self.Passes[i]
        local expansion=i-1 -- exact edge, +1px, +2px; exponential alpha decay
        Paint.set(pass,{Transparency=(GlowAlpha[i] or 0.03*math.exp(-(i-3)))*opacity})
        if self.Shape=="Circle" then
            Paint.circle(self.Owner,pass,position+size/2,radius+expansion,color,self.Z)
        else
            Paint.box(self.Owner,pass,position-V2(expansion,expansion),size+V2(2*expansion,2*expansion),color,self.Z)
        end
    end
end
-- The helper is bound to an owned, preallocated Glow handle:
-- owner.Glow:DrawGlow(position, size, color, radius, layers)

-- ============================================================================
-- 2. Ownership, engine and OOP component classes
-- ============================================================================
local Node = {}
Node.__index = Node
local Manager = { Windows = {}, Connections = {}, Hits = {}, Serial = 0 }
local Window = setmetatable({}, { __index = Node }); Window.__index = Window
local Tab = setmetatable({}, { __index = Node }); Tab.__index = Tab
local Card = setmetatable({}, { __index = Node }); Card.__index = Card
local Control = setmetatable({}, { __index = Node }); Control.__index = Control
local Toggle = setmetatable({}, { __index = Control }); Toggle.__index = Toggle
local Slider = setmetatable({}, { __index = Control }); Slider.__index = Slider
local Dropdown = setmetatable({}, { __index = Control }); Dropdown.__index = Dropdown
local Keybind = setmetatable({}, { __index = Control }); Keybind.__index = Keybind
local Button = setmetatable({}, { __index = Control }); Button.__index = Button
local Label = setmetatable({}, { __index = Control }); Label.__index = Label
local Profile = setmetatable({}, { __index = Node }); Profile.__index = Profile
local VectorLogo = setmetatable({}, { __index = Node }); VectorLogo.__index = VectorLogo

local function init(object, parent, class)
    setmetatable(object, class)
    object.Parent = parent
    object.Window = parent and parent.Window or object
    object.Children, object.Drawings = {}, {}
    object.Destroyed = false
    if parent then table.insert(parent.Children, object) end
    return object
end

local function guarded(owner, build)
    -- Partial construction must clean up too: unsupported Drawing properties,
    -- allocation errors and invalid configuration cannot orphan drawings.
    local ok, result = xpcall(build, debug.traceback)
    if not ok then owner:Destroy(); error(result, 0) end
    return result
end

function Node:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    -- Only the avatar fetch is library-owned async work. Stop it before removing
    -- its target image; completion also checks Destroyed after every yield.
    if self.AvatarTask and task.cancel then pcall(task.cancel,self.AvatarTask) end
    self.AvatarTask=nil
    local window = self.Window
    if Manager.Capture and Manager.Capture.Owner == self then Manager.Capture = nil end
    if window.Popup == self then window.Popup = nil end
    if window.Listening == self then window.Listening = nil end
    if window.InputFocus == self then self.Repeat=nil; window.InputFocus = nil end
    -- Copy-free recursive teardown; each child detaches itself from this list.
    while #self.Children > 0 do self.Children[#self.Children]:Destroy() end
    for _, record in ipairs(self.Drawings) do
        local ok, err = pcall(function() record.Raw:Remove() end)
        if not ok then warn("Vesna Drawing removal failed: " .. tostring(err)) end
        record.Raw, record.Cache = nil, nil
    end
    self.Drawings = {}
    self.Callback, self.OnChanged = nil, nil
    -- Purge routing immediately, including destruction during a callback.
    for i = #Manager.Hits, 1, -1 do
        if Manager.Hits[i].Owner == self then table.remove(Manager.Hits, i) end
    end
    if self.Parent then
        local parent = self.Parent
        detach(parent.Children, self)
        if parent.Cards then detach(parent.Cards, self) end
        if parent.Controls then detach(parent.Controls, self); parent:Reflow() end
        if self.ConfigId and self.Window.Config and self.Window.Config.Controls[self.ConfigId]==self then self.Window.Config.Controls[self.ConfigId]=nil end
        if self.StatusId and parent.StatusItems then parent.StatusItems[self.StatusId]=nil end
        if parent.Tabs then
            detach(parent.Tabs, self)
            if parent.Active == self then parent.Active = parent.Tabs[1] end
            parent:CancelInteraction()
        end
    end
    self.Parent = nil
end
Node.Remove = Node.Destroy

function Node:Emit(field, ...)
    local callback = self[field]
    if not callback or self.Destroyed then return end
    local args = table.pack(...)
    -- Never yield an input/render connection. Deferred callbacks skip destroyed
    -- owners; application errors cannot corrupt the UI's event dispatcher.
    task.defer(function()
        if self.Destroyed then return end
        if self.Kind=="Keybind" and field=="Callback" and
            (Manager:KeyboardBlocked() or self.Window.InputFocus or self.Window.Listening or not self.Window.Visible or self.Window.Modal or self.Window.Active~=self.Card.Parent) then return end
        local ok, err = xpcall(function()
            callback(table.unpack(args, 1, args.n))
        end, debug.traceback)
        if not ok then warn("Vesna callback: " .. tostring(err)) end
    end)
end

local function walk(owner, fn)
    fn(owner)
    for _, child in ipairs(owner.Children) do walk(child, fn) end
end

local function hit(owner, p, s, layer, action, data)
    table.insert(Manager.Hits, { Owner = owner, Window = owner.Window,
        Position = p, Size = s, Z = owner.Window.Order * 2000 + layer,
        Action = action, Data = data })
end

function Manager:Mouse(window)
    return UIS:GetMouseLocation() + window.MouseOffset
end

function Manager:Front(window)
    for _, other in ipairs(self.Windows) do
        if other ~= window then other:CancelInteraction() end
    end
    self.Serial = self.Serial + 1
    window.Order = self.Serial
end

function Manager:Pick()
    local best
    for _, region in ipairs(self.Hits) do
        if not region.Owner.Destroyed and region.Window.Visible
            and (not region.Window.Modal or region.Z%2000>=1202)
            and Math.isHovered(self:Mouse(region.Window), region.Position, region.Size)
            and (not best or region.Z >= best.Z) then best = region end
    end
    return best
end

function Manager:KeyboardBlocked()
    return UIS:GetFocusedTextBox()~=nil
end
function Manager:Modifiers()
    return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl),
        UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
end

function Manager:Render(dt)
    self.Hits = {}
    for _, window in ipairs(self.Windows) do
        if not window.Destroyed then
            local ok, err = xpcall(function()
                walk(window, function(owner)
                    for _, record in ipairs(owner.Drawings) do record.Wanted = false end
                end)
                if self:KeyboardBlocked() then
                    window.Listening=nil
                    if window.InputFocus then window.InputFocus.Repeat=nil; window.InputFocus=nil end
                elseif window.InputFocus then window.InputFocus:Tick(dt) end
                if window.Config then window.Config:Tick(dt) end
                window:Render(dt)
                walk(window, function(owner)
                    for _, record in ipairs(owner.Drawings) do
                        Paint.set(record, { Visible = record.Wanted })
                    end
                end)
            end, debug.traceback)
            if not ok then
                warn("Vesna render failed; window hidden: " .. tostring(err))
                window:SetVisible(false)
            end
        end
    end
end

function Manager:Stop()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Connections, self.Hits = {}, {}
    self.Capture = nil
    self.OnInputBegan, self.OnInputEnded = nil,nil
    self.Serial = 0
end

function Manager:Start()
    if #self.Connections > 0 then return end
    local function connect(signal, fn) table.insert(self.Connections, signal:Connect(fn)) end
    connect(RunService.RenderStepped, function(dt) self:Render(dt) end)
    self.OnInputBegan = function(input, processed)
        self:Render(0) -- refresh geometry and hit boxes between frames
        if input.UserInputType==Enum.UserInputType.Keyboard then
            -- Chat and other Roblox textboxes always own keyboard input, even
            -- with RespectProcessed=false. Opening chat also cancels captures.
            if processed or self:KeyboardBlocked() then
                for _,w in ipairs(self.Windows) do
                    w.Listening=nil
                    if w.InputFocus then w.InputFocus.Repeat=nil; w.InputFocus=nil end
                end
                return
            end
            for _,w in ipairs(self.Windows) do
                if w.InputFocus and w.Visible and not w.Modal then
                    if not processed and not UIS:GetFocusedTextBox() then w.InputFocus:HandleKey(input.KeyCode) end
                    return
                end
            end
        end
        local listening
        for _, window in ipairs(self.Windows) do
            if window.Listening and (not listening or window.Order > listening.Window.Order) then
                listening = window.Listening
            end
        end
        if listening and input.UserInputType == Enum.UserInputType.Keyboard then
            if processed or UIS:GetFocusedTextBox() then return end
            if input.KeyCode == Enum.KeyCode.Escape then
                listening.Window.Listening = nil
            elseif input.KeyCode == Enum.KeyCode.Backspace then
                listening:Set(nil); listening.Window.Listening = nil
            elseif validKey(input.KeyCode) then
                listening:Set(input.KeyCode); listening.Window.Listening = nil
            end
            return -- captured key must never trigger a bind or visibility toggle
        end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if UIS:GetFocusedTextBox() then return end
            for _, window in ipairs(self.Windows) do
                if not processed or not window.RespectProcessed then
                    if input.KeyCode == window.ToggleKey then
                        window:SetVisible(not window.Visible)
                    elseif window.Visible then
                        if window.Modal then
                            if input.KeyCode==Enum.KeyCode.Escape then window.Modal=false end
                            return
                        end
                        if input.KeyCode == Enum.KeyCode.Escape then window:CancelInteraction() end
                        if window.Active then
                            for _, card in ipairs(window.Active.Cards) do
                                for _, control in ipairs(card.Controls) do
                                    if control.Kind == "Keybind" and control.Value == input.KeyCode then
                                        control:Emit("Callback", control.Value)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local region = self:Pick()
        if region and processed and region.Window.RespectProcessed then return end
        -- Only the topmost visible window can own a popup. Outside clicks close
        -- it and consume the click, preventing accidental underlying activation.
        local top
        for _, window in ipairs(self.Windows) do
            if window.Visible and (not top or window.Order > top.Order) then top = window end
        end
        if top and top.Popup and (not region or region.Owner ~= top.Popup) then
            top.Popup = nil; return
        end
        if not region then
            if top then if top.InputFocus then top.InputFocus.Repeat=nil end; top.Listening,top.InputFocus = nil,nil end
            return
        end
        local window = region.Window
        self:Front(window)
        if window.InputFocus and window.InputFocus~=region.Owner then window.InputFocus.Repeat=nil; window.InputFocus=nil end
        if window.Listening and window.Listening ~= region.Owner then window.Listening = nil end
        region.Owner:Press(region.Action, region.Data, self:Mouse(window))
    end
    connect(UIS.InputBegan,self.OnInputBegan)
    connect(UIS.InputChanged, function(input, processed)
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            self:Render(0)
            local region = self:Pick()
            if region and (not processed or not region.Window.RespectProcessed) then
                local window = region.Window
                if window.Modal then return
                elseif window.Popup then
                    if region.Owner == window.Popup then
                        window.Popup:ScrollBy(-input.Position.Z)
                    end
                elseif region.Owner.Card then
                    region.Owner.Card:ScrollBy(-input.Position.Z * 38)
                elseif region.Owner == window.Active then
                    window.NavScroll = Math.clamp(window.NavScroll-input.Position.Z*38,
                        0, window.NavMaximum or 0)
                elseif region.Owner.ScrollBy then region.Owner:ScrollBy(-input.Position.Z * 38) end
            end
        end
    end)
    self.OnInputEnded=function(input)
        if input.UserInputType==Enum.UserInputType.Keyboard then
            for _,w in ipairs(self.Windows) do
                local editor=w.InputFocus
                if editor and editor.Repeat and editor.Repeat.Key==input.KeyCode then editor.Repeat=nil end
            end
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local capture = self.Capture
        self.Capture = nil
        if capture and not capture.Owner.Destroyed then
            local mouse = self:Mouse(capture.Owner.Window)
            if capture.Kind == "Button" then capture.Owner:Release(mouse) end
            if capture.Kind == "Slider" and capture.Owner.Onscreen then capture.Owner:UpdateMouse(mouse) end
            if capture.Kind == "TextSelect" and capture.Owner.Onscreen then capture.Owner:Move(capture.Owner:Nearest(mouse),true) end
            if capture.Kind == "Drag" then capture.Owner.Target=mouse-capture.Offset end
        end
    end
    connect(UIS.InputEnded,self.OnInputEnded)
    connect(UIS.WindowFocusReleased, function()
        self.Capture = nil
        for _, window in ipairs(self.Windows) do window:CancelInteraction() end
    end)
end

local Library = { Version = "1.10.1", Math = Math, Metrics = Metrics }

function Library:CreateWindow(config)
    config = config or {}
    assert(Drawing and Drawing.new, "Vesna requires a Drawing API host")
    local camera = workspace.CurrentCamera
    assert(camera, "Vesna requires a client camera")
    local viewport = camera.ViewportSize
    assert(viewport.X >= 771 and viewport.Y >= 509, "Vesna needs a 771x509 desktop viewport")
    local size = V2(Metrics.Width, Metrics.Height)
    assert(config.Font==nil or config.Font==0,"Font is locked to Drawing.Fonts.UI (0)")
    local position = config.Position or (viewport-size)/2
    local window = init({ Title = config.Title or "VESNA", Size = size,
        Position = position, Target = position, Visible = true, Modal = false,
        Font = 0, MouseOffset = config.MouseOffset or V2(0, 0),
        ToggleKey = config.ToggleKey or Enum.KeyCode.RightControl,
        RespectProcessed = config.RespectProcessed ~= false, Tabs = {},
        FPS = 0, Frames = 0, Elapsed = 0, NavScroll = 0 }, nil, Window)
    window.Theme = {}
    for k, v in pairs(Theme) do window.Theme[k] = v end
    if config.Accent then window.Theme.Accent = config.Accent end
    assert(validKey(window.ToggleKey), "ToggleKey must be an Enum.KeyCode")
    return guarded(window, function()
        window.Bg = Paint.make(window, "Square")
        window.Edge = Paint.make(window, "Square", { Filled = false })
        window.Divider = Paint.make(window, "Line")
        window.Side = Paint.make(window, "Line")
        window.Brand = Paint.make(window, "Text")
        window.Subtitle = Paint.make(window, "Text")
        window.Telemetry = Paint.make(window, "Text")
        window.Dot = Paint.make(window, "Circle")
        window.CloseA = Paint.make(window, "Line")
        window.CloseB = Paint.make(window, "Line")
        window.CloseBg = Paint.make(window, "Square")
        window.Heading = Paint.make(window, "Text")
        window.ModalDraw = {}
        for _,key in ipairs({"Dim","Box","Edge","Cancel","Unload"}) do
            window.ModalDraw[key]=Paint.make(window,"Square",{Filled=key~="Edge"})
        end
        for _,key in ipairs({"Title","Sub1","Sub2","CancelText","UnloadText"}) do
            window.ModalDraw[key]=Paint.make(window,"Text")
        end
        window:CreateLogo()
        window.Profile = window:CreateProfile({Callback=config.ProfileCallback})
        window:CreateConfigManager()
        table.insert(Manager.Windows, window)
        Manager:Front(window)
        Manager:Start()
        return window
    end)
end

-- Native 16x20 faceted emblem. Shared vertices guarantee connected endpoints.
-- Six outer edges, four diamond edges, two axial connectors: twelve lines total.
local logoRose,logoWhite=RGB(244,63,94),RGB(255,255,255)
local logoVertices = {
    V2(8,0), V2(16,5), V2(16,15), V2(8,20), V2(0,15), V2(0,5),
    V2(8,5), V2(12,10), V2(8,15), V2(4,10),
}
local logoEdges = {
    {1,2}, {2,3}, {3,4}, {4,5}, {5,6}, {6,1},
    {7,8}, {8,9}, {9,10}, {10,7}, {1,7}, {4,9},
}
function Window:CreateLogo()
    assertLive(self)
    if self.Logo then self.Logo:Destroy() end
    local logo=init({Lines={}},self,VectorLogo)
    self.Logo=logo
    return guarded(logo,function()
        for i=1,#logoEdges do
            logo.Lines[i]=Paint.make(logo,"Line",{
                Thickness=1,Transparency=i>=7 and i<=10 and 0.9 or 1,
                Color=i>=7 and i<=10 and logoWhite or logoRose,
            })
        end
        return logo
    end)
end
function VectorLogo:Render(base)
    if self.Destroyed then return end
    base=pixel(base)
    for i,edge in ipairs(logoEdges) do
        local color=i>=7 and i<=10 and logoWhite or logoRose
        Paint.line(self,self.Lines[i],base+logoVertices[edge[1]],base+logoVertices[edge[2]],color,5)
    end
end

function Window:CancelInteraction()
    if self.InputFocus then self.InputFocus.Repeat=nil end
    self.Popup, self.Listening, self.InputFocus = nil, nil, nil
    if Manager.Capture and Manager.Capture.Owner.Window == self then Manager.Capture = nil end
end

function Window:SetVisible(value)
    assertLive(self)
    self.Visible = value == true
    self:CancelInteraction()
    if not self.Visible then
        walk(self, function(owner)
            for _, record in ipairs(owner.Drawings) do Paint.set(record, { Visible = false }) end
        end)
    end
end

function Window:SetAccent(color)
    assertLive(self); assert(typeof(color) == "Color3", "Accent must be Color3")
    self.Theme.Accent = color
end

-- LocalPlayer identity is encapsulated in a child owner, including the optional
-- Image and its fetch task. Profile click selects the Profiles tab by default;
-- ProfileCallback(player) can supply application-specific account actions.
function Window:CreateProfile(config)
    assertLive(self)
    config=config or {}
    assert(not config.Callback or type(config.Callback)=="function","ProfileCallback must be a function")
    local profile=init({Player=LocalPlayer,Hover=0,Callback=config.Callback,
        AvatarReady=false,AvatarStatus="fallback"},self,Profile)
    return guarded(profile,function()
        profile.Bg=Paint.make(profile,"Square")
        profile.Edge=Paint.make(profile,"Square",{Filled=false})
        profile.Fallback=Paint.make(profile,"Circle")
        profile.Initial=Paint.make(profile,"Text")
        profile.Display=Paint.make(profile,"Text")
        profile.Handle=Paint.make(profile,"Text")
        local first=#profile.Drawings+1
        local ok,image=pcall(function() return Paint.make(profile,"Image",{Size=V2(34,34)}) end)
        if ok then profile.Image=image
        else
            -- Optional Image setup can fail after allocation. Roll back just
            -- that attempt, preserving the always-available initials fallback.
            for i=#profile.Drawings,first,-1 do
                local record=table.remove(profile.Drawings,i)
                pcall(function() record.Raw:Remove() end)
            end
            profile.AvatarStatus="unsupported"
        end
        if profile.Image and profile.Player then
            profile.AvatarStatus="loading"
            profile.AvatarTask=task.defer(function()
                if profile.Destroyed then return end
                local fetched,data=pcall(function() return profile:GetAvatarRawData() end)
                if profile.Destroyed then return end
                -- Reject HTML/JSON/error responses even if the request succeeds.
                if fetched and type(data)=="string" and data:sub(1,8)=="\137PNG\r\n\26\n" then
                    local assigned=pcall(function() Paint.set(profile.Image,{Data=data}) end)
                    profile.AvatarReady=assigned
                    profile.AvatarStatus=assigned and "ready" or "fallback"
                    if assigned then profile.AvatarBytes=#data end
                else
                    profile.AvatarStatus="fallback"
                    profile.AvatarError=fetched and "Thumbnail response was not PNG" or tostring(data)
                end
                profile.AvatarTask=nil
            end)
        end
        return profile
    end)
end

function Profile:GetAvatarRawData()
    local apiUrl=string.format("https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=150x150&format=Png&isCircular=true",self.Player.UserId)
    -- Completed metadata yields a CDN image URL; Data must receive its binary
    -- response, never the JSON response or the image URL string.
    for attempt=1,3 do
        if self.Destroyed then return nil end
        local response=HttpService:JSONDecode(game:HttpGet(apiUrl))
        if self.Destroyed then return nil end
        local entry=type(response)=="table" and type(response.data)=="table" and response.data[1]
        local url=type(entry)=="table" and entry.imageUrl
        if type(url)=="string" and url:match("^https://") then
            return game:HttpGet(url)
        end
        if attempt<3 and entry and entry.state=="Pending" then task.wait(0.25*attempt)
        else error("Thumbnail metadata has no completed image URL") end
    end
    return nil
end

function Profile:Press()
    self.Window:CancelInteraction()
    if self.Callback then self:Emit("Callback",self.Player); return end
    for _,tab in ipairs(self.Window.Tabs) do
        if tab.Name=="Profiles" then self.Window:SelectTab(tab); return end
    end
end

function Profile:Render(p,dt)
    local theme=self.Window.Theme
    local s=V2(138,52)
    self.Position,self.Size=p,s
    self.Hover=Math.damp(self.Hover,Math.isHovered(Manager:Mouse(self.Window),p,s) and 1 or 0,18,dt)
    Paint.box(self,self.Bg,p,s,theme.Surface:Lerp(theme.Raised,self.Hover),10)
    Paint.box(self,self.Edge,p,s,theme.Border:Lerp(theme.AccentHover,self.Hover*0.4),11)
    local avatar=p+V2(9,9)
    local name=self.Player and self.Player.Name or "Guest"
    local display=self.Player and self.Player.DisplayName or "Local player"
    if self.AvatarReady and self.Image then
        Paint.show(self,self.Image,12,{Position=pixel(avatar),Size=V2(34,34)})
    else
        Paint.circle(self,self.Fallback,avatar+V2(17,17),17,theme.Raised,12)
        local initial=string.upper(name:sub(1,utf8.offset(name,2) and utf8.offset(name,2)-1 or #name))
        Paint.text(self,self.Initial,avatar+V2(11,9),initial,theme.Accent,16,13,24)
    end
    Paint.text(self,self.Display,p+V2(51,10),display,theme.Header,14,14,79)
    Paint.text(self,self.Handle,p+V2(51,30),"@"..name,theme.Muted,13,14,79)
    hit(self,p,s,15,"profile")
end

function Window:Destroy()
    if self.Destroyed then return end
    self:CancelInteraction()
    Node.Destroy(self)
    detach(Manager.Windows, self)
    if #Manager.Windows == 0 then Manager:Stop() end
end
Window.Remove = Window.Destroy

function Library:Unload()
    while #Manager.Windows > 0 do Manager.Windows[#Manager.Windows]:Destroy() end
    Manager:Stop()
end

function Window:CreateTab(name, icon)
    assertLive(self)
    local tab = init({ Name = tostring(name), Icon = icon or "o", Cards = {} }, self, Tab)
    return guarded(tab, function()
        tab.Bg = Paint.make(tab, "Square")
        tab.Stripe = Paint.make(tab, "Square")
        tab.Title = Paint.make(tab, "Text")
        tab.Symbol = Paint.make(tab, "Text")
        table.insert(self.Tabs, tab)
        if not self.Active then self.Active = tab end
        return tab
    end)
end

function Window:SelectTab(tab)
    assertLive(self); assert(tab.Parent == self and not tab.Destroyed, "Foreign or destroyed tab")
    self:CancelInteraction(); self.Active = tab
end

function Window:Press(action, _, mouse)
    if action == "close" then self:CancelInteraction(); self.Modal=true
    elseif action == "cancel-modal" then self.Modal=false
    elseif action == "unload-modal" then self:Destroy(); print("Vesna unloaded: UI drawings and library connections removed.")
    elseif action == "drag" then
        self:CancelInteraction()
        Manager.Capture = { Owner = self, Kind = "Drag", Offset = mouse-self.Position }
    end
end

function Window:Render(dt)
    if not self.Visible then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local p, s, theme = self.Position, self.Size, self.Theme
    local height = s.Y
    local capture = Manager.Capture
    if capture and capture.Owner == self and capture.Kind == "Drag" then
        self.Target = Manager:Mouse(self)-capture.Offset
    end
    self.Target = V2(Math.clamp(self.Target.X, 0, math.max(0, viewport.X-s.X)),
        Math.clamp(self.Target.Y, 0, math.max(0, viewport.Y-height)))
    self.Position = Math.damp(self.Position, self.Target, 24, dt)
    p = pixel(self.Position)
    self.RenderPosition=p -- every child uses this same snapped origin
    if dt > 0 then
        self.Frames, self.Elapsed = self.Frames+1, self.Elapsed+dt
        if self.Elapsed >= 0.4 then
            self.FPS = math.floor(self.Frames/self.Elapsed+0.5)
            self.Frames, self.Elapsed = 0, 0
        end
    end
    Paint.box(self, self.Bg, p, V2(s.X, height), theme.Background, 1)
    Paint.box(self, self.Edge, p, V2(s.X, height), theme.Border, 2)
    hit(self, p, V2(s.X, height), 1, "block")
    if self.Logo and not self.Logo.Destroyed then self.Logo:Render(p+V2(16,9)) end
    Paint.text(self, self.Brand, p+V2(42,11), self.Title, theme.Header, 16, 5, s.X-266)
    Paint.circle(self, self.Dot, p+V2(s.X-215, 19), 3, theme.Accent, 5)
    Paint.text(self, self.Telemetry, p+V2(s.X-205, 12), "ONLINE / "..self.FPS.." FPS", theme.Status, 13, 5, 132)
    local mouse = Manager:Mouse(self)
    local closeP = p+V2(s.X-30,7)
    Paint.box(self,self.CloseBg,closeP,V2(24,24),Math.isHovered(mouse,closeP,V2(24,24)) and theme.Raised or theme.Background,4)
    Paint.line(self,self.CloseA,closeP+V2(7,7),closeP+V2(17,17),theme.Muted,6)
    Paint.line(self,self.CloseB,closeP+V2(17,7),closeP+V2(7,17),theme.Muted,6)
    hit(self,p,V2(s.X-38,Metrics.Header),7,"drag")
    hit(self,closeP,V2(24,24),8,"close")
    Paint.line(self,self.Divider,p+V2(0,38),p+V2(s.X,38),theme.Border,3)
    Paint.line(self,self.Side,p+V2(158,38),p+V2(158,s.Y),theme.Border,3)
    Paint.text(self,self.Subtitle,p+V2(14,50),"WORKSPACE",theme.Muted,13,5,130)
    if self.Profile and not self.Profile.Destroyed then self.Profile:Render(p+V2(10,s.Y-70),dt) end
    local navHeight = s.Y-164
    self.NavMaximum = math.max(0,#self.Tabs*40-navHeight)
    self.NavScroll = Math.clamp(self.NavScroll,0,self.NavMaximum)
    for i, tab in ipairs(self.Tabs) do
        local y = 76+(i-1)*40-self.NavScroll
        if y >= 76 and y+34 <= 76+navHeight then tab:RenderNav(p+V2(10,y),dt) end
    end
    if self.Active then
        Paint.text(self,self.Heading,p+V2(172,48),self.Active.Name,theme.Header,16,5,s.X-186)
        hit(self.Active,p+V2(10,76),V2(138,navHeight),3,"block")
        self.Active:Render(p+V2(172,76),V2(s.X-186,s.Y-90),dt)
    end
    if self.Popup then self.Popup:RenderPopup(dt) end
    if self.Modal then self:RenderModal() end
end

function Tab:Press(action)
    if action == "tab" then self.Window:SelectTab(self) end
end

function Tab:ScrollBy(amount)
    self.Window.NavScroll=Math.clamp(self.Window.NavScroll+amount,0,self.Window.NavMaximum or 0)
end

function Tab:RenderNav(p, dt)
    local theme = self.Window.Theme
    local selected = self.Window.Active == self
    self.Hover = Math.damp(self.Hover or 0,
        Math.isHovered(Manager:Mouse(self.Window),p,V2(138,34)) and 1 or 0,18,dt)
    Paint.box(self,self.Bg,p,V2(138,34),theme.Background:Lerp(theme.Raised,selected and 1 or self.Hover),10)
    if selected then Paint.box(self,self.Stripe,p+V2(0,7),V2(2,18),theme.Accent:Lerp(theme.AccentHover,self.Hover),11) end
    Paint.text(self,self.Symbol,p+V2(10,9),self.Icon,selected and theme.Accent or theme.Muted,16,12,14)
    Paint.text(self,self.Title,p+V2(32,9),self.Name,theme.Header,16,12,102)
    hit(self,p,V2(138,34),13,"tab")
end

function Tab:CreateCard(config)
    assertLive(self); config = config or {}
    local column, row = config.Column or 1, config.Row or 1
    local span, rows = config.ColumnSpan or 3, config.RowSpan or 2
    for _, value in ipairs({column,row,span,rows}) do
        assert(finite(value) and value >= 1 and value%1 == 0,"Grid coordinates must be positive integers")
    end
    assert(column+span-1 <= 6,"Card extends beyond the six-column grid")
    assert(row+rows-1 <= 6,"Card extends beyond the six-row grid")
    for _, other in ipairs(self.Cards) do
        assert(column+span <= other.Column or other.Column+other.ColumnSpan <= column
            or row+rows <= other.Row or other.Row+other.RowSpan <= row,"Bento cards may not overlap")
    end
    local card = init({ Name = tostring(config.Name or "CARD"),
        Description = tostring(config.Description or ""), Column = column, Row = row,
        ColumnSpan = span, RowSpan = rows, Controls = {}, Scroll = 0, ContentHeight = 0 },self,Card)
    return guarded(card,function()
        card.Bg = Paint.make(card,"Square")
        card.Edge = Paint.make(card,"Square",{Filled=false})
        card.Glow = Paint.newGlow(card,"Square",2,22)
        card.Title = Paint.make(card,"Text")
        card.DescriptionText = Paint.make(card,"Text")
        card.Scrollbar = Paint.make(card,"Square")
        card.More = Paint.make(card,"Text")
        table.insert(self.Cards,card)
        return card
    end)
end

function Tab:CreateSection(name)
    -- Convenience: alternate half-width cards across successive two-unit rows.
    local index = #self.Cards
    return self:CreateCard({Name=name,Column=(index%2)*3+1,Row=math.floor(index/2)*2+1})
end

function Tab:Render(p,s,dt)
    local gap = Metrics.Gap
    local units = 1
    for _, card in ipairs(self.Cards) do units = math.max(units,card.Row+card.RowSpan-1) end
    -- A lone card retains its declared span but is left-docked and capped.
    -- Multi-card tabs continue using the ordinary Bento canvas.
    local unitWidth = (s.X-5*gap)/6
    local unitHeight = (s.Y-(units-1)*gap)/units
    for _, card in ipairs(self.Cards) do
        local cp = pixel(p+V2((card.Column-1)*(unitWidth+gap),(card.Row-1)*(unitHeight+gap)))
        local far = pixel(p+V2((card.Column-1)*(unitWidth+gap)+card.ColumnSpan*unitWidth+(card.ColumnSpan-1)*gap,
            (card.Row-1)*(unitHeight+gap)+card.RowSpan*unitHeight+(card.RowSpan-1)*gap))
        local cs = far-cp
        if #self.Cards==1 then cp=V2(p.X,cp.Y); cs=V2(math.min(325,cs.X),cs.Y) end
        card:Render(cp,cs,dt)
    end
end

function Card:Reflow()
    local y = 0
    for _, control in ipairs(self.Controls) do control.Offset = y; y = y+control.Height+Metrics.RowGap end
    self.ContentHeight = math.max(0,y-Metrics.RowGap)
end

function Card:ScrollBy(amount)
    self.Window.Popup = nil
    if Manager.Capture and Manager.Capture.Owner.Card == self then Manager.Capture=nil end
    self.Scroll = Math.clamp(self.Scroll+amount,0,self.Maximum or 0)
end
function Card:Press() end

function Card:Render(p,s,dt)
    local theme = self.Window.Theme
    self.Position,self.Size = p,s
    Paint.box(self,self.Bg,p,s,theme.Surface,20)
    Paint.box(self,self.Edge,p,s,theme.Border,21)
    local hovered = not self.Window.Popup and Math.isHovered(Manager:Mouse(self.Window),p,s)
    local captured = Manager.Capture and Manager.Capture.Owner.Card==self
    local active = hovered or captured or (self.Window.Popup and self.Window.Popup.Card==self)
        or (self.Window.Listening and self.Window.Listening.Card==self)
    if active then self.Glow:DrawGlow(p-V2(1,1),s+V2(2,2),theme.AccentGlow,0,2) end
    Paint.text(self,self.Title,p+V2(14,11),self.Name,theme.Header,16,24,s.X-28)
    local header = self.Description ~= "" and 54 or 36
    if self.Description ~= "" then
        Paint.text(self,self.DescriptionText,p+V2(14,35),self.Description,theme.Muted,13,24,s.X-28)
    end
    hit(self,p,s,22,"block")
    self.InnerPosition = p+V2(14,header)
    self.InnerSize = V2(math.max(0,s.X-28),math.max(0,s.Y-header-14))
    self.Maximum = math.max(0,self.ContentHeight-self.InnerSize.Y)
    self.Scroll = Math.clamp(self.Scroll,0,self.Maximum)
    local anyVisible = false
    for _, control in ipairs(self.Controls) do
        local y = control.Offset-self.Scroll
        control.Onscreen = y >= 0 and y+control.Height <= self.InnerSize.Y and self.InnerSize.X >= 80
        if control.Onscreen then
            anyVisible = true
            control:Render(self.InnerPosition+V2(0,y),V2(self.InnerSize.X,control.Height),dt)
        else
            if self.Window.Popup == control then self.Window.Popup = nil end
            if self.Window.Listening == control then self.Window.Listening = nil end
            if self.Window.InputFocus == control then control.Repeat=nil; self.Window.InputFocus = nil end
            if Manager.Capture and Manager.Capture.Owner == control then Manager.Capture=nil end
        end
    end
    -- Drawing has no clip rect: only fully contained control rows are drawn.
    if self.Maximum > 0 and self.InnerSize.Y > 0 then
        local length = math.max(8,self.InnerSize.Y*math.min(1,self.InnerSize.Y/math.max(1,self.ContentHeight)))
        length = math.min(length,self.InnerSize.Y)
        local offset = (self.InnerSize.Y-length)*self.Scroll/self.Maximum
        Paint.box(self,self.Scrollbar,p+V2(s.X-5,header+offset),V2(2,length),theme.Quiet,25)
    end
    if not anyVisible and #self.Controls > 0 and s.Y > header+12 then
        Paint.text(self,self.More,self.InnerPosition,"Scroll to controls",theme.Muted,13,25,self.InnerSize.X)
    end
end

local function createControl(card,config,class,kind,height,setup)
    assertLive(card); config = config or {}
    assert(config.Callback == nil or type(config.Callback) == "function","Callback must be a function")
    local control = init({Card=card,Kind=kind,Name=tostring(config.Name or kind),
        Callback=config.Callback,Height=height,Hover=0,ConfigId=config.Id, Persist=config.Persist~=false},card,class)
    return guarded(control,function()
        control.Bg = Paint.make(control,"Square")
        control.Title = Paint.make(control,"Text")
        setup(control,config)
        table.insert(card.Controls,control); card:Reflow()
        if card.Window.Config then card.Window.Config:Register(control) end
        return control
    end)
end

function Control:Base(p,s,dt)
    self.Position,self.Size = p,s
    local hovered = not self.Window.Popup and Math.isHovered(Manager:Mouse(self.Window),p,s)
    self.Hover = Math.damp(self.Hover,hovered and 1 or 0,18,dt)
    local theme = self.Window.Theme
    Paint.box(self,self.Bg,p,s,theme.Surface:Lerp(theme.Raised,self.Hover*0.8),30)
    return theme
end
function Control:Get() assertLive(self); return self.Value end

function Card:AddToggle(config)
    return createControl(self,config,Toggle,"Toggle",Metrics.ToggleRow,function(c,o)
        c.Value = o.Default == true; c.Amount = c.Value and 1 or 0
        -- Track owns exactly one filled bridge Square and two filled cap Circles.
        -- Paint.pill uses integer centers/radius here; no Rounding property.
        c.Track = Paint.capsule(c); c.Thumb = Paint.make(c,"Circle")
    end)
end
function Toggle:Set(value,silent)
    assertLive(self); assert(type(value)=="boolean","Toggle value must be boolean")
    if self.Value == value then return end
    self.Value = value; if not silent then self:StateChanged() end; if not silent then self:Emit("Callback",value) end
end
function Toggle:Press() self:Set(not self.Value) end
function Toggle:Render(p,s,dt)
    local theme = self:Base(p,s,dt)
    self.Amount = Math.damp(self.Amount,self.Value and 1 or 0,20,dt)
    Paint.text(self,self.Title,p+V2(0,10),self.Name,theme.Text,14,34,s.X-52)
    local track = p+V2(s.X-34,8)
    local thumb=track+V2(9+16*self.Amount,9)
    Paint.pill(self,self.Track,track,V2(34,18),RGB(35,38,50):Lerp(RGB(244,63,94),self.Amount),33)
    Paint.circle(self,self.Thumb,thumb,6,RGB(255,255,255),35)
    hit(self,p,s,36,"toggle")
end

function Card:AddSlider(config)
    return createControl(self,config,Slider,"Slider",Metrics.SliderRow,function(c,o)
        c.Min,c.Max = o.Min or 0,o.Max or 100
        c.Decimals,c.Suffix = o.Decimals or 0,tostring(o.Suffix or "")
        assert(finite(c.Min) and finite(c.Max) and c.Max > c.Min,"Slider needs finite Min < Max")
        assert(finite(c.Decimals) and c.Decimals%1==0 and c.Decimals>=0 and c.Decimals<=6,"Decimals must be 0..6")
        c.Track = Paint.make(c,"Square"); c.Fill = Paint.make(c,"Square")
        c.Thumb = Paint.make(c,"Circle")
        c.ThumbGlow=Paint.newGlow(c,"Circle",3,34)
        c.ValueText = Paint.make(c,"Text")
        c:Set(o.Default or c.Min,true); c.Fraction = (c.Value-c.Min)/(c.Max-c.Min)
    end)
end
function Slider:Set(value,silent)
    assertLive(self); assert(finite(value),"Slider value must be finite")
    value = Math.clamp(Math.round(Math.clamp(value,self.Min,self.Max),self.Decimals),self.Min,self.Max)
    if self.Value == value then return end
    self.Value = value; if not silent then self:StateChanged() end; if not silent then self:Emit("Callback",value) end
end
function Slider:UpdateMouse(mouse)
    local fraction = Math.clamp((mouse.X-self.TrackPosition.X)/self.TrackWidth,0,1)
    self:Set(self.Min+(self.Max-self.Min)*fraction)
end
function Slider:Press(_,_,mouse)
    Manager.Capture = {Owner=self,Kind="Slider"}; self:UpdateMouse(mouse)
end
function Slider:Render(p,s,dt)
    local theme = self:Base(p,s,dt)
    self.TrackPosition,self.TrackWidth = p+V2(6,26),s.X-12
    if Manager.Capture and Manager.Capture.Owner == self then self:UpdateMouse(Manager:Mouse(self.Window)) end
    self.Fraction = Math.damp(self.Fraction,(self.Value-self.Min)/(self.Max-self.Min),24,dt)
    local value=string.format("%."..self.Decimals.."f",self.Value)..self.Suffix
    -- Measure the retained value text, then anchor its actual right edge.
    Paint.text(self,self.ValueText,p+V2(s.X,2),value,RGB(210,215,230),12,35,math.max(24,s.X*.45))
    local valueWidth=self.ValueText.Raw.TextBounds.X
    Paint.set(self.ValueText,{Position=pixel(p+V2(s.X-valueWidth,2))})
    Paint.text(self,self.Title,p+V2(0,2),self.Name,theme.Text,14,34,math.max(0,s.X-valueWidth-12))
    Paint.box(self,self.Track,self.TrackPosition,V2(self.TrackWidth,4),theme.Border,32)
    Paint.box(self,self.Fill,self.TrackPosition,V2(self.TrackWidth*self.Fraction,4),theme.Accent:Lerp(theme.AccentHover,self.Hover),33)
    local thumb=self.TrackPosition+V2(self.TrackWidth*self.Fraction,2)
    -- A nonzero slider value represents an active fill. Zero-value sliders have
    -- no halo unless actively captured by the pointer.
    if self.Value>self.Min or (Manager.Capture and Manager.Capture.Owner==self) then
        self.ThumbGlow:DrawGlow(thumb-V2(6,6),V2(12,12),theme.AccentGlow,7,3)
    end
    Paint.circle(self,self.Thumb,thumb,6,theme.Header,35)
    hit(self,p,s,36,"slider")
end

function Card:AddDropdown(config)
    return createControl(self,config,Dropdown,"Dropdown",34,function(c,o)
        assert(type(o.Options)=="table" and #o.Options>0,"Dropdown requires non-empty Options")
        c.Options = {}
        local seen = {}
        for _,value in ipairs(o.Options) do
            assert(type(value)=="string" and not seen[value],"Options must be unique strings")
            seen[value]=true; table.insert(c.Options,value)
        end
        c.Scroll = 0
        c.Field = Paint.make(c,"Square"); c.FieldEdge = Paint.make(c,"Square",{Filled=false})
        c.ValueText = Paint.make(c,"Text"); c.ArrowA = Paint.make(c,"Line"); c.ArrowB = Paint.make(c,"Line")
        c.PopupBg = Paint.make(c,"Square"); c.PopupEdge = Paint.make(c,"Square",{Filled=false})
        c.Rows = {}; c.PopupBar = Paint.make(c,"Square")
        for i=1,6 do
            c.Rows[i]={Bg=Paint.make(c,"Square"),Text=Paint.make(c,"Text")}
        end
        c:Set(o.Default or c.Options[1],true)
    end)
end
function Dropdown:Set(value,silent)
    assertLive(self)
    local exists = false
    for _,option in ipairs(self.Options) do if option==value then exists=true; break end end
    assert(exists,"Dropdown value is not in Options")
    if self.Value==value then return end
    self.Value=value; if not silent then self:StateChanged() end; if not silent then self:Emit("Callback",value) end
end
function Dropdown:Close() if self.Window.Popup==self then self.Window.Popup=nil end end
function Dropdown:Press(action,data)
    if action=="option" then self:Set(self.Options[data]); self:Close()
    elseif action=="open" then
        self.Window.Listening=nil
        self.Window.Popup = self.Window.Popup~=self and self or nil
        self.Scroll=0
        for i,option in ipairs(self.Options) do
            if option==self.Value then self.Scroll=math.max(0,i-3); break end
        end
    end
end
function Dropdown:ScrollBy(amount)
    self.Scroll = Math.clamp(self.Scroll+amount,0,math.max(0,#self.Options-(self.VisibleRows or 6)))
end
function Dropdown:Render(p,s,dt)
    local theme=self:Base(p,s,dt)
    local labelWidth=math.min(64,math.floor(s.X*0.4))
    Paint.text(self,self.Title,p+V2(0,10),self.Name,theme.Text,14,34,labelWidth-4)
    self.FieldPosition,self.FieldSize=p+V2(labelWidth,5),V2(s.X-labelWidth,24)
    Paint.box(self,self.Field,self.FieldPosition,self.FieldSize,theme.Background,32)
    Paint.box(self,self.FieldEdge,self.FieldPosition,self.FieldSize,theme.Border,33)
    Paint.text(self,self.ValueText,self.FieldPosition+V2(8,6),self.Value,theme.Muted,13,35,self.FieldSize.X-30)
    local a=self.FieldPosition+V2(self.FieldSize.X-18,10)
    Paint.line(self,self.ArrowA,a,a+V2(4,4),theme.Muted,35)
    Paint.line(self,self.ArrowB,a+V2(4,4),a+V2(8,0),theme.Muted,35)
    hit(self,self.FieldPosition,self.FieldSize,36,"open")
end
function Dropdown:RenderPopup()
    if self.Destroyed or not self.Onscreen then self:Close(); return end
    local theme=self.Window.Theme
    local viewport=workspace.CurrentCamera.ViewportSize
    local window=self.Window
    local lower=math.min(viewport.Y-4,window.Position.Y+window.Size.Y-4)
    local upper=math.max(4,window.Position.Y+Metrics.Header+2)
    local below=lower-(self.FieldPosition.Y+self.FieldSize.Y+4)
    local above=self.FieldPosition.Y-4-upper
    local openBelow=below>=above
    local available=math.max(0,openBelow and below or above)
    local count=math.min(6,#self.Options,math.floor(available/24))
    if count<1 then self:Close(); return end
    self.VisibleRows=count
    self.Scroll=Math.clamp(math.floor(self.Scroll),0,#self.Options-count)
    local height=count*24
    local p=pixel(V2(self.FieldPosition.X,openBelow and self.FieldPosition.Y+self.FieldSize.Y+4 or self.FieldPosition.Y-height-4))
    local width=self.FieldSize.X
    Paint.box(self,self.PopupBg,p,V2(width,height),theme.Background,900)
    Paint.box(self,self.PopupEdge,p,V2(width,height),theme.Border,901)
    hit(self,p,V2(width,height),902,"block")
    for i=1,count do
        local row=self.Rows[i]
        local rp=p+V2(1,(i-1)*24+1)
        local index=i+self.Scroll
        local option=self.Options[index]
        local selected=option==self.Value
        local hovered=Math.isHovered(Manager:Mouse(window),rp,V2(width-2,22))
        Paint.box(self,row.Bg,rp,V2(width-2,22),hovered and theme.Raised or theme.Background,903)
        Paint.text(self,row.Text,rp+V2(5,4),option,selected and theme.Accent or theme.Text,14,904,width-14)
        hit(self,rp,V2(width-2,22),905,"option",index)
    end
    if #self.Options>count then
        local length=height*count/#self.Options
        Paint.box(self,self.PopupBar,p+V2(width-3,(height-length)*self.Scroll/(#self.Options-count)),V2(2,length),theme.Accent,906)
    end
end

function Card:AddKeybind(config)
    return createControl(self,config,Keybind,"Keybind",34,function(c,o)
        assert(o.OnChanged==nil or type(o.OnChanged)=="function","OnChanged must be a function")
        c.OnChanged=o.OnChanged
        c.Keycap=Paint.make(c,"Square")
        c.KeyEdge=Paint.make(c,"Square",{Filled=false,Thickness=1})
        c.KeyText=Paint.make(c,"Text"); Paint.set(c.KeyText,{Center=true})
        c.PulseTime=0
        c:Set(o.Default,true)
    end)
end
function Keybind:Set(value,silent)
    assertLive(self); assert(value==nil or validKey(value),"Keybind needs Enum.KeyCode or nil")
    if self.Value==value then return end
    self.Value=value; if not silent then self:StateChanged() end; if not silent then self:Emit("OnChanged",value) end
end
function Keybind:Press()
    self.Window.Popup=nil
    self.Window.Listening = self.Window.Listening~=self and self or nil
end
function Keybind:Render(p,s,dt)
    local theme=self:Base(p,s,dt)
    local listening=self.Window.Listening==self
    self.PulseTime=self.PulseTime+math.max(0,dt)
    local text=listening and "..." or keyName(self.Value)
    Paint.set(self.KeyText,{Text=text,Size=12})
    local width=math.ceil(math.max(42,self.KeyText.Raw.TextBounds.X+16))
    local capP,capS=p+V2(s.X-width,(s.Y-22)/2),V2(width,22)
    self.KeycapPosition,self.KeycapSize=capP,capS
    local pulse=listening and (.35+.15*math.sin(self.PulseTime*5)) or 0
    Paint.box(self,self.Keycap,capP,capS,RGB(32,35,48):Lerp(Theme.Accent,pulse),32)
    Paint.box(self,self.KeyEdge,capP,capS,RGB(52,58,78):Lerp(Theme.Accent,pulse),33)
    Paint.text(self,self.Title,p+V2(0,10),self.Name,theme.Text,14,34,s.X-width-10)
    Paint.centerText(self,self.KeyText,capP,capS,text,RGB(240,242,250),12,35,8)
    hit(self,p,s,36,"listen")
end

function Card:AddButton(config)
    return createControl(self,config,Button,"Button",34,function(c)
        c.Flash,c.Depression=0,0
        c.Face=Paint.make(c,"Square")
        c.Edge=Paint.make(c,"Square",{Filled=false,Thickness=1})
        Paint.set(c.Title,{Center=true})
    end)
end
function Button:Press()
    self.Flash=1; Manager.Capture={Owner=self,Kind="Button"}
end
function Button:Release(mouse)
    if self.Onscreen and Math.isHovered(mouse,self.Position,self.Size) then self:Emit("Callback") end
end
function Button:Render(p,s,dt)
    self:Base(p,s,dt)
    local down=Manager.Capture and Manager.Capture.Owner==self
    self.Depression=Math.damp(self.Depression,down and 1 or 0,30,dt)
    self.Flash=Math.damp(self.Flash,0,8,dt)
    local face=p+V2(0,(s.Y-30)/2+self.Depression)
    local size=V2(s.X,30-self.Depression)
    local color=RGB(28,31,42):Lerp(RGB(38,42,58),self.Hover):Lerp(Theme.Accent,self.Flash*.25)
    Paint.box(self,self.Face,face,size,color,32)
    Paint.box(self,self.Edge,face,size,RGB(42,47,64),33)
    Paint.centerText(self,self.Title,face,size,self.Name,RGB(230,235,245),13,35,8)
    hit(self,p,s,36,"button")
end

-- Small telemetry/hero copy primitive. Set(text) updates without allocating.
function Card:AddLabel(config)
    return createControl(self,config,Label,"Label",config and config.Height or 34,function(c,o)
        assert(finite(c.Height) and c.Height>=20,"Label Height must be >=20")
        c.Value=tostring(o.Text or o.Name or "")
        c.Accent=o.Accent==true; c.TextSize=o.Size or 13
        assert(c.TextSize==13 or c.TextSize==14,"Label Size must be 13 or 14")
    end)
end
function Label:Set(text) assertLive(self); self.Value=tostring(text) end
function Label:Press() end
function Label:Render(p,s,dt)
    local theme=self:Base(p,s,dt)
    Paint.text(self,self.Title,p+V2(0,4),self.Value,self.Accent and theme.Accent or theme.Muted,self.TextSize,34,s.X)
end

-- Modal is retained and participates in the same input/Z stack as the window.
function Window:RenderModal()
    local p,s,t=self.RenderPosition,self.Size,self.Theme
    local d=self.ModalDraw
    local box=p+(s-V2(280,130))/2
    Paint.set(d.Dim,{Transparency=.55})
    Paint.box(self,d.Dim,p,s,RGB(0,0,0),1200)
    Paint.box(self,d.Box,box,V2(280,130),t.Surface,1201)
    Paint.box(self,d.Edge,box,V2(280,130),t.Accent,1202)
    Paint.text(self,d.Title,box+V2(16,14),"Unload Vesna?",t.Header,16,1203,248)
    -- Two lines keep the full requested message legible at this dialog width.
    Paint.text(self,d.Sub1,box+V2(16,42),"This will terminate all hooks",t.Muted,13,1203,248)
    Paint.text(self,d.Sub2,box+V2(16,58),"and remove all UI elements.",t.Muted,13,1203,248)
    hit(self,p,s,1202,"block")
    for _,item in ipairs({{"Cancel",16,"cancel-modal"},{"Unload",146,"unload-modal"}}) do
        local bp=box+V2(item[2],88)
        local hovered=Math.isHovered(Manager:Mouse(self),bp,V2(118,28))
        Paint.box(self,d[item[1]],bp,V2(118,28),item[1]=="Unload" and t.Accent or (hovered and t.Border or t.Raised),1204)
        Paint.text(self,d[item[1].."Text"],bp+V2(12,6),item[1],t.Header,13,1205,94)
        hit(self,bp,V2(118,28),1206,item[3])
    end
end

-- Retained UTF-8 editor. Prefix measurements are cached until the value changes;
-- caret/selection/repeat use the existing render and input connections.
local Input=setmetatable({}, {__index=Control}); Input.__index=Input
function Card:AddInput(config)
    return createControl(self,config,Input,"Input",34,function(c,o)
        c.Value=tostring(o.Default or ""); c.MaxLength=o.MaxLength or 48
        assert(finite(c.MaxLength) and c.MaxLength>=1 and c.MaxLength%1==0,"Invalid MaxLength")
        assert(utf8.len(c.Value) and utf8.len(c.Value)<=c.MaxLength,"Invalid input default")
        c.Pattern=o.Pattern or "."; c.Caret=utf8.len(c.Value); c.Anchor=c.Caret; c.ViewStart=0; c.Blink=0
        c.Field=Paint.make(c,"Square"); c.Edge=Paint.make(c,"Square",{Filled=false})
        c.Selection=Paint.make(c,"Square",{Transparency=.35})
        c.CaretLine=Paint.make(c,"Line"); c.MeasureText=Paint.make(c,"Text")
        c.ValueText=Paint.make(c,"Text")
    end)
end
function Input:Layout()
    if self.LayoutValue==self.Value then return end
    self.Offsets={[0]=0}; self.WidthCache={}; self.Widths={[0]=0}; self.Length=0
    for byte in utf8.codes(self.Value) do
        local nextByte=utf8.offset(self.Value,2,byte) or #self.Value+1
        self.Length=self.Length+1; self.Offsets[self.Length]=nextByte-1
        self.Widths[self.Length]=self:Measure(self.Value:sub(1,nextByte-1))
    end
    self.LayoutValue=self.Value
    self.Caret=Math.clamp(self.Caret or self.Length,0,self.Length)
    self.Anchor=Math.clamp(self.Anchor or self.Caret,0,self.Length)
end
function Input:Measure(text)
    local width=self.WidthCache[text]
    if width~=nil then return width end
    Paint.set(self.MeasureText,{Text=text,Size=13})
    width=self.MeasureText.Raw.TextBounds.X; self.WidthCache[text]=width
    return width
end
function Input:Slice(first,last)
    return self.Value:sub(self.Offsets[first]+1,self.Offsets[last])
end
function Input:Set(value,silent)
    assertLive(self); local length=type(value)=="string" and utf8.len(value)
    assert(length and length<=self.MaxLength,"Input must be valid UTF-8 within MaxLength")
    if self.Value==value then return end
    self.Value=value; self.LayoutValue=nil; self.Caret=math.min(self.Caret or length,length)
    self.Anchor=self.Caret; self.Blink=0
    if not silent then self:StateChanged(); self:Emit("Callback",value) end
end
function Input:GetSelection()
    self:Layout(); return math.min(self.Caret,self.Anchor),math.max(self.Caret,self.Anchor)
end
function Input:Replace(text)
    self:Layout(); local lo,hi=self:GetSelection()
    local chars={}; local count=0; local room=self.MaxLength-(self.Length-(hi-lo))
    if not utf8.len(text) then return end
    for byte in utf8.codes(text) do
        local nextByte=utf8.offset(text,2,byte) or #text+1
        local char=text:sub(byte,nextByte-1)
        if not char:match("%c") and char:match(self.Pattern) and count<room then count=count+1; chars[count]=char end
    end
    if text~="" and count==0 then return end -- rejected paste must not delete selection
    self:Set(self:Slice(0,lo)..table.concat(chars)..self:Slice(hi,self.Length))
    self.Caret=lo+count; self.Anchor=self.Caret; self.Blink=0
end
function Input:Move(where,selecting)
    self:Layout(); self.Caret=Math.clamp(where,0,self.Length)
    if not selecting then self.Anchor=self.Caret end
    self.Blink=0
end
function Input:Word(direction)
    self:Layout(); local i=self.Caret
    if direction<0 then
        while i>0 and self:Slice(i-1,i):match("%s") do i=i-1 end
        while i>0 and not self:Slice(i-1,i):match("%s") do i=i-1 end
    else
        while i<self.Length and not self:Slice(i,i+1):match("%s") do i=i+1 end
        while i<self.Length and self:Slice(i,i+1):match("%s") do i=i+1 end
    end
    return i
end
function Input:Nearest(mouse)
    self:Layout(); local start=self.ViewStart or 0
    local x=mouse.X-(self.FieldPosition.X+7); local best=start; local distance=math.huge
    for i=start,self.ViewEnd or self.Length do
        local delta=math.abs(x-self:Measure(self:Slice(start,i)))
        if delta<distance then distance=delta; best=i end
    end
    return best
end
function Input:Press(_,_,mouse)
    if Manager:KeyboardBlocked() then return end
    local focused=self.Window.InputFocus==self
    if not focused then self.Window:CancelInteraction(); self.Before=self.Value end
    self.Window.InputFocus=self; self.Repeat=nil; self:Layout()
    local _,shift=Manager:Modifiers()
    self:Move(mouse and self.FieldPosition and self:Nearest(mouse) or self.Length,focused and shift)
    if mouse then Manager.Capture={Owner=self,Kind="TextSelect"} end
end
function Input:EditKey(key)
    self:Layout(); local name=key.Name; local ctrl,shift=Manager:Modifiers()
    local lo,hi=self:GetSelection()
    if name=="Backspace" or name=="Delete" then
        if lo==hi then
            if name=="Backspace" then self.Anchor=ctrl and self:Word(-1) or math.max(0,self.Caret-1)
            else self.Anchor=ctrl and self:Word(1) or math.min(self.Length,self.Caret+1) end
        end
        self:Replace(""); return true
    elseif name=="Left" or name=="Right" then
        local direction=name=="Left" and -1 or 1
        local target=ctrl and self:Word(direction) or self.Caret+direction
        if not shift and lo~=hi and not ctrl then target=direction<0 and lo or hi end
        self:Move(target,shift); return true
    elseif name=="Home" or name=="End" then self:Move(name=="Home" and 0 or self.Length,shift); return false end
    if ctrl then return false end
    local char=UIS:GetStringForKeyCode(key)
    if char==" " or name=="Space" then char=" " end
    if utf8.len(char)==1 then
        if shift then char=char=="-" and "_" or char:upper() else char=char:lower() end
        if not char:match("%c") and char:match(self.Pattern) then self:Replace(char); return true end
    end
    return false
end
function Input:HandleKey(key)
    self.Repeat=nil; local name=key.Name; local ctrl=Manager:Modifiers()
    if name=="Escape" then self:Set(self.Before or self.Value); self.Window.InputFocus=nil; return end
    if name=="Return" or name=="KeypadEnter" then self.Window.InputFocus=nil; return end
    if ctrl and name=="A" then self:Layout(); self.Anchor=0; self.Caret=self.Length; self.Blink=0; return end
    if ctrl and (name=="C" or name=="X" or name=="V") then
        local env=type(getgenv)=="function" and getgenv() or _G
        local lo,hi=self:GetSelection()
        if name=="V" then
            local reader=env.getclipboard or _G.getclipboard
            if type(reader)=="function" then local ok,text=pcall(reader); if ok and type(text)=="string" then self:Replace(text) end end
        elseif hi>lo then
            local writer=env.setclipboard or _G.setclipboard
            if type(writer)=="function" then
                local ok=pcall(writer,self:Slice(lo,hi)); if ok and name=="X" then self:Replace("") end
            end
        end
        return
    end
    if self:EditKey(key) then self.Repeat={Key=key,Remaining=.4} end
end
function Input:Tick(dt)
    if self.Destroyed or self.Window.InputFocus~=self then self.Repeat=nil; return end
    self.Blink=(self.Blink+math.max(0,dt))%1
    if not self.Repeat then return end
    self.Repeat.Remaining=self.Repeat.Remaining-math.max(0,dt)
    for _=1,8 do
        if not self.Repeat or self.Repeat.Remaining>0 then break end
        self:EditKey(self.Repeat.Key); self.Repeat.Remaining=self.Repeat.Remaining+.045
    end
end
function Input:Render(p,s,dt)
    local t=self:Base(p,s,dt); self:Layout()
    Paint.text(self,self.Title,p+V2(0,10),self.Name,t.Text,14,34,61)
    local fp,fs=p+V2(65,5),V2(s.X-65,24); self.FieldPosition,self.FieldSize=fp,fs
    local focused=self.Window.InputFocus==self; local available=math.max(0,fs.X-14)
    local captured=Manager.Capture and Manager.Capture.Owner==self and Manager.Capture.Kind=="TextSelect"
    if captured then self:Move(self:Nearest(Manager:Mouse(self.Window)),true) end
    self.ViewStart=math.min(self.ViewStart or 0,focused and self.Caret or 0)
    while focused and self.ViewStart<self.Caret and self:Measure(self:Slice(self.ViewStart,self.Caret))>available do self.ViewStart=self.ViewStart+1 end
    local last=self.ViewStart
    while last<self.Length and self:Measure(self:Slice(self.ViewStart,last+1))<=available do last=last+1 end
    self.ViewEnd=last
    Paint.box(self,self.Field,fp,fs,t.Background,32)
    Paint.box(self,self.Edge,fp,fs,focused and t.Accent or t.Border,33)
    local lo,hi=self:GetSelection(); local start=self.ViewStart
    if focused and hi>lo then
        local a=Math.clamp(lo,start,last); local b=Math.clamp(hi,start,last)
        if b>a then Paint.box(self,self.Selection,fp+V2(7+self:Measure(self:Slice(start,a)),3),V2(self:Measure(self:Slice(start,b))-self:Measure(self:Slice(start,a)),18),t.Accent,34) end
    end
    Paint.text(self,self.ValueText,fp+V2(7,6),self:Slice(start,last),t.Text,13,35)
    if focused and self.Blink<.55 then
        local x=fp.X+7+self:Measure(self:Slice(start,Math.clamp(self.Caret,start,last)))
        Paint.line(self,self.CaretLine,V2(x,fp.Y+5),V2(x,fp.Y+19),t.Text,36)
    end
    hit(self,fp,fs,37,"input")
end

local Status=setmetatable({}, {__index=Control}); Status.__index=Status
function Card:AddStatusItem(id,label,initialValue,initialColor)
    self.StatusItems=self.StatusItems or {}
    assert(type(id)=="string" and not self.StatusItems[id],"Status id must be unique in the card")
    local c=createControl(self,{Name=label,Persist=false},Status,"Status",34,function(c)
        c.Value=tostring(initialValue or ""); c.Color=initialColor or self.Window.Theme.Muted
        assert(typeof(c.Color)=="Color3","Status color must be Color3")
        c.ValueText=Paint.make(c,"Text")
    end)
    c.StatusId=id; self.StatusItems[id]=c
    return c
end
function Status:SetText(text) assertLive(self); self.Value=tostring(text) end
function Status:SetColor(color) assertLive(self); assert(typeof(color)=="Color3","Color must be Color3"); self.Color=color end
function Status:Set(text) self:SetText(text) end
function Status:Press() end
function Status:Render(p,s,dt)
    local t=self:Base(p,s,dt)
    Paint.text(self,self.Title,p+V2(0,10),self.Name,t.Text,14,34,s.X*.45)
    Paint.text(self,self.ValueText,p+V2(s.X*.48,11),self.Value,self.Color,13,35,s.X*.52)
end

-- Executor-local persistence. All filesystem failures return false,error.
-- Only this window's registered primitive state is serialized.
local Config={}; Config.__index=Config
function Window:CreateConfigManager()
    if self.Config then return self.Config end
    local environment=type(getgenv)=="function" and getgenv() or _G
    local api={}
    for _,name in ipairs({"isfolder","makefolder","writefile","readfile","listfiles","delfile","isfile"}) do api[name]=environment[name] or _G[name] end
    local c=setmetatable({Window=self,Controls={},AutoSave=false,Pending=nil,Loading=false,Files=api,
        Directory="VesnaConfigs/"..tostring(game.GameId or 0).."/",LastError=nil},Config)
    for _,name in ipairs({"isfolder","makefolder","writefile","readfile","listfiles"}) do
        if type(api[name])~="function" then c.Unavailable="Missing executor function: "..name; break end
    end
    self.Config=c; return c
end
function Config:Guard(fn)
    if self.Window.Destroyed then return false,"Window destroyed" end
    if self.Unavailable then self.LastError=self.Unavailable; return false,self.Unavailable end
    local ok,result=pcall(fn)
    self.LastError=not ok and tostring(result) or nil
    return ok,result
end
function Config:Path(name)
    assert(type(name)=="string" and #name>0 and #name<=48 and name:match("^[A-Za-z0-9_%- ]+$"),"Use 1ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“48 letters, numbers, spaces, _ or -")
    return self.Directory..name..".json"
end
function Config:EnsureDirectory()
    if not self.Files.isfolder("VesnaConfigs") then self.Files.makefolder("VesnaConfigs") end
    if not self.Files.isfolder(self.Directory) then self.Files.makefolder(self.Directory) end
end
function Config:Register(control)
    if not control.Persist or not ({Toggle=true,Slider=true,Dropdown=true,Keybind=true,Input=true})[control.Kind] then return end
    local id=control.ConfigId or (control.Card.Parent.Name.."/"..control.Card.Name.."/"..control.Name)
    assert(type(id)=="string" and not self.Controls[id],"Duplicate config id: "..tostring(id).."; provide Id")
    control.ConfigId=id; self.Controls[id]=control
end
function Control:StateChanged()
    local c=self.Window.Config
    if c and not c.Loading and c.AutoSave and self.Persist and self.ConfigId then c.Pending=.5 end
end
function Config:SetAutoSave(enabled)
    assert(type(enabled)=="boolean","Auto save must be boolean")
    self.AutoSave=enabled; self.Pending=enabled and .5 or nil
    if self.AutoToggle and not self.AutoToggle.Destroyed then self.AutoToggle:Set(enabled,true) end
end
function Config:Tick(dt)
    if not self.Pending or self.Loading then return end
    self.Pending=self.Pending-math.max(0,dt)
    if self.Pending<=0 then
        self.Pending=nil
        local ok,err=self:Save("default")
        if not ok then warn("Vesna auto-save: "..tostring(err)) end
    end
end
function Config:Save(name)
    return self:Guard(function()
        local path=self:Path(name); local state={Version=1,GameId=tostring(game.GameId or 0),AutoSave=self.AutoSave,Values={}}
        for id,c in pairs(self.Controls) do
            if not c.Destroyed then state.Values[id]={Kind=c.Kind,Value=c.Kind=="Keybind" and (c.Value and c.Value.Name or "NONE") or c.Value} end
        end
        local raw=HttpService:JSONEncode(state)
        self:EnsureDirectory(); self.Files.writefile(path,raw)
        return path
    end)
end
function Config:List()
    return self:Guard(function()
        self:EnsureDirectory(); local names,seen={},{}
        for _,path in ipairs(self.Files.listfiles(self.Directory)) do
            local name=tostring(path):gsub("\\","/"):match("([^/]+)%.json$")
            if name and name:match("^[A-Za-z0-9_%- ]+$") and #name<=48 and not seen[name] then seen[name]=true; table.insert(names,name) end
        end
        table.sort(names); return names
    end)
end
function Config:Load(name)
    return self:Guard(function()
        local decoded=HttpService:JSONDecode(self.Files.readfile(self:Path(name)))
        assert(type(decoded)=="table" and decoded.Version==1 and type(decoded.Values)=="table" and decoded.GameId==tostring(game.GameId or 0),"Invalid config schema/game")
        assert(type(decoded.AutoSave)=="boolean","Invalid auto-save setting")
        local pending={}
        -- Validate the entire payload before mutating controls.
        for id,entry in pairs(decoded.Values) do
            local c=self.Controls[id]
            if c and not c.Destroyed then
                assert(type(entry)=="table" and entry.Kind==c.Kind,"Config kind mismatch: "..id)
                local v=entry.Value
                if c.Kind=="Toggle" then assert(type(v)=="boolean","Invalid toggle")
                elseif c.Kind=="Slider" then assert(finite(v) and v>=c.Min and v<=c.Max,"Invalid slider")
                elseif c.Kind=="Dropdown" then local found=false; for _,option in ipairs(c.Options) do if option==v then found=true end end; assert(found,"Invalid option")
                elseif c.Kind=="Input" then assert(type(v)=="string" and utf8.len(v) and utf8.len(v)<=c.MaxLength,"Invalid input")
                elseif c.Kind=="Keybind" then
                    assert(type(v)=="string","Invalid key")
                    if v=="NONE" then v=nil else v=Enum.KeyCode[v]; assert(validKey(v),"Invalid key") end
                end
                table.insert(pending,{Control=c,Value=v})
            end
        end
        self.Loading=true
        local ok,err=pcall(function() for _,item in ipairs(pending) do item.Control:Set(item.Value) end end)
        self.Loading=false; assert(ok,err)
        self.AutoSave=decoded.AutoSave; self.Pending=nil
        if self.AutoToggle and not self.AutoToggle.Destroyed then self.AutoToggle:Set(self.AutoSave,true) end
        return #pending
    end)
end
function Config:Delete(name)
    return self:Guard(function()
        assert(type(self.Files.delfile)=="function","Executor delfile is unavailable")
        self.Files.delfile(self:Path(name)); return true
    end)
end
function Dropdown:SetOptions(options)
    assertLive(self); assert(type(options)=="table" and #options>0,"Options must be nonempty")
    local seen,copy={},{}
    for _,v in ipairs(options) do assert(type(v)=="string" and not seen[v],"Options must be unique strings"); seen[v]=true; table.insert(copy,v) end
    -- Six retained rows support arbitrary option counts without redraw allocations.
    self.Options=copy; self.Scroll=0; self:Close()
    if not seen[self.Value] then self:Set(copy[1],true) end
end
function Window:CreateConfigTab()
    local config=self.Config
    local tab=self:CreateTab("Configs","=")
    local tools=tab:CreateCard({Name="CONFIG MANAGER",Description="Executor-local JSON profiles",ColumnSpan=6,RowSpan=6})
    local function report(ok,result)
        config.LastResult=ok and result or nil
        if not ok then warn("Vesna config: "..tostring(result)) end
    end
    config.AutoToggle=tools:AddToggle({Name="Auto Save Config",Persist=false,Callback=function(v) config:SetAutoSave(v) end})
    local choices=tools:AddDropdown({Name="Files",Options={"(none)"},Persist=false})
    local input=tools:AddInput({Name="Name",Default="default",Persist=false,Pattern="[A-Za-z0-9_%- ]"})
    local function refresh(quiet)
        local ok,names=config:List()
        if ok then choices:SetOptions(#names>0 and names or {"(none)"})
        elseif quiet then config.LastError=tostring(names)
        else report(ok,names) end
    end
    tools:AddButton({Name="Save Config",Callback=function() report(config:Save(input:Get())); refresh() end})
    tools:AddButton({Name="Load Config",Callback=function() report(config:Load(choices:Get())) end})
    tools:AddButton({Name="Delete Config",Callback=function() report(config:Delete(choices:Get())); refresh() end})
    tools:AddButton({Name="Refresh Files",Callback=refresh})
    config.UI={Choices=choices,Input=input,Refresh=refresh}
    refresh(true); return tab
end


-- ============================================================================
-- 3. Illustrative usage: original six-column Bento composition
-- ============================================================================
-- All sample callbacks are local UI settings/diagnostics. The final block below
-- calls this example directly, so pasting the complete script opens the UI.
function Library:Demo()
    local window=self:CreateWindow({Title="VESNA",Font=0})
    local home=window:CreateTab("Overview","+")
    local profiles=window:CreateTab("Profiles","=")
    local settings={Enabled=true,Quality=75,Scale=1,Profile="Balanced"}
    local hero=home:CreateCard({Name="SESSION",Description="Your local workspace",
        Column=1,ColumnSpan=3,Row=1,RowSpan=3})
    hero:AddToggle({Id="workspace.enabled",Name="Workspace enabled",Default=true,Callback=function(v) settings.Enabled=v end})
    hero:AddToggle({Name="Bright accents",Default=false,Callback=function(v)
        window:SetAccent(v and RGB(255,90,120) or RGB(244,63,94))
    end})
    hero:AddButton({Name="Print snapshot",Callback=function()
        print("Vesna session:",settings.Enabled,settings.Quality,settings.Scale,settings.Profile)
    end})
    local telemetry=home:CreateCard({Name="LIVE STATUS",Description="Local diagnostics",
        Column=4,ColumnSpan=3,Row=1,RowSpan=3})
    window.Status={}
    window.Status.Session=telemetry:AddStatusItem("session","Session","ONLINE",Theme.Accent)
    window.Status.Ping=telemetry:AddStatusItem("ping","Ping","Loading...",Theme.Muted)
    telemetry:AddKeybind({Name="Print diagnostic",Default=Enum.KeyCode.F6,Callback=function(key)
        print("Diagnostic",key.Name,"FPS",window.FPS)
    end})
    local tuning=home:CreateCard({Name="FINE TUNING",Description="Smooth fills. Exact values.",
        Column=1,ColumnSpan=3,Row=4,RowSpan=3})
    tuning:AddSlider({Name="Render quality",Min=0,Max=100,Default=75,Suffix="%",Callback=function(v) settings.Quality=v end})
    tuning:AddSlider({Name="Scale preset",Min=0.5,Max=2,Decimals=2,Default=1,Suffix="x",Callback=function(v) settings.Scale=v end})
    tuning:AddLabel({Text="Precision, without clutter.",Size=13})
    local routes=home:CreateCard({Name="PROFILE",Description="Choose a preset",
        Column=4,ColumnSpan=3,Row=4,RowSpan=3})
    local profile=routes:AddDropdown({Name="Preset",Options={"Balanced","Quiet","High contrast","Presentation","Custom"},
        Default="Balanced",Callback=function(v) settings.Profile=v end})
    routes:AddButton({Name="Reset profile",Callback=function() profile:Set("Balanced") end})
    routes:AddKeybind({Name="Quick reset",Default=Enum.KeyCode.F7,Callback=function() profile:Set("Balanced") end})
    local help=profiles:CreateCard({Name="KEYBOARD",Description="Intentional, minimal shortcuts",Column=1,ColumnSpan=6,RowSpan=3})
    help:AddLabel({Text="RIGHT CTRL  /  Show or hide the workspace"})
    help:AddLabel({Text="ESC  /  Cancel capture or close the dropdown"})
    help:AddLabel({Text="BACKSPACE  /  Clear a key while listening"})
    help:AddButton({Name="Unload interface",Callback=function() window:Press("close") end})
    window:CreateConfigTab()
    local config=window.Config
    if not config.Unavailable and type(config.Files.isfile)=="function" then
        local ok,exists=pcall(config.Files.isfile,config.Directory.."default.json")
        if ok and exists then local loaded,err=config:Load("default"); if not loaded then warn("Vesna config: "..tostring(err)) end end
    end
    return window,settings
end

-- Run the example at the end of this standalone script. Re-execution unloads
-- the previous copy first, preventing stacked windows and event connections.
local environment = type(getgenv) == "function" and getgenv() or _G
local legacy = environment.ObsidianUI
if type(legacy)=="table" and type(legacy.Unload)=="function" then legacy:Unload() end
environment.ObsidianUI=nil
local previous = environment.VesnaUI
if type(previous) == "table" and type(previous.Unload) == "function" then
    previous:Unload()
end
Library.DemoWindow, Library.DemoSettings = Library:Demo()
environment.VesnaUI = Library
-- From your host console: getgenv().VesnaUI:Unload()
return Library
