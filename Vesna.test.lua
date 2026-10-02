-- Behavioral test host: exercises the production source without editing it.
local passed = 0
local function check(condition, message)
    assert(condition, message); passed = passed+1
end

local vector = {}; vector.__index=vector
function vector.__add(a,b) return Vector2.new(a.X+b.X,a.Y+b.Y) end
function vector.__sub(a,b) return Vector2.new(a.X-b.X,a.Y-b.Y) end
function vector.__mul(a,b)
    if type(a)=="number" then a,b=b,a end
    return Vector2.new(a.X*b,a.Y*b)
end
function vector.__div(a,b) return Vector2.new(a.X/b,a.Y/b) end
function vector.__eq(a,b) return a.X==b.X and a.Y==b.Y end
Vector2={new=function(x,y) return setmetatable({X=x,Y=y,__type="Vector2"},vector) end}
local color={}; color.__index=color
Color3={fromRGB=function(r,g,b) return setmetatable({R=r/255,G=g/255,B=b/255,__type="Color3"},color) end}
function color:Lerp(b,t) return Color3.fromRGB((self.R+(b.R-self.R)*t)*255,(self.G+(b.G-self.G)*t)*255,(self.B+(b.B-self.B)*t)*255) end
function typeof(v) return type(v)=="table" and v.__type or type(v) end
Enum={KeyCode={},UserInputType={}}
for _,name in ipairs({"Unknown","Insert","F6","F7","F8","Escape","Backspace","Space","LeftShift","RightShift","LeftControl","RightControl","A","B","C","V","X","Delete","Left","Right","Home","End","Return","Minus"}) do
    Enum.KeyCode[name]={Name=name,EnumType=Enum.KeyCode,__type="EnumItem"}
end
for _,name in ipairs({"Keyboard","MouseButton1","MouseMovement","MouseWheel"}) do
    Enum.UserInputType[name]={Name=name,EnumType=Enum.UserInputType,__type="EnumItem"}
end

local deferred={}
local jsonBlobs,jsonSerial={},0
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
task={defer=function(fn) table.insert(deferred,fn) end}
local warnings={}
warn=function(message) table.insert(warnings,message) end
local function flush()
    while #deferred>0 do local q=deferred; deferred={}; for _,fn in ipairs(q) do fn() end end
end
local liveConnections=0
local function signal()
    local s={items={}}
    function s:Connect(fn)
        local c={Connected=true,fn=fn}; liveConnections=liveConnections+1
        function c:Disconnect()
            if self.Connected then self.Connected=false; liveConnections=liveConnections-1 end
        end
        table.insert(self.items,c); return c
    end
    function s:Fire(...)
        for _,c in ipairs(self.items) do if c.Connected then c.fn(...) end end
    end
    return s
end
local mouse=Vector2.new(0,0)
local focused=nil
local held={}
local clipboard=""
setclipboard=function(text) clipboard=text end
getclipboard=function() return clipboard end
local UIS={InputBegan=signal(),InputChanged=signal(),InputEnded=signal(),WindowFocusReleased=signal()}
function UIS:GetMouseLocation() return mouse end
function UIS:GetFocusedTextBox() return focused end
function UIS:IsKeyDown(key) return held[key]==true end
function UIS:GetStringForKeyCode(key) return #key.Name==1 and key.Name or (key.Name=="Space" and " " or key.Name=="Minus" and "-" or "") end
local RS={RenderStepped=signal()}
local testPlayer={Name="TestUser",DisplayName="Test Player With A Long Display Name",UserId=12345}
local Players={LocalPlayer=testPlayer}
local imageSupported=false
local httpMode="success"
local httpRequests=0
local httpHook=nil
local png="\137PNG\r\n\26\nmock-thumbnail"
game={GetService=function(_,name)
    return ({UserInputService=UIS,RunService=RS,Players=Players,HttpService={JSONEncode=function(_,value)
        jsonSerial=jsonSerial+1; local key="mock-json-"..jsonSerial; jsonBlobs[key]=copy(value); return key
    end,JSONDecode=function(_,response)
        if jsonBlobs[response] then return copy(jsonBlobs[response]) end
        if response=="metadata" then return {data={{state="Completed",imageUrl="https://cdn.mock/avatar.png"}}} end
        error("Invalid thumbnail JSON")
    end}})[name]
end}
function game:HttpGet(url)
    httpRequests=httpRequests+1
    assert(url=="https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=12345&size=150x150&format=Png&isCircular=true" or url=="https://cdn.mock/avatar.png","Two-stage avatar request")
    if httpHook then httpHook() end
    if httpMode=="error" then error("Mock HTTP failure") end
    if url=="https://cdn.mock/avatar.png" then return httpMode=="html" and "<html>Error</html>" or png end
    return "metadata"
end
workspace={CurrentCamera={ViewportSize=Vector2.new(1280,900)}}
local drawings,liveDrawings={},0
local failAt=nil
local failProperty=nil
local failKind=nil
local allocation=0
Drawing={new=function(kind)
    allocation=allocation+1
    if allocation==failAt then error("Injected allocation failure") end
    assert(kind=="Square" or kind=="Text" or kind=="Circle" or kind=="Line" or kind=="Image","Forbidden Drawing primitive")
    if kind=="Image" and not imageSupported then error("Mock Image unavailable") end
    local data={Kind=kind,Removed=false}
    local raw=setmetatable({}, {
        __index=function(_,key)
            if key=="TextBounds" then return Vector2.new(utf8.len(data.Text or "")*(data.Size or 13)*0.57,data.Size or 13) end
            if key=="Remove" then return function()
                assert(not data.Removed,"Double removal"); data.Removed=true; liveDrawings=liveDrawings-1
            end end
            assert(not data.Removed,"Access after removal"); return data[key]
        end,
        __newindex=function(_,key,value)
            assert(not data.Removed,"Write after removal")
            if key==failProperty and (not failKind or data.Kind==failKind) then error("Injected unsupported property: "..key) end
            if key=="Size" and type(value)=="table" then assert(value.X>=0 and value.Y>=0,"Negative Drawing size") end
            data[key]=value
        end,
    })
    table.insert(drawings,data); liveDrawings=liveDrawings+1; return raw
end}

local library=assert(loadfile(arg[1] or "outputs/Vesna.luau"))()
local function frame(count,dt) for _=1,count or 1 do RS.RenderStepped:Fire(dt or 1/60) end end
local function input(kind,key,z) return {UserInputType=Enum.UserInputType[kind],KeyCode=key or Enum.KeyCode.Unknown,Position={Z=z or 0}} end
local function down(p,processed)
    mouse=p; UIS.InputBegan:Fire(input("MouseButton1"),processed or false)
end
local function up(p) mouse=p or mouse; UIS.InputEnded:Fire(input("MouseButton1"),false) end
local function click(p,processed) down(p,processed); up(); flush(); frame() end
local function key(k,processed) UIS.InputBegan:Fire(input("Keyboard",k),processed or false); flush(); frame() end
local function wheel(p,z) mouse=p; UIS.InputChanged:Fire(input("MouseWheel",nil,z),false); frame() end
local function center(c) return c.Position+c.Size/2 end
local function at(c,dx,dy) return c.Position+Vector2.new(dx,dy) end
local w,state=library.DemoWindow,library.DemoSettings; frame(60)
check(liveConnections==5,"Exactly five shared connections")
check(w.FPS==60,"FPS telemetry")
check(liveDrawings>0,"Drawing allocation")
-- The header emblem owns exactly 12 retained lines and no image/network loader.
check(w.Logo and #w.Logo.Drawings==12 and #w.Logo.Lines==12,"Twelve-line vector logo")
check(w.LogoTask==nil and library.LogoURL==nil,"No header asset-loading work")
local vertices={{8,0},{16,5},{16,15},{8,20},{0,15},{0,5},{8,5},{12,10},{8,15},{4,10}}
local edges={{1,2},{2,3},{3,4},{4,5},{5,6},{6,1},{7,8},{8,9},{9,10},{10,7},{1,7},{4,9}}
local function verifyLogo()
    for i,edge in ipairs(edges) do
        local line=w.Logo.Lines[i].Cache
        local a,b=vertices[edge[1]],vertices[edge[2]]
        check(line.From.X==w.RenderPosition.X+16+a[1] and line.From.Y==w.RenderPosition.Y+9+a[2],"Vector origin follows snapped window")
        check(line.To.X==w.RenderPosition.X+16+b[1] and line.To.Y==w.RenderPosition.Y+9+b[2],"Connected endpoint follows snapped window")
        check(line.Thickness==1 and line.Visible,"Visible single-pixel vector stroke")
        local inner=i>=7 and i<=10
        check(line.Transparency==(inner and .9 or 1),"Diamond alpha")
        local color=inner and Color3.fromRGB(255,255,255) or Color3.fromRGB(244,63,94)
        check(line.Color.R==color.R and line.Color.G==color.G and line.Color.B==color.B,"Exact vector palette")
    end
end
verifyLogo()
local originalPosition=w.Position
for i=1,30 do w.Target=Vector2.new(130+i*3.25,90+i*1.75);frame();verifyLogo() end
w.Position=originalPosition;w.Target=originalPosition;frame()
local oldLogo=w.Logo
local stableCount=liveDrawings
w:CreateLogo(); frame()
check(oldLogo.Destroyed and #oldLogo.Drawings==0 and liveDrawings==stableCount,"Logo replacement releases all twelve old lines")
verifyLogo()
local home=w.Tabs[1]
local hero,telemetry,tuning,routes=table.unpack(home.Cards)
local toggle,accent,button=table.unpack(hero.Controls)
local slider,scale=table.unpack(tuning.Controls)
local dropdown,reset,bind=table.unpack(routes.Controls)
local diagnostic=telemetry.Controls[3]
check(hero.ColumnSpan==3 and telemetry.ColumnSpan==3,"Compact Bento geometry")
check(w.Size.X==695 and w.Size.Y==452,"Exact 695x452 footprint")
for _,d in ipairs(drawings) do
    if d.Kind=="Text" then
        check(d.Font==0 and not d.Outline,"Hardcoded UI font, smooth text flags")
        check(d.OutlineColor.R==0 and d.OutlineColor.G==0 and d.OutlineColor.B==0,"Black text outlines")
        check(d.Size>=11 and d.Size<=16 and d.Size%1==0,"Readable integer typography")
        if d.Visible then check(d.Position.X%1==0 and d.Position.Y%1==0,"Pixel-snapped text") end
    end
end
check(toggle.Height==34 and slider.Height==34,"Spacious component rows")
check(w.Profile.AvatarStatus=="unsupported" and w.Profile.Fallback.Cache.Visible,"Unsupported Image fallback")
check(w.Profile.Display.Cache.Size==14 and w.Profile.Handle.Cache.Size==13,"Profile text sizes")
check(w.Profile.Size.X==138 and w.Profile.Size.Y==52,"138x52 profile card")
check(w.Profile.Display.Cache.Text~=testPlayer.DisplayName,"Display name truncation")
check(toggle.Track[1].Cache.Size.X==16 and toggle.Track[1].Cache.Size.Y==18 and toggle.Thumb.Cache.Radius==6,"34x18 capsule, 16px bridge and r6 thumb")
check(slider.Track.Cache.Size.Y==4 and slider.Thumb.Cache.Radius==6,"4px track and 12px thumb")
check(toggle.Track[2].Cache.Radius==9 and toggle.Track[3].Cache.Radius==9,"Integer radius-9 cap circles")
check(toggle.Track[3].Cache.Position.X-toggle.Track[2].Cache.Position.X==16,"Circle cap centers 16px apart")
check(bind.KeycapPosition.Y-bind.Position.Y==6 and bind.KeycapPosition.X+bind.KeycapSize.X==bind.Position.X+bind.Size.X,"Expanded keycap centered and flush right")
check(toggle.TrackGlow==nil and toggle.ThumbGlow==nil and #toggle.Drawings==6,"Toggle has only base/label/track/thumb drawings")
check(slider.Badge==nil and slider.ValueText.Cache.Size==12,"Slider pill removed; 12px plain value")
check(math.abs(slider.ValueText.Cache.Position.X+slider.ValueText.Raw.TextBounds.X-(slider.Position.X+slider.Size.X))<=.51,"Slider value right aligned")
check(bind.Badge==nil and bind.KeyText.Cache.Text=="F7" and bind.KeyText.Cache.Center,"Centered unbracketed keycap")
check(bind.KeycapSize.X==42 and bind.KeycapSize.Y==22,"Compact F7 keycap")
check(bind.KeyText.Cache.Size==12 and bind.KeyEdge.Cache.Filled==false,"12px text and keycap stroke")
check(button.Rule==nil and button.Edge.Cache.Filled==false,"Button has border, no accent strip")
check(button.Title.Cache.Center and button.Title.Cache.Size==13,"Button label centered at 13px")
check(button.Face.Cache.Size.Y==30,"30px tactile face")
check(toggle.ActiveEdge==nil,"Detached toggle frame removed")
check(hero.DescriptionText.Cache.Size==13 and hero.DescriptionText.Cache.Color.R==190/255,"Description size and contrast")
check(hero.DescriptionText.Cache.Position.Y-hero.Position.Y==35,"Expanded description spacing")
check(toggle.Title.Cache.Size==14 and toggle.Title.Cache.Color.R==245/255,"Primary labels size and contrast")
check(w.Telemetry.Cache.Size==13 and w.Telemetry.Cache.Color.R==1,"Bright telemetry")
w:SelectTab(w.Tabs[3]); frame()
local configCard=w.Tabs[3].Cards[1]
check(configCard.Size.X==325 and configCard.Position.X==w.RenderPosition.X+172,"Single card capped and left-docked")
for _,control in ipairs(configCard.Controls) do check(control.Onscreen,"Config controls fit after typography changes") end
check(w.Config.UI.Status==nil and #configCard.Controls==7,"Storage row removed")
-- Editing uses actual shared mock input signals and retained Drawing geometry.
local editor=w.Config.UI.Input
local function edit(k) UIS.InputBegan:Fire(input("Keyboard",k),false); UIS.InputEnded:Fire(input("Keyboard",k),false); flush(); frame() end
editor:Set("default",true); editor:Press(); held[Enum.KeyCode.LeftControl]=true
edit(Enum.KeyCode.A); check(editor.Anchor==0 and editor.Caret==7 and editor.Selection.Cache.Visible,"Ctrl+A visible selection")
held[Enum.KeyCode.LeftControl]=nil; edit(Enum.KeyCode.B); check(editor:Get()=="b","Typing replaces selection")
editor:Set("abcdef",true); editor:Move(0,false)
UIS.InputBegan:Fire(input("Keyboard",Enum.KeyCode.Delete),false); frame(18)
check(editor:Get()=="bcdef","Held Delete waits before repeat")
frame(30); check(editor:Get()=="","Held Delete repeats")
UIS.InputEnded:Fire(input("Keyboard",Enum.KeyCode.Delete),false)
editor:Set("abcdef",true); editor:Move(6,false)
UIS.InputBegan:Fire(input("Keyboard",Enum.KeyCode.Backspace),false); frame(50)
check(editor:Get()=="","Held Backspace repeats"); UIS.InputEnded:Fire(input("Keyboard",Enum.KeyCode.Backspace),false)
editor:Set("abcdef",true); editor:Move(3,false); edit(Enum.KeyCode.Delete); check(editor:Get()=="abcef","Delete removes character after caret")
edit(Enum.KeyCode.Backspace); check(editor:Get()=="abef","Backspace removes character before caret")
held[Enum.KeyCode.LeftControl]=true; edit(Enum.KeyCode.A); edit(Enum.KeyCode.C); check(clipboard=="abef","Ctrl+C copies selection")
edit(Enum.KeyCode.X); check(editor:Get()=="","Ctrl+X cuts selection")
clipboard="profile_test"; edit(Enum.KeyCode.V); check(editor:Get()=="profile_test","Ctrl+V pastes")
held[Enum.KeyCode.LeftControl]=nil; edit(Enum.KeyCode.Home); held[Enum.KeyCode.LeftShift]=true; edit(Enum.KeyCode.Right)
check(editor.Caret==1 and editor.Anchor==0,"Shift+Right selects")
held[Enum.KeyCode.LeftShift]=nil; edit(Enum.KeyCode.A); check(editor:Get()=="arofile_test","Selected character replaced")
editor:Set(string.rep("x",48),true); editor:Move(48,false); frame()
check(editor.ViewStart>0 and editor.ValueText.Raw.TextBounds.X<=editor.FieldSize.X-14,"Long input scrolls without overflow")
local editorAlloc=allocation; frame(100); check(allocation==editorAlloc,"Editing render allocates no drawings")
edit(Enum.KeyCode.Return); check(w.InputFocus==nil and not editor.CaretLine.Cache.Visible,"Enter commits and hides caret")
editor:Set("default",true)
w:SelectTab(home); frame()
check(toggle.Onscreen and button.Onscreen and slider.Onscreen and bind.Onscreen,"Demo controls fit")
local retainedAllocation=allocation
frame(100)
check(allocation==retainedAllocation,"Rendering allocates no new drawings")

-- New controllers update retained native records without allocation.
local status=w.Status.Ping
status:SetText("32 ms"); status:SetColor(Color3.fromRGB(16,185,129)); frame()
check(status.ValueText.Cache.Text=="32 ms" and status.ValueText.Cache.Color.G==185/255,"Dynamic status text/color")
check(allocation==retainedAllocation,"Status updates retain drawings")
status:SetText("Loading..."); status:SetColor(w.Theme.Muted)
local cfg=w.Config
local memory,folders={},{}
cfg.Unavailable=nil
cfg.Files={isfolder=function(path) return folders[path]==true end,
    makefolder=function(path) folders[path]=true end,
    writefile=function(path,value) memory[path]=value end,
    readfile=function(path) return assert(memory[path],"Missing file") end,
    listfiles=function() local paths={}; for path in pairs(memory) do paths[#paths+1]=path end; return paths end,
    delfile=function(path) memory[path]=nil end}
check(cfg:Save("snapshot"),"Config saves primitive snapshot")
toggle:Set(false); slider:Set(42); dropdown:Set("Quiet"); bind:Set(nil)
check(cfg:Load("snapshot"),"Config loads snapshot"); flush()
check(toggle:Get() and slider:Get()==75 and dropdown:Get()=="Balanced" and bind:Get()==Enum.KeyCode.F7,"Config roundtrip including Enum")
check(not cfg:Save("../outside"),"Config path traversal rejected")
local payload=game:GetService("HttpService"):JSONDecode(memory[cfg.Directory.."snapshot.json"])
payload.Values[slider.ConfigId].Value="bad"
memory[cfg.Directory.."bad.json"]=game:GetService("HttpService"):JSONEncode(payload)
check(not cfg:Load("bad") and slider:Get()==75,"Invalid payload makes no partial edits")
cfg:SetAutoSave(true); slider:Set(42); frame(20)
check(cfg.Pending and not memory[cfg.Directory.."default.json"],"Debounce delays write")
slider:Set(43); frame(20); check(cfg.Pending~=nil,"Debounce resets on change")
frame(20); check(memory[cfg.Directory.."default.json"]~=nil and cfg.Pending==nil,"Debounced default saved")
cfg:SetAutoSave(false); cfg:Load("snapshot"); flush()
local listed,names=cfg:List(); check(listed and #names==3,"Config listing")
check(cfg:Delete("bad") and not memory[cfg.Directory.."bad.json"],"Config deletion")
local beforeDuplicate=liveDrawings
local bad,duplicate=pcall(function() hero:AddToggle({Name="duplicate",Id=toggle.ConfigId}) end)
check(not bad and cfg.Controls[toggle.ConfigId]==toggle,"Duplicate ID rollback preserves original registry")
check(liveDrawings==beforeDuplicate,"Duplicate construction draws removed")

-- Export a trace of the actual retained draw list for visual QA.
local function export(path)
    if not arg[2] then return end
    path=arg[2].."/"..path
    local f=assert(io.open(path,"w"))
    local sorted={}
    for _,d in ipairs(drawings) do if d.Visible and not d.Removed then sorted[#sorted+1]=d end end
    table.sort(sorted,function(a,b) return a.ZIndex<b.ZIndex end)
    for _,d in ipairs(sorted) do
        local p=d.Position or d.From or Vector2.new(0,0)
        if d.Kind=="Text" and d.Center then p=p-Vector2.new(utf8.len(d.Text or "")*(d.Size or 14)*.57/2,0) end
        local s=type(d.Size)=="table" and d.Size or d.To or Vector2.new(0,0)
        local c=d.Color or Color3.fromRGB(255,255,255)
        f:write(string.format("%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\t%d\t%d\t%s\t%s\t%.3f\n",
            d.Kind,p.X,p.Y,s.X,s.Y,d.Radius or 0,type(d.Size)=="number" and d.Size or 0,
            math.floor(c.R*255+0.5),math.floor(c.G*255+0.5),math.floor(c.B*255+0.5),tostring(d.Filled),
            (d.Text or ""):gsub("\t"," "):gsub("\n"," "),d.Transparency or 1))
    end
    f:close()
end
frame()
export("demo-trace.tsv")
w:SelectTab(w.Tabs[3]); frame()
export("config-trace.tsv")
w:SelectTab(home); frame()
click(center(toggle)); check(not toggle:Get() and not state.Enabled,"Toggle callback")
frame(30); check(toggle.Amount<0.001,"Toggle lerp converges")
check(toggle.TrackGlow==nil and toggle.ThumbGlow==nil,"No toggle glow exists in off state")
click(center(accent)); check(w.Theme.Accent.R==1 and w.Theme.Accent.G==90/255 and w.Theme.Accent.B==120/255,"Bright rose accent")
toggle:Set(true,true); flush(); check(toggle:Get() and not state.Enabled,"Silent Set suppresses callback")

-- Capture continues outside bounds, clamps, snaps and flushes final release.
down(slider.TrackPosition+Vector2.new(slider.TrackWidth*0.25,0)); frame()
check(slider:Get()==25,"Slider bar seek")
mouse=slider.TrackPosition+Vector2.new(slider.TrackWidth*2,200); frame()
check(slider:Get()==100,"Slider capture clamps outside")
up(slider.TrackPosition+Vector2.new(-30,0)); flush()
check(slider:Get()==0 and state.Quality==0,"Final release position committed")
scale:Set(1.23456); flush(); check(scale:Get()==1.23 and state.Scale==1.23,"Decimal rounding")
slider:Set(75); frame(60); check(math.abs(slider.Fraction-0.75)<0.001,"Fill lerp converges")

-- Dropdown is above controls, closes on selection and consumes outside clicks.
click(dropdown.FieldPosition+Vector2.new(15,12)); check(w.Popup==dropdown,"Popup open")
check(dropdown.PopupBg.Cache.Visible and dropdown.PopupBg.Cache.ZIndex>slider.Thumb.Cache.ZIndex,"Popup priority")
export("popup-trace.tsv")
local rowP=dropdown.Rows[2].Bg.Cache.Position
click(rowP+Vector2.new(10,10)); check(dropdown:Get()=="Quiet" and state.Profile=="Quiet" and not w.Popup,"Select floating option")
click(dropdown.FieldPosition+Vector2.new(10,10))
local old=toggle:Get(); click(center(toggle)); check(not w.Popup and toggle:Get()==old,"Outside click consumed")
click(center(reset)); check(dropdown:Get()=="Balanced","Button release callback")
local buttonCalls=0
button.Callback=function() buttonCalls=buttonCalls+1 end
down(center(button)); frame(); check(button.Depression>0,"Button tactile depression")
up(button.Position+Vector2.new(-200,-200)); flush(); check(buttonCalls==0,"Release outside cancels")
click(center(button)); check(buttonCalls==1,"Release inside fires once")

-- Key capture semantics: consumed assignment, Escape cancel, Backspace clear.
local triggered,changed=0,0
bind.Callback=function(k) triggered=triggered+1; check(k==Enum.KeyCode.F8,"Enum callback") end
bind.OnChanged=function() changed=changed+1 end
click(center(bind)); check(w.Listening==bind and bind.KeyText.Cache.Text=="...","Listening indicator")
key(Enum.KeyCode.F8); check(bind:Get()==Enum.KeyCode.F8 and triggered==0 and changed==1,"Assignment consumes key")
key(Enum.KeyCode.F8); check(triggered==1,"Assigned key activates")
key(Enum.KeyCode.F8,true); check(triggered==1,"Processed keyboard input ignored")
focused={}; key(Enum.KeyCode.F8); key(Enum.KeyCode.RightControl)
check(triggered==1 and w.Visible,"Chat focus blocks feature and visibility keys")
focused=nil
UIS.InputBegan:Fire(input("Keyboard",Enum.KeyCode.F8),false); focused={}; flush()
check(triggered==1,"Queued key callback suppressed when chat starts")
focused=nil
w.RespectProcessed=false; key(Enum.KeyCode.F8,true); key(Enum.KeyCode.RightControl,true)
check(triggered==1 and w.Visible,"Processed chat keys blocked even with RespectProcessed=false"); w.RespectProcessed=true
click(center(bind)); key(Enum.KeyCode.Escape); check(not w.Listening and bind:Get()==Enum.KeyCode.F8,"Escape cancels")
click(center(bind)); key(Enum.KeyCode.Backspace); check(bind:Get()==nil and changed==2,"Backspace unbind")
click(center(bind)); key(Enum.KeyCode.Insert); check(bind:Get()==Enum.KeyCode.Insert and w.Visible,"Capture consumes visibility key")
bind:Set(Enum.KeyCode.F7,true)

-- Visibility/minimize and tab switching release captures and hide descendants.
down(slider.TrackPosition); UIS.WindowFocusReleased:Fire(); frame();
local fixed=slider:Get(); mouse=slider.TrackPosition+Vector2.new(slider.TrackWidth,0); frame()
check(slider:Get()==fixed,"Focus loss cancels slider capture")
click(dropdown.FieldPosition+Vector2.new(10,10)); key(Enum.KeyCode.RightControl)
check(not w.Visible and not w.Popup,"Hide cancels popup")
for _,d in ipairs(drawings) do check(not d.Visible or d.Removed,"Hidden drawings invisible") end
key(Enum.KeyCode.RightControl); check(w.Visible,"Hidden window restored by hotkey")
click(w.Position+Vector2.new(w.Size.X-16,18)); check(w.Modal and not w.Destroyed,"Close opens modal")
local priorToggle=toggle:Get(); click(center(toggle)); check(w.Modal and toggle:Get()==priorToggle,"Modal blocks underlying controls")
key(Enum.KeyCode.Escape); check(not w.Modal,"Escape closes modal")
w:SelectTab(w.Tabs[2]); frame(); check(not slider.Thumb.Cache.Visible and w.Tabs[2].Cards[1].Bg.Cache.Visible,"Tab visibility")
key(Enum.KeyCode.F7); check(triggered==1,"Inactive binds suppressed")
w:SelectTab(home); frame()
click(center(w.Profile)); check(w.Active==w.Tabs[2],"Interactive profile selects Profiles tab")
w:SelectTab(home); frame()

-- Drag follows with lag, settles after release, and clamps to viewport.
local before=w.Position
down(before+Vector2.new(100,14)); mouse=before+Vector2.new(200,94); frame()
check(w.Position.X>before.X and w.Position.X<before.X+100,"Smoothed drag")
up(mouse); frame(60); check(math.abs(w.Position.X-(before.X+100))<0.01,"Drag settles")
down(w.Position+Vector2.new(100,14)); mouse=Vector2.new(-400,-400); frame(60); up(); frame(60)
check(w.Position.X<0.01 and w.Position.Y<0.01,"Drag viewport clamp")

-- Scroll lots of options and controls; whole-row clipping forbids overflow.
-- Use another window because grid occupancy is explicit.
local w2=library:CreateWindow({Title="SECOND",Position=Vector2.new(300,100),Size=Vector2.new(680,480)})
local tab=w2:CreateTab("Overflow")
local card=tab:CreateCard({Name="SCROLL",ColumnSpan=6,RowSpan=6})
local options={}; for i=1,20 do options[i]="Choice "..i end
local many=card:AddDropdown({Name="Many options",Options=options})
for i=1,12 do card:AddToggle({Name="Option "..i}) end
frame(); check(liveConnections==5,"Multiple windows share event engine")
click(many.FieldPosition+Vector2.new(10,10)); frame()
check(w2.Popup==many and many.VisibleRows==6,"Dropdown rows capped")
wheel(many.PopupBg.Cache.Position+Vector2.new(10,10),-20)
check(many.Scroll==14,"Popup wheel clamps")
click(many.Rows[6].Bg.Cache.Position+Vector2.new(10,10)); check(many:Get()=="Choice 20","Scrolled option selection")
wheel(card.Position+Vector2.new(10,80),-20); check(card.Scroll==card.Maximum,"Card wheel scroll")
for _,c in ipairs(card.Controls) do
    if c.Onscreen then
        check(c.Position.Y>=card.InnerPosition.Y and c.Position.Y+c.Height<=card.InnerPosition.Y+card.InnerSize.Y,"Whole-row clipping")
    else check(not c.Title.Cache.Visible,"Offscreen text hidden") end
end
check(card.Controls[1].Onscreen==false,"Top row scrolls out")
card:ScrollBy(-10000); frame()
click(many.FieldPosition+Vector2.new(10,10)); many:Destroy(); frame()
check(not w2.Popup,"Destroyed popup clears ownership")
local prior=card.ContentHeight; card.Controls[1]:Destroy(); check(card.ContentHeight<prior,"Destroy reflows card")
card:Destroy(); check(#tab.Cards==0,"Card detaches")
tab:Destroy(); check(w2.Active==nil and #w2.Tabs==0,"Active tab destruction")
w2:Destroy(); w2:Destroy(); check(liveConnections==5,"Destroy one preserves other window")

-- Failures and destruction are resource-safe.
local beforeCount=liveDrawings
local ok=pcall(function() library:CreateWindow({Font=3}) end)
check(not ok and liveDrawings==beforeCount,"Monospace font rejected")
ok=pcall(function() tuning:AddLabel({Text="Bad size",Size=15}) end)
check(not ok and liveDrawings==beforeCount,"Noncalibrated text size rolls back")
ok=pcall(function() tuning:AddSlider({Min=5,Max=1}) end)
check(not ok and liveDrawings==beforeCount,"Invalid slider rolls back")
ok=pcall(function() home:CreateCard({Column=1,ColumnSpan=4,Row=1,RowSpan=2}) end)
check(not ok and liveDrawings==beforeCount,"Overlapping card rejected before drawing")
failAt=allocation+5
ok=pcall(function() library:CreateWindow({Title="FAIL"}) end)
failAt=nil
check(not ok and liveDrawings==beforeCount and liveConnections==5,"Partial window allocation rollback")
failProperty="Font"
ok=pcall(function() library:CreateWindow({Title="UNSUPPORTED"}) end)
failProperty=nil
check(not ok and liveDrawings==beforeCount and liveConnections==5,"Property assignment failure rollback")
local callbackRan=false
toggle.Callback=function() callbackRan=true end
toggle:Set(not toggle:Get()); toggle:Destroy(); flush(); frame(); check(not callbackRan,"Queued callbacks skip destroyed owner")
button.Callback=function() error("application failure") end
click(center(button)); check(#warnings==1,"Callback errors isolated")
library:Unload(); library:Unload(); flush()
check(liveDrawings==0 and liveConnections==0,"Unload releases every Drawing and event connection")
frame(); key(Enum.KeyCode.Insert); check(liveDrawings==0,"No resurrection after unload")
local fresh=library:CreateWindow(); frame(); fresh:Destroy()
check(liveDrawings==0 and liveConnections==0,"Engine restarts and cleans up")

-- Optional avatar paths: all native Image resources remain owned by Profile.
imageSupported=true
local avatarWindow=library:CreateWindow()
flush(); frame()
check(avatarWindow.Profile.AvatarReady and avatarWindow.Profile.Image.Cache.Visible,"PNG avatar assigned and rendered")
check(avatarWindow.Profile.Image.Cache.Size.X==34 and avatarWindow.Profile.Image.Cache.Size.Y==34,"34x34 avatar image")
local profileCalls=0
avatarWindow.Profile.Callback=function(player) check(player==testPlayer,"Profile callback receives LocalPlayer"); profileCalls=profileCalls+1 end
click(center(avatarWindow.Profile)); check(profileCalls==1,"Profile callback dispatch")
avatarWindow:Destroy(); check(liveDrawings==0 and liveConnections==0,"Avatar image cleanup")

httpMode="error"
avatarWindow=library:CreateWindow(); flush(); frame()
check(not avatarWindow.Profile.AvatarReady and avatarWindow.Profile.Fallback.Cache.Visible,"HTTP error initials fallback")
check(not avatarWindow.Profile.Image.Cache.Visible,"Failed avatar remains hidden")
avatarWindow:Destroy()

avatarWindow=library:CreateWindow(); flush(); frame()
avatarWindow.Profile:Destroy(); frame()
check(avatarWindow.Visible,"Removing profile independently preserves window rendering")
avatarWindow:Destroy()
httpMode="html"
avatarWindow=library:CreateWindow(); flush(); frame()
check(not avatarWindow.Profile.AvatarReady,"Reject non-PNG response")
avatarWindow:Destroy()
httpMode="success"
avatarWindow=library:CreateWindow(); failProperty="Data"; flush(); failProperty=nil; frame()
check(avatarWindow.Profile.AvatarStatus=="fallback" and avatarWindow.Profile.Fallback.Cache.Visible,"Image Data failure fallback")
avatarWindow:Destroy()
failProperty="Size"; failKind="Image"; avatarWindow=library:CreateWindow(); failProperty=nil; failKind=nil; frame()
check(avatarWindow.Profile.Image==nil and avatarWindow.Profile.AvatarStatus=="unsupported","Partial optional Image setup rollback")
avatarWindow:Destroy()

local requestsBefore=httpRequests
avatarWindow=library:CreateWindow(); avatarWindow:Destroy(); flush()
check(httpRequests==requestsBefore,"Destroy cancels queued avatar work")
avatarWindow=library:CreateWindow()
httpHook=function() avatarWindow:Destroy() end
flush(); httpHook=nil
check(avatarWindow.Profile.Destroyed,"Destroy during avatar fetch prevents late assignment")
check(liveDrawings==0 and liveConnections==0,"Every avatar failure/race path releases resources")
print("PASS: "..passed.." assertions; "..allocation.." allocations; zero live drawings/connections")
