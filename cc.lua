local supplied = ...
local Env = type(supplied) == "table" and supplied or getgenv()
local Boot = {}
Env.SkiderMM2Boot = Boot
local function AwaitBoot(read, name)
    local deadline = os.clock() + 120
    repeat
        if Env.SkiderMM2Boot ~= Boot then error("[Skider MM2] Startup superseded", 0) end
        local value = read()
        if value then return value end
        if os.clock() >= deadline then error("[Skider MM2] Startup timeout: " .. name, 0) end
        task.wait(0.1)
    until false
end
local function BootChild(parent, name)
    return AwaitBoot(function() return parent:FindFirstChild(name) end, name)
end
local function WaitGameReady()
    AwaitBoot(function() return game:IsLoaded() end,"game loaded")
    local players=game:GetService("Players")
    local player=AwaitBoot(function() return players.LocalPlayer end,"LocalPlayer")
    local gui=BootChild(player,"PlayerGui")
    BootChild(gui,"MainGUI")
    AwaitBoot(function()
        local character=player.Character
        return character and character:FindFirstChildOfClass("Humanoid")
            and character:FindFirstChild("HumanoidRootPart") and workspace.CurrentCamera
    end,"character and camera ready")
end
local Core = (function()
local Core = {}

function Core.requiresVerification(mode, target, total, authenticated)
    return mode == 2 and target >= total and authenticated ~= true
end

function Core.number(value, fallback, low, high)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then n = fallback end
    return math.max(low, math.min(high, n))
end

function Core.config(raw, mode, fps)
    raw = type(raw) == "table" and raw or {}
    local crates = type(raw.Crates) == "table" and raw.Crates or {}
    local pass = type(raw.Battlepass) == "table" and raw.Battlepass or {}
    local hook = type(raw["Webhook Noti"]) == "table" and raw["Webhook Noti"] or {}
    local fullscreenUI = raw.UI
    if fullscreenUI == nil then fullscreenUI = raw.Ui end
    return {
        fullscreenUI = fullscreenUI ~= false,
        fpsBoost = raw["Fps Boots"] == true,
        mode = mode == 2 and 2 or 1,
        fps = math.floor(Core.number(fps, 60, 1, 2000)),
        speed = Core.number(raw["Spead"], 120, 1, 1000000),
        collectDelay = Core.number(raw["Delay Collect Candy"], 1, 0, 30),
        crateThreshold = math.floor(Core.number(crates["Candies When"], 1800, 1, 1000000000000)),
        openDelay = Core.number(crates["Delay Open"], 0.5, 0, 60),
        passThreshold = math.floor(Core.number(pass["Candies When"], 1800, 1, 1000000000000)),

        tierCap = math.floor(Core.number(pass["Tier Final"], 29, 1, 1000000)),
        buyFinalReward = pass["Buy Final Reward"] ~= false,

        finalRewardThreshold = math.floor(Core.number(pass["Final Reward Candies When"], 0, 0, 1000000000)),
        crateID = type(crates["Crate ID"]) == "string" and crates["Crate ID"] or "",
        currencyID = type(raw["Currency ID"]) == "string" and raw["Currency ID"] or "",
        webhook = {
            enabled = hook.Enabled == true,
            url = type(hook.URL) == "string" and hook.URL or "",
            discordID = tostring(hook["Discord ID"] or ""),
            ping = hook["Ping User"] == true,
            interval = Core.number(hook["Status Interval"], 300, 30, 86400),
        },
        battleNotices = type(raw["Noti Battle"]) == "table" and raw["Noti Battle"] or {},
        noteItems = type(raw["Note Items"]) == "table" and raw["Note Items"] or {
            "CandyCorn", "Skulls", "Bombs", "Bullets", "Glow", "Brew", "Drool",
            "Catseye", "Raven", "Embergun", "Embersickle", "Chroma Embersickle",
        },
        resetDelay = Core.number(raw["Reset Delay"], 2, 0, 10),
        segment = Core.number(raw["Segment Distance"], 14, 2, 14),
        confirmTimeout = Core.number(raw["Confirm Timeout"], 8, 3, 30),
    }
end

function Core.isRoundMember(member)
    return type(member)=="table" and member.Dead==false and member.Killed~=true
        and (member.Role=="Innocent" or member.Role=="Sheriff" or member.Role=="Murderer"
            or member.Role=="Survivor" or member.Role=="Zombie")
end

function Core.canFarm(info)
    return info.enabled == true and info.paused ~= true and info.waiting ~= true
        and info.ended ~= true and (tonumber(info.timer) or 0) > 0 and info.inMap == true
        and info.characterAlive == true and Core.isRoundMember(info.member)
end

function Core.batch(balance, threshold, cost, remaining)
    if cost <= 0 or threshold < cost or balance < threshold then return 0 end
    return math.max(0, math.min(math.floor(threshold / cost), math.floor(balance / cost), remaining or math.huge))
end

function Core.ownedCount(owned, id)
    if type(owned) ~= "table" or id == nil then return 0 end
    if type(owned[id]) == "number" then return owned[id] end
    if owned[id] == true then return 1 end
    local count = 0
    for _, item in ipairs(owned) do if item == id then count = count + 1 end end
    return count
end

function Core.claimKeys(event, rewards, cap)
    local keys = {}
    local claimed = event.ClaimedRewards or {}
    local limit = math.min(tonumber(event.CurrentTier) or 0, cap)
    for key, reward in pairs(rewards) do
        local tier = tonumber(key)
        if tier and tier <= limit and not reward.Final
            and claimed[tostring(key)] ~= true and claimed[key] ~= true then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
    return keys
end

function Core.normalize(value)
    return tostring(value):lower():gsub("[^%w]", "")
end

function Core.itemName(id, info)
    info = info or {}
    local name = info.ItemName or info.Name or id
    if info.Chroma == true and not tostring(name):lower():find("chroma", 1, true) then name = "Chroma " .. name end
    return tostring(name)
end

local ItemStyles = {
        common = {rank=1, icon="⚪", color=9807270},
        uncommon = {rank=2, icon="🟢", color=5763719},
        rare = {rank=3, icon="🔵", color=3447003},
        legendary = {rank=4, icon="🟣", color=10181046},
        godly = {rank=5, icon="💎", color=16738740},
        vintage = {rank=6, icon="🏛️", color=15844367},
        classic = {rank=6, icon="🏛️", color=15844367},
        ancient = {rank=7, icon="🔥", color=15105570},
        unique = {rank=8, icon="🏆", color=16766720},
        unknown = {rank=0, icon="📦", color=5037412},
}
local ChromaStyles = {}
for rarity,style in pairs(ItemStyles) do
    ChromaStyles[rarity]={rank=math.max(style.rank,5),icon="🌈",color=style.color}
end
function Core.itemStyle(info)
    info = type(info) == "table" and info or {}
    local rarity=Core.normalize(info.Rarity or "")
    local styles=info.Chroma==true and ChromaStyles or ItemStyles
    return styles[rarity] or styles.unknown
end

function Core.itemDisplay(id, info)
    info = type(info) == "table" and info or {}
    local style = Core.itemStyle(info)
    local kind = Core.normalize(info.ItemType or "")
    local icon = kind == "knife" and "🗡️" or kind == "gun" and "🔫" or "📦"
    local name = Core.itemName(id, info):gsub("([\\`*_~|>])", "\\%1")
    if style.rank >= 3 then
        local rarity = tostring(info.Rarity or "Chroma")
        if info.Chroma == true then rarity = "Chroma · " .. rarity end
        return style.icon .. " " .. icon .. " **" .. name .. "** · " .. rarity
    end
    return icon .. " " .. name
end

function Core.itemLines(owned, database, wanted)
    local lines = {}
    local names = {}
    for _, name in ipairs(wanted) do if name ~= "" then names[Core.normalize(name)] = true end end
    for id, amount in pairs(owned or {}) do
        local info = database[id]
        if type(amount) == "number" and amount > 0 and info then
            local name = Core.itemName(id, info)
            if names[Core.normalize(name)] or names[Core.normalize(id)] then
                lines[#lines + 1] = {rank=Core.itemStyle(info).rank, name=name,
                    text=Core.itemDisplay(id,info).." ×"..math.floor(amount)}
            end
        end
    end
    table.sort(lines,function(a,b) if a.rank~=b.rank then return a.rank>b.rank end;return a.name<b.name end)
    local output, length = {}, 0
    for _, entry in ipairs(lines) do
        if length + #entry.text + 1 > 990 then output[#output+1]="…";break end
        output[#output+1]=entry.text;length=length+#entry.text+1
    end
    return #output > 0 and table.concat(output, "\n") or "None"
end

function Core.battleNotice(filters, event)
    local any = false
    for _, value in ipairs(filters) do
        if tostring(value) ~= "" then
            any = true
            if Core.normalize(value) == Core.normalize(event) then return true end
        end
    end
    return not any
end

function Core.duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

function Core.webhook(metrics, title, description, hook, itemInfo)
    local ping = hook.ping and hook.discordID:match("^%d+$") ~= nil
    local function field(name, value, inline)
        return {name = name, value = tostring(value):sub(1, 1024), inline = inline == true}
    end
    return {
        username = "Skider MM2 Kaitun",
        content = ping and "<@" .. hook.discordID .. ">" or "",
        allowed_mentions = {parse = {}, users = ping and {hook.discordID} or {}},
        embeds = {{
            title = ("🎃 " .. tostring(title)):sub(1, 256), description = tostring(description):sub(1, 1024),
            color = itemInfo and Core.itemStyle(itemInfo).color or 5037412, url = "https://mtrchill.click",
            fields = {
                field("👤 User", metrics.user, true), field("🍬 Candies", metrics.candies, true),
                field("🎯 Candies This Round", metrics.bag, true), field("🏅 Battle Pass Tier", metrics.tier, true),
                field("🗺️ Map", metrics.map, true), field("🎭 Role", metrics.role, true),
                field("⏳ Round Time", metrics.roundTime, true), field("⏱️ Elapsed", metrics.elapsed, true),
                field("🎒 Items This Account", metrics.items, false),
            },
            footer = {text = "mtrchill.click | Skider MM2 Kaitun"},
        }},
    }
end

return Core

end)()
local AttachFPSBoost = (function()
return function()
    local Players=game:GetService("Players")
    local Workspace=game:GetService("Workspace")
    local CollectionService=game:GetService("CollectionService")
    local Lighting=game:GetService("Lighting")
    local active=true
    local stopped=false
    local originals=setmetatable({},{__mode="k"})
    local connections={}
    local queue,queued={},setmetatable({},{__mode="k"})
    local head,tail=1,0
    local characters={}
    local characterRoots={}
    local playerConnections={}
    local function enqueue(object)
        if not active or queued[object] then return end
        tail=tail+1;queue[tail]=object;queued[object]=true
    end
    local function setCharacter(player,character)
        local previous=characters[player]
        if previous then characterRoots[previous]=nil end
        characters[player]=character
        if character then characterRoots[character]=true end
    end
    local function unwatchPlayer(player)
        setCharacter(player,nil)
        for _,connection in ipairs(playerConnections[player] or {}) do connection:Disconnect() end
        playerConnections[player]=nil
    end
    local function watchPlayer(player)
        unwatchPlayer(player)
        setCharacter(player,player.Character)
        playerConnections[player]={
            player.CharacterAdded:Connect(function(character) setCharacter(player,character) end),
            player.CharacterRemoving:Connect(function(character)
                if characters[player]==character then setCharacter(player,nil) end
            end),
        }
    end
    for _,player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
    connections[#connections+1]=Players.PlayerAdded:Connect(watchPlayer)
    connections[#connections+1]=Players.PlayerRemoving:Connect(unwatchPlayer)

    local function change(object,property,value)
        pcall(function()
            local current=object[property]
            if current==value then return end
            local values=originals[object]
            if not values then values={};originals[object]=values end
            if values[property]==nil then values[property]=current end
            object[property]=value
        end)
    end
    local function restoreObject(object)
        local values=originals[object]
        if not values then return end
        for property,value in pairs(values) do pcall(function() object[property]=value end) end
        originals[object]=nil
    end
    local function protected(object)
        local camera=Workspace.CurrentCamera
        local current=object
        while current and current~=Workspace do
            if characterRoots[current] or current==camera
                or current:GetAttribute("CoinID")~=nil
                or CollectionService:HasTag(current,"ServerCoinPart")
                or CollectionService:HasTag(current,"CoinVisual")
                or current.Name=="Coin_Server" or current.Name=="CoinVisual" then return true end
            current=current.Parent
        end
        return false
    end
    local function optimize(object)
        if not active or not object.Parent then return end
        if not (object:IsA("BasePart") or object:IsA("Decal") or object:IsA("Texture")
            or object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")
            or object:IsA("Light") or object:IsA("SurfaceGui") or object:IsA("BillboardGui")) then return end
        if protected(object) then restoreObject(object);return end
        if object:IsA("BasePart") then
            change(object,"Transparency",1)
            change(object,"LocalTransparencyModifier",1)
            change(object,"CastShadow",false)
        elseif object:IsA("Decal") or object:IsA("Texture") then
            change(object,"Transparency",1)
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")
            or object:IsA("PointLight") or object:IsA("SpotLight") or object:IsA("SurfaceLight")
            or object:IsA("SurfaceGui") or object:IsA("BillboardGui") then
            change(object,"Enabled",false)
        end
    end
    local function optimizeLighting()
        if not active then return end
        change(Lighting,"GlobalShadows",false)
        for _,object in ipairs(Lighting:GetDescendants()) do
            if object:IsA("PostEffect") then change(object,"Enabled",false) end
        end
    end

    local quality
    local qualityOK,rendering=pcall(function() return settings().Rendering end)
    if qualityOK and rendering then
        local ok,value=pcall(function() return rendering.QualityLevel end)
        if ok then
            quality=value
            pcall(function() rendering.QualityLevel=Enum.QualityLevel.Level01 end)
        end
    end
    local terrain=Workspace.Terrain
    local decorationOK,decoration=pcall(function() return terrain.Decoration end)
    if decorationOK and decoration~=nil and typeof(sethiddenproperty)=="function" then
        pcall(sethiddenproperty,terrain,"Decoration",false)
    end

    connections[#connections+1]=Workspace.DescendantAdded:Connect(function(object)
        enqueue(object)
    end)
    connections[#connections+1]=Lighting.DescendantAdded:Connect(function(object)
        if active and object:IsA("PostEffect") then change(object,"Enabled",false) end
    end)
    for _,tag in ipairs({"ServerCoinPart","CoinVisual"}) do
        connections[#connections+1]=CollectionService:GetInstanceAddedSignal(tag):Connect(function(object)
            enqueue(object)
            for _,child in ipairs(object:GetDescendants()) do enqueue(child) end
        end)
    end
    task.spawn(function()
        optimizeLighting()
        local initial=Workspace:GetDescendants()
        local initialIndex=1
        while active do
            if initial then
                for _=1,24 do
                    local object=initial[initialIndex]
                    if not object then initial=nil;break end
                    enqueue(object)
                    initialIndex=initialIndex+1
                end
            end
            local started,count=os.clock(),0
            while active and head<=tail and count<24 and os.clock()-started<0.0015 do
                local object=queue[head];queue[head]=nil;head=head+1
                queued[object]=nil
                optimize(object)
                count=count+1
            end
            if head>tail then queue={};head=1;tail=0 end
            task.wait((initial or head<=tail) and 0 or 0.25)
        end
    end)
    local function stop()
        if not active then
            while not stopped do task.wait() end
            return
        end
        active=false
        for _,connection in ipairs(connections) do connection:Disconnect() end
        for player in pairs(playerConnections) do unwatchPlayer(player) end
        queue={};queued=setmetatable({},{__mode="k"})
        local started,count=os.clock(),0
        for object in pairs(originals) do
            restoreObject(object);count=count+1
            if count>=24 or os.clock()-started>=0.0015 then task.wait();started=os.clock();count=0 end
        end
        if quality~=nil then pcall(function() rendering.QualityLevel=quality end) end
        if decorationOK and decoration~=nil and typeof(sethiddenproperty)=="function" then
            pcall(sethiddenproperty,terrain,"Decoration",decoration)
        end
        stopped=true
    end
    return {Stop=stop}
end

end)()
local AttachKaitun = (function()

return function(Context)

AwaitBoot(function() return game:IsLoaded() end,"game loaded")
local Env = Context.env
if game.PlaceId ~= 142823291 then error("[Skider] Join MM2 before running.") end
if type(Env.SkiderMM2)=="table" and type(Env.SkiderMM2.Stop)=="function" then pcall(Env.SkiderMM2.Stop) end
local Config=Core.config(Env.ConfigKaitunMM2Hallowen2026,Env.ModeFarming,Env.Fpslock)
local Validation=type(Env.SkiderMM2Validation)=="table" and Env.SkiderMM2Validation or {}
Env.SkiderMM2Validation=nil
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Collection=game:GetService("CollectionService")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local Player=AwaitBoot(function() return Players.LocalPlayer end,"LocalPlayer")
local PlayerGui=BootChild(Player,"PlayerGui")
local Remotes=BootChild(RS,"Remotes")
local Gameplay=BootChild(Remotes,"Gameplay")
local Inventory=BootChild(Remotes,"Inventory")
local Shop=BootChild(Remotes,"Shop")
local function LoadModule(module: any): any return require(module) end
local Sync=LoadModule(BootChild(BootChild(RS,"Database"),"Sync"))
local Round=LoadModule(BootChild(BootChild(RS,"Modules"),"CurrentRoundClient"))
local EventInfo=LoadModule(BootChild(BootChild(RS,"SharedServices"),"EventInfoService"))
local function WaitForEvent()
    return AwaitBoot(function()
        local ok,event=pcall(EventInfo.GetMainEvent,EventInfo)
        local info=ok and type(event)=="table" and event.EventStartInfo
        local pass=type(info)=="table" and info.BattlePass
        if type(event)=="table" and type(event.Title)=="string" and event.Title~=""
            and type(info)=="table" and type(info.CurrencyName)=="string" and info.CurrencyName~=""
            and type(pass)=="table" and type(pass.Rewards)=="table"
            and tonumber(pass.TotalTiers) and tonumber(pass.TotalTiers)>0
            and tonumber(pass.TierCost) and tonumber(pass.TierCost)>0
            and type(Sync.NewShop)=="table" and next(Sync.NewShop)~=nil
            and type(Sync.Weapons)=="table" and next(Sync.Weapons)~=nil then
            return event
        end
    end,"Halloween event data")
end
local Event=WaitForEvent()
local BP=Event.EventStartInfo.BattlePass
local HW=BootChild(BootChild(Remotes,"Events"),Event.Title.."Remotes")
local Currency=Config.currencyID~="" and Config.currencyID or Event.EventStartInfo.CurrencyName
local TargetTier=math.min(Config.tierCap,BP.TotalTiers)
local CrateID=Config.crateID
if CrateID=="" and Sync.NewShop[Event.Title.."Box"] then CrateID=Event.Title.."Box" end
assert(Config.mode~=1 or (Sync.NewShop[CrateID] and Sync.NewShop[CrateID].Type=="MysteryBox"),"[Skider] Set a valid Crates > Crate ID.")
local CrateCost=Config.mode==1 and tonumber(Sync.NewShop[CrateID].Price[Currency]) or 0
assert(Config.mode~=1 or (CrateCost and CrateCost>0 and Config.crateThreshold>=CrateCost),"[Skider] Crate threshold must cover one crate.")
assert(Config.mode~=2 or (BP.TierCost>0 and Config.passThreshold>=BP.TierCost),"[Skider] Tier threshold must cover one tier.")
local ProfileCategories={Weapons=true,Materials=true}
for _,reward in pairs(BP.Rewards) do
    if type(reward)=="table" and type(reward.ItemType)=="string" then ProfileCategories[reward.ItemType]=true end
end
if type(BP.FinalRewardType)=="string" then ProfileCategories[BP.FinalRewardType]=true end
local S={running=true,paused=false,status="Starting",notice="",started=os.clock(),bag=0,maxBag=50,epoch=0,waiting=false,ended=false,
    available=0,profile=nil,profileAt=0,map=nil,mapCF=nil,mapSize=nil,mapChecked=0,tween=nil,moveToken=0,
    connections={},failed={},transaction=false,purchaseBlocked=false,claimPending={},inflight=nil,logQueue={},webhookQueue={},
    session=tostring(os.time()).."-"..tostring(math.floor(os.clock()*1000)),receipts=0,errors=0,webhookStatus="Disabled",lastWebhook=0,
    lastProfileRead=-math.huge,completed=false,collected=0,finalPending=false,itemsDirty=true,itemsText="None"}
local API={}
Env.SkiderMM2=API
local Ui,Labels,Notify,FpsBoost
local function clone(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {}
    if seen[value] then return seen[value] end
    local out={};seen[value]=out
    for k,v in pairs(value) do out[k]=clone(v,seen) end
    return out
end
local function log(event,details)
    if #S.logQueue>=200 then return end
    local ok,body=pcall(Http.JSONEncode,Http,details or {})
    S.logQueue[#S.logQueue+1]=string.format("[%s %.3f] %s %s\n",S.session,os.clock(),event,ok and body or "{}")
end
local function connect(signal,callback)
    local c=signal:Connect(function(...)
        if not S.running then return end
        local ok,err=pcall(callback,...)
        if not ok then S.errors=S.errors+1;S.notice="Client error; see local log";log("CLIENT_ERROR",{message=tostring(err)}); end
    end)
    S.connections[#S.connections+1]=c;return c
end
local function cancelMovement()
    local moving=Context.config.AutoCandy or Context.snapshot().moving
    Context.config.AutoCandy=false
    if moving then Context.cancel() end
end
local function syncBase()
    local base=Context.snapshot()
    S.bag=base.bag;S.maxBag=base.maxBag;S.waiting=base.waiting
    return base
end
local function blockedByVerification()
    return Core.requiresVerification(Config.mode,TargetTier,BP.TotalTiers,Player:GetAttribute("Authenticated"))
end
local function status(text) S.status=text end
local function balance() return S.profile and (tonumber(S.profile.materials[Currency]) or 0) or 0 end
local function passData() return S.profile and S.profile.event or {CurrentTier=0,ClaimedRewards={}} end
local function currentCharacter()
    local c=Player.Character;local h=c and c:FindFirstChildOfClass("Humanoid");local r=c and c:FindFirstChild("HumanoidRootPart")
    if not h or not r or h.Health<=0 then return nil end
    return c,h,r
end
local function findMap()
    if os.clock()-S.mapChecked<0.5 then return S.map end
    S.mapChecked=os.clock()
    if S.map and S.map.Parent and S.map:FindFirstChild("CoinContainer") then return S.map end
    S.map,S.mapCF,S.mapSize=nil,nil,nil
    for _,o in ipairs(workspace:GetChildren()) do
        if o:IsA("Model") and o.Name~="Lobby" and o:FindFirstChild("CoinContainer") then
            local ok,cf,size=pcall(o.GetBoundingBox,o)
            if ok then S.map,S.mapCF,S.mapSize=o,cf,size;break end
        end
    end
    return S.map
end
local function timer()
    local part=workspace:FindFirstChild("RoundTimerPart")
    return part and tonumber(part:GetAttribute("Time")) or 0
end
local function member() return Round.PlayerData and Round.PlayerData[Player.Name] end
local function inMap(root)
    if not root or not findMap() or not S.mapCF then return false end
    local p=S.mapCF:PointToObjectSpace(root.Position);local half=S.mapSize/2+Vector3.new(8,12,8)
    return math.abs(p.X)<=half.X and math.abs(p.Y)<=half.Y and math.abs(p.Z)<=half.Z
end
local function canFarm()
    syncBase()
    local _,h,r=currentCharacter()
    return not blockedByVerification() and Core.canFarm({enabled=S.running,paused=S.paused or S.transaction or Validation.NoMovement==true,
        waiting=S.waiting,ended=S.ended,timer=timer(),inMap=inMap(r),characterAlive=h~=nil,member=member()})
end
local function metrics(includeItems)
    syncBase()
    local m=member()
    local _,humanoid,root=currentCharacter()
    local remaining=timer()
    if includeItems~=false and S.itemsDirty then
        S.itemsText=Core.itemLines(S.profile and S.profile.owned.Weapons or {},Sync.Weapons,Config.noteItems)
        S.itemsDirty=false
    end
    return {user=Player.Name,candies=balance(),bag=string.format("%d/%d",S.bag,S.maxBag),
        tier=string.format("%d/%d",tonumber(passData().CurrentTier) or 0,BP.TotalTiers),map=findMap() and S.map.Name or "Lobby",
        role=Core.isRoundMember(m) and humanoid~=nil and inMap(root) and remaining>0 and not S.ended and m.Role or "Spectator",
        roundTime=remaining>0 and string.format("%02d:%02d",math.floor(remaining/60),remaining%60) or "N/A",
        elapsed=Core.duration(os.clock()-S.started),items=includeItems~=false and S.itemsText or nil}
end
local function validWebhook(url)
    return url:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+") or url:match("^https://discord%.com/api/v%d+/webhooks/%d+/[%w_%-]+")
        or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+")
end
Notify=function(event,description,battle,itemInfo)
    log(event,{message=description,balance=balance(),tier=passData().CurrentTier})
    if blockedByVerification() then return end
    if Validation.NoWebhook or not Config.webhook.enabled or Config.webhook.url=="" then return end
    if battle and not Core.battleNotice(Config.battleNotices,event) then return end
    if not validWebhook(Config.webhook.url) then S.webhookStatus="Invalid URL";return end
    if #S.webhookQueue>=40 then S.webhookStatus="Queue full";return end
    S.webhookQueue[#S.webhookQueue+1]=Core.webhook(metrics(),event,description,Config.webhook,itemInfo)
end
local function applyProfile(data)
    if type(data)~="table" or type(data.Materials)~="table" or type(data[Event.Title])~="table" then return false end
    local owned={}
    for cat in pairs(ProfileCategories) do
        owned[cat]=clone(type(data[cat])=="table" and data[cat].Owned or {})
    end
    S.profile={event=clone(data[Event.Title]),materials=owned.Materials,owned=owned};S.profileAt=os.clock();S.itemsDirty=true;return true
end

local function invoke(remote,args,timeout)
    if S.inflight and not S.inflight.done then return false,"Request already pending" end
    local op={done=false,ok=false,value=nil};S.inflight=op
    task.spawn(function() op.ok,op.value=pcall(remote.InvokeServer,remote,table.unpack(args,1,args.n));op.done=true end)
    local deadline=os.clock()+timeout
    while S.running and not op.done and os.clock()<deadline do task.wait(0.05) end
    if not op.done then return false,"Request pending" end
    if S.inflight==op then S.inflight=nil end
    if not op.ok then return false,"Remote error" end
    return true,op.value
end
local function refreshProfile()
    S.lastProfileRead=os.clock()
    local ok,data=invoke(Inventory:WaitForChild("GetProfileData"),table.pack(),Config.confirmTimeout)
    if not ok then return false,data end
    return applyProfile(data),"Invalid profile"
end
local function waitConfirm(predicate)
    local deadline=os.clock()+Config.confirmTimeout;local nextRead=os.clock()+0.6
    while S.running and os.clock()<deadline do
        if S.profile and predicate(S.profile) then return true end
        if os.clock()>=nextRead and not (S.inflight and not S.inflight.done) then
            refreshProfile();nextRead=os.clock()+1
            if S.profile and predicate(S.profile) then return true end
        end
        task.wait(0.1)
    end
    return false
end
local function uncertain(reason)
    S.purchaseBlocked=true;S.notice=reason.."; no automatic retry";Notify("Purchase pending",reason)
end
local function fire(remote,...) return pcall(remote.FireServer,remote,...) end
local function ownedCount(category,id) return Core.ownedCount(S.profile and S.profile.owned[category],id) end
local function claimUnlocked()
    for _,key in ipairs(Core.claimKeys(passData(),BP.Rewards,TargetTier)) do
        if not S.running or S.paused or blockedByVerification() or S.claimPending[key] then return false end
        local reward=BP.Rewards[key] or BP.Rewards[tonumber(key)];local before=ownedCount(reward.ItemType,reward.ItemID)
        status("Claiming tier "..key);S.claimPending[key]=true
        log("CLAIM_REQUEST",{tier=key,argumentType="string",item=reward.ItemID})
        local ok=fire(HW:WaitForChild("ClaimBattlePassReward"),key)
        local confirmed=ok and waitConfirm(function(p)
            return (p.event.ClaimedRewards or {})[key]==true or Core.ownedCount(p.owned[reward.ItemType],reward.ItemID)>before
        end)
        if not confirmed then S.notice="Tier "..key.." claim not confirmed; no automatic retry";Notify("Claim pending",S.notice,true);return false end
        if (passData().ClaimedRewards or {})[key]==true then S.claimPending[key]=nil end
        S.receipts=S.receipts+1
        Notify("Reward claimed","Tier "..key.." | "..Core.itemDisplay(reward.ItemID,Sync.Weapons[reward.ItemID]),true,Sync.Weapons[reward.ItemID]);task.wait(0.25)
        if S.claimPending[key] then return false end
    end
    return true
end
local function purchaseBatch()
    if Validation.NoSpending or S.purchaseBlocked or blockedByVerification() then return false end
    S.transaction=true;cancelMovement();status("Checking server balance")
    if not refreshProfile() or not S.running or S.paused or blockedByVerification() then S.transaction=false;return false end
    if Config.mode==1 then
        local count=Core.batch(balance(),Config.crateThreshold,CrateCost)
        for i=1,count do
            if not S.running or S.paused or blockedByVerification() or balance()<CrateCost then break end
            status(string.format("Opening crate %d/%d",i,count));local before=clone(S.profile.owned.Weapons)
            log("CRATE_REQUEST",{crate=CrateID,currency=Currency,balance=balance(),batch=count,index=i})
            local success,item=invoke(Shop:WaitForChild("OpenCrate"),table.pack(CrateID,"MysteryBox",Currency),Config.confirmTimeout)
            if not success or type(item)~="string" or not Sync.Weapons[item] then uncertain("Crate result not confirmed");break end
            local expected=Core.ownedCount(before,item)+1
            if not waitConfirm(function(p) return Core.ownedCount(p.owned.Weapons,item)>=expected end) then uncertain("Crate inventory not confirmed");break end
            if S.running then fire(Shop:WaitForChild("CrateComplete"),item) end
            S.receipts=S.receipts+1;Notify("Crate opened",Core.itemDisplay(item,Sync.Weapons[item]).." | "..CrateID,false,Sync.Weapons[item])
            local deadline=os.clock()+Config.openDelay
            while S.running and not S.paused and os.clock()<deadline do task.wait(0.05) end
        end
    else
        if not claimUnlocked() then S.transaction=false;return true end
        local tier=tonumber(passData().CurrentTier) or 0
        local count=Core.batch(balance(),Config.passThreshold,BP.TierCost,TargetTier-tier)
        if count>0 then
            local expected=tier+count;status("Buying "..count.." tiers")
            log("TIER_REQUEST",{count=count,before=tier,expected=expected,balance=balance()})
            local sent=fire(HW:WaitForChild("BuyBattlePassTiers"),count)
            if sent and waitConfirm(function(p) return (tonumber(p.event.CurrentTier) or 0)>=expected end) then
                S.receipts=S.receipts+1;Notify("Tiers purchased",tier.." -> "..passData().CurrentTier,true);claimUnlocked()
            else uncertain("Tier purchase not confirmed") end
        end
        if not S.purchaseBlocked and S.running and not S.paused and not blockedByVerification() and TargetTier>=BP.TotalTiers
            and (tonumber(passData().CurrentTier) or 0)>=BP.TotalTiers and Config.buyFinalReward then
            local finalWhen=math.max(tonumber(BP.FinalRewardCost) or math.huge,Config.finalRewardThreshold)
            if not S.finalPending and (tonumber(passData().FinalRewardClaimAmount) or 0)<1 and balance()>=finalWhen then
                status("Claiming final reward");local old=tonumber(passData().FinalRewardClaimAmount) or 0
                local before=ownedCount(BP.FinalRewardType,BP.FinalReward)
                S.finalPending=true
                local sent=fire(HW:WaitForChild("BuyBattlePassFinalReward"))
                local confirmed=sent and waitConfirm(function(p)
                    return (tonumber(p.event.FinalRewardClaimAmount) or 0)>old or Core.ownedCount(p.owned[BP.FinalRewardType],BP.FinalReward)>before
                end)
                if confirmed then S.receipts=S.receipts+1;Notify("Final reward claimed",Core.itemDisplay(BP.FinalReward,Sync.Weapons[BP.FinalReward]),true,Sync.Weapons[BP.FinalReward])
                else uncertain("Final reward not confirmed") end
            end
        end
    end
    S.transaction=false;return true
end
local function buildCompactUI()
    local coreGui=game:GetService("CoreGui")
    for _,parent in ipairs({coreGui,PlayerGui}) do
        for _,name in ipairs({"SkiderMM2Kaitun","SkiderMM2KaitunUI"}) do
            local old=parent:FindFirstChild(name,true)
            if old and old:IsA("ScreenGui") then old:Destroy() end
        end
    end
    local screen=Instance.new("ScreenGui")
    screen.Name="SkiderMM2Kaitun";screen.ResetOnSpawn=false;screen.DisplayOrder=50
    screen.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    local ok=pcall(function() screen.Parent=coreGui end)
    if not ok then screen.Parent=PlayerGui end
    local green=Color3.fromRGB(107,235,124)
    local function make(class,props,parent)
        local o=Instance.new(class);for k,v in pairs(props) do o[k]=v end;o.Parent=parent;return o
    end
    local main=make("Frame",{Name="Panel",Size=UDim2.fromOffset(360,370),Position=UDim2.fromOffset(24,140),
        BackgroundColor3=Color3.fromRGB(10,13,11),BorderSizePixel=0,Active=true},screen)
    make("UICorner",{CornerRadius=UDim.new(0,14)},main)
    make("UIStroke",{Color=Color3.fromRGB(42,76,49),Thickness=1},main)
    local bar=make("Frame",{Size=UDim2.new(1,-32,0,3),Position=UDim2.fromOffset(16,15),BackgroundColor3=green,BorderSizePixel=0},main)
    make("UICorner",{CornerRadius=UDim.new(1,0)},bar)
    local function label(name,text,x,y,w,h,size,color)
        return make("TextLabel",{Name=name,Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),Font=Enum.Font.FredokaOne,
            TextSize=size,TextColor3=color or Color3.fromRGB(236,245,238),TextXAlignment=Enum.TextXAlignment.Left,
            TextYAlignment=Enum.TextYAlignment.Center,BackgroundTransparency=1,TextTruncate=Enum.TextTruncate.AtEnd},main)
    end
    label("Title","Skider MM2 Kaitun",18,27,310,32,23,green)
    label("UserCaption","👤 USER",19,98,100,18,11,Color3.fromRGB(143,169,148))
    label("User",Player.Name,19,117,320,27,17)
    label("Mode",(Config.mode==1 and "📦 Mode: Crates" or "🏅 Mode: Battlepass"),19,146,320,20,13,green)
    label("CandyCaption","🍬 CANDIES",19,181,150,18,11,Color3.fromRGB(143,169,148))
    local candies=label("Candies","Loading",19,201,150,28,23,green)
    label("BagCaption","🎯 THIS ROUND",196,181,145,18,11,Color3.fromRGB(143,169,148))
    local bag=label("Bag","0/50",196,201,145,28,23)
    local state=label("Status","⚡ Status Farming : Starting",19,240,322,38,13,green)
    state.TextWrapped=true;state.TextTruncate=Enum.TextTruncate.None
    local info=label("Round","Lobby | Spectator | Tier 0",19,280,322,20,11,Color3.fromRGB(163,184,168))
    local elapsed=label("Elapsed","⏱️ Elapsed : 00:00:00",19,304,265,20,12)
    label("Brand","mtrchill.click",19,339,220,19,13,green)
    local pause=make("TextButton",{Text="PAUSE",Position=UDim2.fromOffset(272,333),Size=UDim2.fromOffset(69,26),Font=Enum.Font.FredokaOne,
        TextSize=11,TextColor3=green,BackgroundColor3=Color3.fromRGB(24,39,27),BorderSizePixel=0},main)
    make("UICorner",{CornerRadius=UDim.new(0,7)},pause)
    connect(pause.Activated,function() S.paused=not S.paused;cancelMovement();pause.Text=S.paused and "RESUME" or "PAUSE" end)
    local close=make("TextButton",{Text="x",Position=UDim2.fromOffset(326,32),Size=UDim2.fromOffset(19,21),Font=Enum.Font.FredokaOne,
        TextSize=15,BackgroundTransparency=1,TextColor3=Color3.fromRGB(140,165,146)},main)
    connect(close.Activated,function() API.Stop() end)
    local dragging,startInput,startPosition
    connect(main.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true;startInput=input.Position;startPosition=main.Position
        end
    end)
    connect(UIS.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    connect(UIS.InputChanged,function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local d=input.Position-startInput;main.Position=startPosition+UDim2.fromOffset(d.X,d.Y)
        end
    end)
    local bindings={
        SetCandies=function(total,thisRound) candies.Text=tostring(total);bag.Text=tostring(thisRound) end,
        SetStatus=function(text) state.Text="⚡ Status Farming : "..tostring(text) end,
        SetInfo=function(map,role,tier) info.Text="🗺️ "..tostring(map).." | "..tostring(role).." | 🏅 "..tostring(tier) end,
        SetElapsed=function(time,roundTime) elapsed.Text="⏱️ Elapsed : "..tostring(time);info.Text=info.Text.." | "..tostring(roundTime) end,
    }
    API.UI=bindings
    return screen,bindings
end
local function buildUI()
if not Config.fullscreenUI then return buildCompactUI() end
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Player
local function richText(value)
    return (tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
for _, parent in ipairs({CoreGui, PlayerGui}) do
    for _, name in ipairs({"SkiderMM2Kaitun", "SkiderMM2KaitunUI"}) do
        local old = parent:FindFirstChild(name, true)
        if old and old:IsA("ScreenGui") then old:Destroy() end
    end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SkiderMM2KaitunUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 50
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local success = pcall(function()
    ScreenGui.Parent = CoreGui
end)
if not success then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local BlackScreen = Instance.new("Frame")
BlackScreen.Name = "BlackScreen"
BlackScreen.Size = UDim2.new(1, 0, 1, 0)
BlackScreen.Position = UDim2.new(0, 0, 0, 0)
BlackScreen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
BlackScreen.BorderSizePixel = 0
BlackScreen.Parent = ScreenGui

local CenterContainer = Instance.new("Frame")
CenterContainer.Name = "CenterContainer"
CenterContainer.Size = UDim2.new(0, 800, 0, 520)
CenterContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
CenterContainer.AnchorPoint = Vector2.new(0.5, 0.5)
CenterContainer.BackgroundTransparency = 1
CenterContainer.Parent = BlackScreen

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = CenterContainer
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 14)

local function CreateText(order, text, size, color)
    local label = Instance.new("TextLabel")
    label.LayoutOrder = order
    label.Size = UDim2.new(1, 0, 0, size + 6)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.FredokaOne
    label.Text = text
    label.TextSize = size
    label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    label.RichText = true
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = CenterContainer
    return label
end

local TitleLabel = CreateText(
    1,
    "🔪 Skider MM2 Kaitun 🎃",
    44,
    Color3.fromRGB(85, 255, 127)
)

local playerName = LocalPlayer and LocalPlayer.Name or "Player"
local UsernameLabel = CreateText(
    2,
    '👤 Username : <font color="#55ff7f">' .. richText(playerName) .. '</font>',
    22,
    Color3.fromRGB(220, 220, 220)
)

local ModeLabel = CreateText(
    3,
    'Mode: <font color="#55ff7f">' .. (Config.mode == 1 and "Crates" or "Battlepass") .. '</font>',
    22,
    Color3.fromRGB(220, 220, 220)
)
ModeLabel.Name = "Mode"

local CandyRow = Instance.new("Frame")
CandyRow.LayoutOrder = 4
CandyRow.Size = UDim2.new(0, 560, 0, 75)
CandyRow.BackgroundTransparency = 1
CandyRow.Parent = CenterContainer

local CandiesLabel = Instance.new("TextLabel")
CandiesLabel.Size = UDim2.new(0.5, 0, 1, 0)
CandiesLabel.Position = UDim2.new(0, 0, 0, 0)
CandiesLabel.BackgroundTransparency = 1
CandiesLabel.Font = Enum.Font.FredokaOne
CandiesLabel.RichText = true
CandiesLabel.Text = '🍬 Candies\n<font size="34" color="#55ff7f">0</font>'
CandiesLabel.TextSize = 18
CandiesLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
CandiesLabel.Parent = CandyRow

local CandiesRoundLabel = Instance.new("TextLabel")
CandiesRoundLabel.Size = UDim2.new(0.5, 0, 1, 0)
CandiesRoundLabel.Position = UDim2.new(0.5, 0, 0, 0)
CandiesRoundLabel.BackgroundTransparency = 1
CandiesRoundLabel.Font = Enum.Font.FredokaOne
CandiesRoundLabel.RichText = true
CandiesRoundLabel.Text = '🎯 Candies This Round\n<font size="34" color="#ffffff">0/50</font>'
CandiesRoundLabel.TextSize = 18
CandiesRoundLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
CandiesRoundLabel.Parent = CandyRow

local StatusLabel = CreateText(
    5,
    '⚡ Status Farming : <font color="#55ff7f">Waiting for next round...</font>',
    22,
    Color3.fromRGB(255, 255, 255)
)

local MapRoleTierLabel = CreateText(
    6,
    '🗺️ Map : <font color="#ffaa00">Lobby</font>   ;   🎭 Role : <font color="#00ffff">None</font>   ;   🏆 Tier Battlepass : <font color="#ff55ff">0/30</font>',
    20,
    Color3.fromRGB(200, 200, 200)
)

local TimeLabel = CreateText(
    7,
    '⏱️ Total time elapsed : <font color="#ffff55">00:00:00</font>',
    22,
    Color3.fromRGB(255, 255, 255)
)

local WebLabel = CreateText(
    8,
    "🌐 mtrchill.click",
    20,
    Color3.fromRGB(85, 255, 127)
)

StatusLabel.Size = UDim2.new(1, 0, 0, 50)
StatusLabel.TextWrapped = true
MapRoleTierLabel.TextScaled = true
TimeLabel.TextScaled = true
local timeSize = Instance.new("UITextSizeConstraint")
timeSize.MinTextSize = 14
timeSize.MaxTextSize = 22
timeSize.Parent = TimeLabel
local infoSize = Instance.new("UITextSizeConstraint")
infoSize.MinTextSize = 12
infoSize.MaxTextSize = 20
infoSize.Parent = MapRoleTierLabel
local scale = Instance.new("UIScale")
scale.Parent = CenterContainer
local function resize()
    local size = BlackScreen.AbsoluteSize
    scale.Scale = math.max(0.1, math.min(1, (size.X - 24) / 800, (size.Y - 24) / 520))
end
connect(BlackScreen:GetPropertyChangedSignal("AbsoluteSize"), resize)
resize()
local bindings = {
    SetCandies = function(total, thisRound)
        CandiesLabel.Text = '🍬 Candies\n<font size="34" color="#55ff7f">' .. richText(total) .. '</font>'
        CandiesRoundLabel.Text = '🎯 Candies This Round\n<font size="34" color="#ffffff">' .. richText(thisRound) .. '</font>'
    end,
    SetStatus = function(statusText)
        StatusLabel.Text = '⚡ Status Farming : <font color="#55ff7f">' .. richText(statusText) .. '</font>'
    end,
    SetInfo = function(mapName, roleName, tierText)
        MapRoleTierLabel.Text = string.format(
            '🗺️ Map : <font color="#ffaa00">%s</font>   ;   🎭 Role : <font color="#00ffff">%s</font>   ;   🏆 Tier Battlepass : <font color="#ff55ff">%s</font>',
            richText(mapName), richText(roleName), richText(tierText)
        )
    end,
    SetElapsed = function(elapsed, roundTime)
        TimeLabel.Text = '⏱️ Total time elapsed : <font color="#ffff55">' .. richText(elapsed) .. '</font>   |   Round Time : ' .. richText(roundTime)
    end,
}
API.UI = bindings
return ScreenGui, bindings
end
function API.Stop()
    if not S.running then
        if FpsBoost then FpsBoost.Stop() end
        return
    end
    S.running=false;cancelMovement();Context.abortReset()
    if FpsBoost then FpsBoost.Stop();FpsBoost=nil end
    for _,c in ipairs(S.connections) do c:Disconnect() end
    if Ui then Ui:Destroy() end
    log("STOP",{receipts=S.receipts})
end
function API.Snapshot()
    return {running=S.running,paused=S.paused,status=S.status,notice=S.notice,bag=S.bag,maxBag=S.maxBag,balance=balance(),
        tier=passData().CurrentTier,targetTier=TargetTier,map=findMap() and S.map.Name or "Lobby",eligible=not blockedByVerification(),
        canFarm=canFarm(),mode=Config.mode,receipts=S.receipts,errors=S.errors,purchaseBlocked=S.purchaseBlocked,webhook=S.webhookStatus,
        available=S.available,collected=S.collected,role=metrics(false).role,base="scripts/01_auto_candy_farm.lua",
        config={crateThreshold=Config.crateThreshold,passThreshold=Config.passThreshold,speed=Config.speed,openDelay=Config.openDelay}}
end
function API.SetPaused(value) S.paused=value==true;cancelMovement() end
if type(STATE)=="table" and type(STATE.onCleanup)=="function" then STATE.onCleanup(API.Stop);STATE.api=API end
pcall(function()
    local old=game:GetService("CoreGui"):FindFirstChild("MM2CandyUI")
    if old then old:Destroy() end
end)
if typeof(setfpscap)=="function" then pcall(setfpscap,Config.fps) end
Ui,Labels=buildUI()

applyProfile(LoadModule(BootChild(BootChild(RS,"Modules"),"ProfileData")))
local bagGui=PlayerGui:FindFirstChild("MainGUI")
bagGui=bagGui and bagGui:FindFirstChild("Game");bagGui=bagGui and bagGui:FindFirstChild("CoinBags")
bagGui=bagGui and bagGui:FindFirstChild("Container");bagGui=bagGui and bagGui:FindFirstChild("Candy")
if bagGui then local currency=bagGui:FindFirstChild("CurrencyFrame");local icon=currency and currency:FindFirstChild("Icon");local n=icon and icon:FindFirstChild("Coins");if n and n:IsA("TextLabel") then S.bag=tonumber(n.Text) or 0;Context.setBag(S.bag) end end
connect(BootChild(Inventory,"ChangeProfileData").OnClientEvent,function(key,value)
    if S.profile and key==Event.Title and type(value)=="table" then S.profile.event=clone(value);S.profileAt=os.clock() end
end)
connect(BootChild(Inventory,"ChangeInventoryItem").OnClientEvent,function(category,id,amount)
    if not S.profile then return end
    if category=="Weapons" then S.itemsDirty=true end
    if category=="Materials" or category=="Weapons" or category=="Pets" then
        S.profile.owned[category]=S.profile.owned[category] or {};S.profile.owned[category][id]=tonumber(amount) or 0
        if category=="Materials" then S.profile.materials=S.profile.owned.Materials end
    elseif tonumber(amount) and amount>0 then
        S.profile.owned[category]=S.profile.owned[category] or {}
        if Core.ownedCount(S.profile.owned[category],id)==0 then table.insert(S.profile.owned[category],id) end
    end
end)
connect(BootChild(Gameplay,"CoinCollected").OnClientEvent,function(id,amount,maximum)
    if id=="Candy" then
        local new=tonumber(amount) or S.bag
        S.collected=S.collected+math.max(0,new-S.bag)
        S.bag=new;S.maxBag=tonumber(maximum) or S.maxBag
        log("CANDY_COLLECTED",{bag=S.bag,maxBag=S.maxBag})
    end
end)
connect(BootChild(Gameplay,"CoinsStarted").OnClientEvent,function(data)
    S.epoch=S.epoch+1;S.waiting=false;S.ended=false;S.failed={};S.bag=0;cancelMovement()
    local candy=type(data)=="table" and data.Candy
    if type(candy)=="table" then S.bag=tonumber(candy.CollectedAmount) or 0;S.maxBag=tonumber(candy.CollectionLimit) or S.maxBag;Context.setBag(S.bag,S.maxBag) end
    Notify("Round started","A new round is available")
end)
connect(BootChild(Gameplay,"RoundStart").OnClientEvent,function() S.ended=false;cancelMovement() end)
for _,name in ipairs({"GameOver","RoundEndFade","VictoryScreen"}) do
    local remote=Gameplay:FindFirstChild(name)
    if remote then connect(remote.OnClientEvent,function()
        if not S.ended then Notify("Round ended",S.bag.."/"..S.maxBag.." candies collected") end
        S.ended=true;cancelMovement()
    end) end
end
local roundCheckPending=false
connect(BootChild(Gameplay,"PlayerDataChanged").OnClientEvent,function()
    if roundCheckPending then return end
    roundCheckPending=true
    task.defer(function()
        roundCheckPending=false
        if S.running and not canFarm() then cancelMovement() end
    end)
end)
connect(Player:GetAttributeChangedSignal("Alive"),function() if not canFarm() then cancelMovement() end end)
connect(Player:GetAttributeChangedSignal("Authenticated"),cancelMovement)
connect(Player.CharacterAdded,cancelMovement)
task.spawn(function()
    while S.running or #S.logQueue>0 do
        if #S.logQueue>0 then
            local text=table.concat(S.logQueue);S.logQueue={}
            if typeof(appendfile)=="function" then
                local ok=pcall(appendfile,"Skider_MM2_Kaitun.log",text)
                if not ok then  end
            end
        end
        task.wait(0.5)
    end
end)
task.spawn(function()
    local requestFn=typeof(request)=="function" and request or (typeof(http_request)=="function" and http_request or nil)
    while S.running do
        if #S.webhookQueue>0 and requestFn and not blockedByVerification() then
            local payload=table.remove(S.webhookQueue,1)
            for _=1,3 do
                if not S.running then break end
                local ok,response=pcall(requestFn,{Url=Config.webhook.url,Method="POST",Headers={["Content-Type"]="application/json"},Body=Http:JSONEncode(payload)})
                local code=ok and type(response)=="table" and tonumber(response.StatusCode) or 0
                if code>=200 and code<300 then S.webhookStatus="Sent";break end
                if code==429 then
                    local decodeOK,body=pcall(Http.JSONDecode,Http,type(response.Body)=="string" and response.Body or "{}")
                    local waitFor=decodeOK and tonumber(body.retry_after) or 5
                    S.webhookStatus="Rate limited";task.wait(math.min(math.max(waitFor or 5,1),30))
                else S.webhookStatus="HTTP "..code;log("WEBHOOK_FAILED",{status=code});break end
            end
            task.wait(1.5)
        else
            if not requestFn and Config.webhook.enabled then S.webhookStatus="HTTP API unavailable" end
            task.wait(0.5)
        end
    end
end)
task.spawn(function()
    local last={}
    while S.running do
        local m=metrics(false)
        if m.candies~=last.candies or m.bag~=last.bag then Labels.SetCandies(m.candies,m.bag) end
        local shownStatus=blockedByVerification() and "Required Buy/Premium Or Verification Age" or S.paused and "Paused" or S.status
        if S.notice~="" and not blockedByVerification() then shownStatus=S.notice end
        if shownStatus~=last.status then Labels.SetStatus(shownStatus) end
        if m.map~=last.map or m.role~=last.role or m.tier~=last.tier
            or m.elapsed~=last.elapsed or m.roundTime~=last.roundTime then
            Labels.SetInfo(m.map,m.role,m.tier)
            Labels.SetElapsed(m.elapsed,m.roundTime)
        end
        last=m;last.status=shownStatus
        task.wait(0.5)
    end
end)
Notify("Started","Mode "..Config.mode.." | "..(Config.mode==1 and "Crates" or "Battle Pass"))
local function beforeCycle()
    syncBase()

            if blockedByVerification() then cancelMovement();Context.abortReset();status("Required Buy/Premium Or Verification Age");task.wait(0.5);return false end
            if S.paused then status("Paused");task.wait(0.3);return false end
            if not S.profile then status("Loading server profile");if not refreshProfile() then task.wait(2) end;return false end
            if os.clock()-S.lastProfileRead>60 and not (S.inflight and not S.inflight.done) then refreshProfile() end
            if os.clock()-S.lastWebhook>Config.webhook.interval then S.lastWebhook=os.clock();Notify("Account status",S.status) end
            if S.completed then status("Completed");task.wait(1);return false end
            for key in pairs(S.claimPending) do
                if (passData().ClaimedRewards or {})[key]==true then S.claimPending[key]=nil;S.notice="";Notify("Reward claimed","Tier "..key,true) end
            end
            if S.finalPending and (tonumber(passData().FinalRewardClaimAmount) or 0)<1 then status("Waiting for final reward confirmation");task.wait(1);return false end
            if Config.mode==2 and next(S.claimPending) then status("Waiting for claim confirmation");task.wait(1);return false end
            if not Validation.NoSpending and not S.purchaseBlocked then
                local tier=tonumber(passData().CurrentTier) or 0
                local claims=Config.mode==2 and Core.claimKeys(passData(),BP.Rewards,TargetTier) or {}
                local count=Config.mode==1 and Core.batch(balance(),Config.crateThreshold,CrateCost)
                    or Core.batch(balance(),Config.passThreshold,BP.TierCost,TargetTier-tier)
                local finalReady=Config.mode==2 and TargetTier>=BP.TotalTiers and Config.buyFinalReward and tier>=BP.TotalTiers
                    and (tonumber(passData().FinalRewardClaimAmount) or 0)<1
                    and balance()>=math.max(tonumber(BP.FinalRewardCost) or math.huge,Config.finalRewardThreshold)
                if count>0 or #claims>0 or finalReady then purchaseBatch() end
                if Config.mode==2 and (tonumber(passData().CurrentTier) or 0)>=TargetTier and #Core.claimKeys(passData(),BP.Rewards,TargetTier)==0
                    and (TargetTier<BP.TotalTiers or not Config.buyFinalReward or (tonumber(passData().FinalRewardClaimAmount) or 0)>0) then
                    S.completed=true;Notify("Completed","Battle Pass target reached",true);return false
                end
            end

    if canFarm() then
        status(Context.snapshot().moving and "Moving to candy" or "Collecting candies")
        Context.config.AutoCandy=true
        return true
    end
    cancelMovement()
    status(Validation.NoMovement and "Validation: movement disabled" or S.waiting and "Waiting for next round" or "Waiting to join a round")
    return false
end
function API.BeforeCycle()
    if not S.running then return false end
    local ok,allowed=pcall(beforeCycle)
    if not ok then
        if S.transaction then S.purchaseBlocked=true;S.notice="Transaction interrupted; no automatic retry"
        else S.notice="Client error; see local log" end
        S.transaction=false;cancelMovement();S.errors=S.errors+1
        log("MAIN_ERROR",{message=tostring(allowed)});task.wait(2)
        return false
    end
    return allowed==true
end

task.spawn(function()
    local nextCount=0
    while S.running do
        local base=syncBase()
        if not canFarm() or S.completed then
            if Context.config.AutoCandy or base.moving then cancelMovement() end
        end
        if blockedByVerification() then Context.abortReset() end
        if os.clock()>=nextCount then
            local count=0
            for index,coin in ipairs(Collection:GetTagged("ServerCoinPart")) do
                if not S.running then return end
                if Context.validCandy(coin) then count=count+1 end
                if index%32==0 then task.wait() end
            end
            S.available=count
            nextCount=os.clock()+1
        end
        task.wait(0.5)
    end
end)
API.Connect=connect
API.Gui=Ui
API.CanFarm=canFarm
API.MovementError=function(message) log("MOVEMENT_ERROR",{message=tostring(message)}) end
log("READY",{mode=Config.mode,crate=CrateID,crateThreshold=Config.crateThreshold,passThreshold=Config.passThreshold,targetTier=TargetTier,speed=Config.speed,
    validation={movement=Validation.NoMovement==true,spending=Validation.NoSpending==true}})

if Config.fpsBoost then
    task.delay(10,function()
        if not S.running or Env.SkiderMM2Boot~=Boot or Env.SkiderMM2~=API then return end
        local ok,boost=pcall(AttachFPSBoost)
        if ok then FpsBoost=boost
        else log("FPS_BOOST_ERROR",{message=tostring(boost)}) end
    end)
end

return API

end

end)()
WaitGameReady()
if type(Env.SkiderMM2)=="table" and type(Env.SkiderMM2.Stop)=="function" then pcall(Env.SkiderMM2.Stop) end
if type(Env.MM2CandyConfig)=="table" then Env.MM2CandyConfig.AutoCandy=false end

AwaitBoot(function() return game:IsLoaded() end,"game loaded")

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local Player = AwaitBoot(function() return Players.LocalPlayer end,"LocalPlayer")
AwaitBoot(function() return Player.Character end,"Character")
BootChild(Player,"PlayerGui")

local Config = {
    AutoCandy = false,
    Stabilizer = true,
    TweenSpeed = 120,
    CollectDelay = 1,
    ResetDelay = 2,
    YOffset = 1.8,
    SafeTween = true,
    SegmentDistance = 10,
    SegmentDelay = 0.03,
    CollectTimeout = 4,
    FailedTargetDelay = 3,
    FinalDistance = 5,
    FinalSpeed = 28,
    FinalHold = 0.18,
    TouchSweep = true,
    SweepDistance = 0.28,
    SweepSpeed = 14,
    StabilizerResponsiveness = 35,
    StabilizerTorqueMultiplier = 4500,
}

local Settings = Core.config(Env.ConfigKaitunMM2Hallowen2026,Env.ModeFarming,Env.Fpslock)
local EffectiveFPS = math.max(1,tonumber(Settings.fps) or 60)
local LowFPS = EffectiveFPS <= 10
local FrameTime = 1 / EffectiveFPS
Config.TweenSpeed=Settings.speed
Config.CollectDelay=Settings.collectDelay
Config.ResetDelay=Settings.resetDelay
Config.SegmentDistance=LowFPS and math.clamp(Config.TweenSpeed / EffectiveFPS,18,36) or math.min(Settings.segment,10)
Config.SegmentDelay=LowFPS and 0 or Config.SegmentDelay
if LowFPS then
    Config.FinalDistance=8
    Config.FinalSpeed=math.min(Config.FinalSpeed,math.max(16,EffectiveFPS*4))
    Config.FinalHold=math.max(Config.FinalHold,FrameTime*2)
    Config.SweepDistance=0.55
    Config.SweepSpeed=math.min(Config.SweepSpeed,10)
    Config.StabilizerResponsiveness=50
    Config.StabilizerTorqueMultiplier=6000
end
Env.MM2CandyConfig = Config

local Remotes = BootChild(ReplicatedStorage,"Remotes")
local Gameplay = BootChild(Remotes,"Gameplay")
local CoinCollected = BootChild(Gameplay,"CoinCollected")
local CoinsStarted = BootChild(Gameplay,"CoinsStarted")

local CurrentBag = 0
local MaxBag = 50

local IsMoving = false
local CurrentTween = nil
local CurrentTarget = nil
local MoveGeneration = 0
local StabilizerData = nil
local Addon

local WaitingNextRound = false
local ResettingCharacter = false

local FailedTargets =
    setmetatable({}, {
        __mode = "k"
    })

local function GetCharacter()
    local Character =
        Player.Character

    if not Character then
        return
    end

    local Humanoid =
        Character:
        FindFirstChildOfClass(
            "Humanoid"
        )

    local Root =
        Character:
        FindFirstChild(
            "HumanoidRootPart"
        )

    if not Humanoid
        or not Root
        or Humanoid.Health <= 0 then

        return
    end

    return Character,
        Humanoid,
        Root
end

local function MovementAllowed(
    Token,
    Character
)
    if Token ~= MoveGeneration
        or not Config.AutoCandy
        or WaitingNextRound then

        return false
    end

    local Current,
        Humanoid,
        Root =
        GetCharacter()

    if not Current
        or not Humanoid
        or not Root
        or Current ~= Character then

        return false
    end

    if not Addon then
        return false
    end

    if type(Addon.CanFarm) == "function"
        and not Addon.CanFarm() then

        return false
    end

    return true
end

local function CleanupStabilizer()
    local Data =
        StabilizerData

    StabilizerData =
        nil

    if not Data then
        return
    end

    if Data.Connection then
        pcall(function()
            Data.Connection:
                Disconnect()
        end)
    end

    if Data.Humanoid
        and Data.Humanoid.Parent then

        pcall(function()
            Data.Humanoid.AutoRotate =
                Data.AutoRotate
        end)

        pcall(function()
            Data.Humanoid.PlatformStand =
                false
        end)
    end

    if Data.Align then
        pcall(function()
            Data.Align:
                Destroy()
        end)
    end

    if Data.Attachment then
        pcall(function()
            Data.Attachment:
                Destroy()
        end)
    end
end

local function BuildOrientation(
    Root,
    Target
)
    local Direction =
        Target
        - Root.Position

    local Flat =
        Vector3.new(
            Direction.X,
            0,
            Direction.Z
        )

    if Flat.Magnitude
        < 0.05 then

        local Look =
            Root.CFrame.LookVector

        Flat =
            Vector3.new(
                Look.X,
                0,
                Look.Z
            )
    end

    if Flat.Magnitude
        < 0.05 then

        Flat =
            Vector3.new(
                0,
                0,
                -1
            )

    else

        Flat =
            Flat.Unit
    end

    return CFrame.lookAt(
        Vector3.zero,
        Flat,
        Vector3.yAxis
    )
end

local function StartStabilizer(
    Root,
    Target
)
    if not Config.Stabilizer then
        return
    end

    local Character,
        Humanoid,
        CurrentRoot =
        GetCharacter()

    if not Character
        or not Humanoid
        or CurrentRoot ~= Root then

        return
    end

    if StabilizerData
        and StabilizerData.Root
            == Root then

        StabilizerData.Align.CFrame =
            BuildOrientation(
                Root,
                Target
            )

        return
    end

    CleanupStabilizer()

    local Attachment =
        Instance.new(
            "Attachment"
        )

    Attachment.Name =
        "MM2TweenStabilizerAttachment"

    Attachment.Parent =
        Root

    local Align =
        Instance.new(
            "AlignOrientation"
        )

    Align.Name =
        "MM2TweenStabilizer"

    Align.Mode =
        Enum.OrientationAlignmentMode.OneAttachment

    Align.Attachment0 =
        Attachment

    Align.RigidityEnabled =
        false

    Align.ReactionTorqueEnabled =
        false

    Align.Responsiveness =
        Config.StabilizerResponsiveness

    Align.MaxAngularVelocity =
        10

    Align.MaxTorque =
        math.max(
            40000,
            Root.AssemblyMass
            * Config.StabilizerTorqueMultiplier
        )

    Align.CFrame =
        BuildOrientation(
            Root,
            Target
        )

    Align.Parent =
        Root

    local OldAutoRotate =
        Humanoid.AutoRotate

    Humanoid.AutoRotate =
        false

    Humanoid.PlatformStand =
        false

    if Humanoid.Sit then
        Humanoid.Sit =
            false
    end

    if Root.Anchored then
        Root.Anchored =
            false
    end

    local Data = {
        Root = Root,
        Humanoid = Humanoid,
        AutoRotate = OldAutoRotate,
        Attachment = Attachment,
        Align = Align
    }

    StabilizerData =
        Data

    Data.Connection =
        RunService.Heartbeat:
        Connect(function()
            if StabilizerData
                ~= Data then

                return
            end

            if not Config.Stabilizer
                or not IsMoving then

                return
            end

            if not Root
                or not Root.Parent
                or not Humanoid
                or not Humanoid.Parent
                or Humanoid.Health <= 0 then

                return
            end

            if Root.Anchored then
                Root.Anchored =
                    false
            end

            if Humanoid.PlatformStand then
                Humanoid.PlatformStand =
                    false
            end

            if Humanoid.Sit then
                Humanoid.Sit =
                    false
            end

            Root.AssemblyAngularVelocity =
                Vector3.zero
        end)
end

local function CancelTween()
    MoveGeneration += 1

    if CurrentTween then
        pcall(function()
            CurrentTween:
                Cancel()
        end)

        CurrentTween =
            nil
    end

    CleanupStabilizer()

    IsMoving =
        false

    CurrentTarget =
        nil
end

local function IsValidCandy(
    Object
)
    if not Object
        or not Object.Parent then

        return false
    end

    if not Object:IsA(
        "BasePart"
    ) then

        return false
    end

    if not Object:IsDescendantOf(
        workspace
    ) then

        return false
    end

    if not CollectionService:
        HasTag(
            Object,
            "ServerCoinPart"
        ) then

        return false
    end

    if Object:GetAttribute(
        "CoinID"
    ) ~= "Candy" then

        return false
    end

    if Object:GetAttribute(
        "Collected"
    ) == true then

        return false
    end

    return true
end

local function GetNearestCandy()
    local _, _, Root =
        GetCharacter()

    if not Root then
        return
    end

    local Closest =
        nil

    local ClosestDistance =
        math.huge

    for Index, Candy in ipairs(
        CollectionService:
        GetTagged(
            "ServerCoinPart"
        )
    ) do
        if IsValidCandy(
            Candy
        ) then
            local IgnoreUntil =
                FailedTargets[
                    Candy
                ]

            if not IgnoreUntil
                or os.clock()
                    >= IgnoreUntil then

                local Distance =
                    (
                        Root.Position
                        - Candy.Position
                    ).Magnitude

                if Distance
                    < ClosestDistance then

                    Closest =
                        Candy

                    ClosestDistance =
                        Distance
                end
            end
        end
        if Index%32 == 0 then
            task.wait()
            if not Config.AutoCandy then return end
        end
    end

    local _, _, CurrentRoot = GetCharacter()
    if CurrentRoot ~= Root then return end
    if Closest and not IsValidCandy(Closest) then return end
    return Closest,
        ClosestDistance
end

local function MovementConfirmed(
    Candy,
    OldBag
)
    return not Candy
        or not Candy.Parent
        or Candy:GetAttribute(
            "Collected"
        ) == true
        or CurrentBag > OldBag
end

local function BuildTweenCFrame(
    Root,
    Position
)
    local Direction =
        Position
        - Root.Position

    local Flat =
        Vector3.new(
            Direction.X,
            0,
            Direction.Z
        )

    if Flat.Magnitude
        < 0.01 then

        local Look =
            Root.CFrame.LookVector

        Flat =
            Vector3.new(
                Look.X,
                0,
                Look.Z
            )
    end

    if Flat.Magnitude
        < 0.01 then

        Flat =
            Vector3.new(
                0,
                0,
                -1
            )

    else

        Flat =
            Flat.Unit
    end

    return CFrame.lookAt(
        Position,
        Position + Flat
    )
end

local function TweenSegment(
    Root,
    Position,
    Speed,
    Token,
    Character,
    MinimumDuration
)
    if not Root
        or not Root.Parent then

        return false
    end

    if not MovementAllowed(
        Token,
        Character
    ) then

        return false
    end

    local Distance =
        (
            Root.Position
            - Position
        ).Magnitude

    if Distance <= 0.1 then
        return true
    end

    local MoveSpeed =
        math.max(
            tonumber(Speed)
            or Config.TweenSpeed,
            1
        )

    local DefaultMinimum =
        LowFPS
        and FrameTime * 0.9
        or 0.05

    local Duration =
        math.max(
            Distance
            / MoveSpeed,
            tonumber(MinimumDuration)
            or DefaultMinimum
        )

    if Config.Stabilizer then
        StartStabilizer(
            Root,
            Position
        )

        if StabilizerData
            and StabilizerData.Align then

            StabilizerData.Align.CFrame =
                BuildOrientation(
                    Root,
                    Position
                )
        end

        Root.AssemblyAngularVelocity =
            Vector3.zero

    else

        CleanupStabilizer()

        Root.AssemblyLinearVelocity =
            Vector3.zero

        Root.AssemblyAngularVelocity =
            Vector3.zero
    end

    local Tween =
        TweenService:
        Create(
            Root,
            TweenInfo.new(
                Duration,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out
            ),
            {
                CFrame =
                    BuildTweenCFrame(
                        Root,
                        Position
                    )
            }
        )

    CurrentTween =
        Tween

    Tween:Play()

    local PlaybackState =
        Tween.Completed:
        Wait()

    if CurrentTween
        == Tween then

        CurrentTween =
            nil
    end

    if PlaybackState
        == Enum.PlaybackState.Cancelled then

        return false
    end

    if not MovementAllowed(
        Token,
        Character
    ) then

        return false
    end

    return true
end

local function TouchSweep(
    Candy,
    Token,
    Character,
    OldBag
)
    if not Config.Stabilizer
        or not Config.TouchSweep
        or not IsValidCandy(
            Candy
        ) then

        return true
    end

    local _, _, Root =
        GetCharacter()

    if not Root then
        return false
    end

    local Center =
        Candy.Position
        + Vector3.new(
            0,
            Config.YOffset,
            0
        )

    local Right =
        Root.CFrame.RightVector

    local Forward =
        Root.CFrame.LookVector

    Right =
        Vector3.new(
            Right.X,
            0,
            Right.Z
        )

    Forward =
        Vector3.new(
            Forward.X,
            0,
            Forward.Z
        )

    if Right.Magnitude > 0 then
        Right = Right.Unit
    else
        Right = Vector3.xAxis
    end

    if Forward.Magnitude > 0 then
        Forward = Forward.Unit
    else
        Forward = Vector3.zAxis
    end

    local D =
        Config.SweepDistance

    local Points

    if LowFPS then
        Points = {
            Center + Right * D,
            Center - Right * D,
            Center
        }
    else
        Points = {
            Center,
            Center + Right * D,
            Center - Right * D,
            Center + Forward * D,
            Center - Forward * D,
            Center
        }
    end

    for _, Position in ipairs(
        Points
    ) do
        if not MovementAllowed(
            Token,
            Character
        ) then

            return false
        end

        if MovementConfirmed(
            Candy,
            OldBag
        ) then

            return true
        end

        if not IsValidCandy(
            Candy
        ) then

            return true
        end

        local CurrentCharacter,
            _,
            CurrentRoot =
            GetCharacter()

        if CurrentCharacter ~= Character
            or not CurrentRoot then

            return false
        end

        local Success =
            TweenSegment(
                CurrentRoot,
                Position,
                Config.SweepSpeed,
                Token,
                Character,
                LowFPS and FrameTime * 0.85 or nil
            )

        if not Success then
            return false
        end
    end

    if Config.FinalHold > 0 then
        local Start =
            os.clock()

        while MovementAllowed(
            Token,
            Character
        )
            and os.clock()
                - Start
                < Config.FinalHold do

            if MovementConfirmed(
                Candy,
                OldBag
            ) then

                return true
            end

            task.wait(0.03)
        end
    end

    return true
end

local function SafeTweenTo(
    Candy
)
    local Character,
        _,
        Root =
        GetCharacter()

    if not Character
        or not Root
        or not IsValidCandy(
            Candy
        ) then

        return false
    end

    MoveGeneration += 1

    local Token =
        MoveGeneration

    IsMoving =
        true

    CurrentTarget =
        Candy

    local OldBag =
        CurrentBag

    local Success =
        true

    while MovementAllowed(
        Token,
        Character
    )
        and Candy
        and Candy.Parent
        and IsValidCandy(
            Candy
        ) do

        if MovementConfirmed(
            Candy,
            OldBag
        ) then

            break
        end

        local CurrentCharacter,
            _,
            CurrentRoot =
            GetCharacter()

        if CurrentCharacter ~= Character
            or not CurrentRoot then

            Success =
                false

            break
        end

        Root =
            CurrentRoot

        local FinalPosition =
            Candy.Position
            + Vector3.new(
                0,
                Config.YOffset,
                0
            )

        local Delta =
            FinalPosition
            - Root.Position

        local Distance =
            Delta.Magnitude

        if Distance <= 2.2 then
            break
        end

        local TargetPosition

        if Distance
            > Config.FinalDistance then

            local StepDistance =
                math.min(
                    Config.SegmentDistance,
                    math.max(
                        Distance
                        - Config.FinalDistance,
                        0.5
                    )
                )

            TargetPosition =
                Root.Position
                + Delta.Unit
                * StepDistance

        else

            TargetPosition =
                FinalPosition
        end

        local MoveSpeed =
            Config.TweenSpeed

        local MinimumDuration =
            nil

        if Config.Stabilizer
            and Distance
                <= Config.FinalDistance then

            MoveSpeed =
                math.min(
                    MoveSpeed,
                    Config.FinalSpeed
                )

            if LowFPS then
                MinimumDuration =
                    FrameTime * 2.25
            end
        end

        Success =
            TweenSegment(
                Root,
                TargetPosition,
                MoveSpeed,
                Token,
                Character,
                MinimumDuration
            )

        if not Success then
            break
        end

        if MovementConfirmed(
            Candy,
            OldBag
        ) then
            break
        end

        if not MovementAllowed(
            Token,
            Character
        ) then

            Success =
                false

            break
        end

        if Config.SegmentDelay > 0 then
            task.wait(
                Config.SegmentDelay
            )
        end
    end

    if Success
        and MovementAllowed(
            Token,
            Character
        )
        and IsValidCandy(
            Candy
        )
        and not MovementConfirmed(
            Candy,
            OldBag
        ) then

        local CurrentCharacter,
            _,
            Root2 =
            GetCharacter()

        if CurrentCharacter == Character
            and Root2 then

            local Final =
                Candy.Position
                + Vector3.new(
                    0,
                    Config.YOffset,
                    0
                )

            local FinalSpeed =
                Config.Stabilizer
                and math.min(
                    Config.TweenSpeed,
                    Config.FinalSpeed
                )
                or Config.TweenSpeed

            Success =
                TweenSegment(
                    Root2,
                    Final,
                    FinalSpeed,
                    Token,
                    Character,
                    LowFPS and FrameTime * 2.25 or nil
                )

            if Success
                and LowFPS
                and not MovementConfirmed(
                    Candy,
                    OldBag
                ) then

                local ConfirmUntil =
                    os.clock()
                    + FrameTime * 1.25

                while MovementAllowed(
                    Token,
                    Character
                )
                    and os.clock()
                        < ConfirmUntil
                    and not MovementConfirmed(
                        Candy,
                        OldBag
                    ) do

                    RunService.Heartbeat:
                        Wait()
                end
            end

            if Success
                and not MovementConfirmed(
                    Candy,
                    OldBag
                )
                and Config.Stabilizer then

                Success =
                    TouchSweep(
                        Candy,
                        Token,
                        Character,
                        OldBag
                    )
            end
        end
    end

    if Token == MoveGeneration then
        if CurrentTween then
            pcall(function()
                CurrentTween:
                    Cancel()
            end)

            CurrentTween =
                nil
        end

        CleanupStabilizer()

        IsMoving =
            false

        CurrentTarget =
            nil
    end

    if not Success
        and Candy
        and Candy.Parent
        and IsValidCandy(
            Candy
        ) then

        FailedTargets[
            Candy
        ] =
            os.clock()
            + Config.FailedTargetDelay
    end

    return Success
end

local function StepMoveToCandy(
    Candy
)
    return SafeTweenTo(
        Candy
    )
end

local function WaitForCollect(
    Candy,
    OldBag
)

    local Start =
        os.clock()

    repeat

        task.wait(0.05)

        if not Config.AutoCandy then

            return false,
                "Stopped"

        end

        if WaitingNextRound then

            return false,
                "WaitingNextRound"

        end

        if not Candy
            or not Candy.Parent then

            return true,
                "Removed"
        end

        if Candy:GetAttribute(
            "Collected"
        ) == true then

            return true,
                "CollectedAttribute"
        end

        if CurrentBag
            > OldBag then

            return true,
                "CoinCollected"
        end

    until
        os.clock()
        - Start
        >= Config.CollectTimeout

    return false,
        "Timeout"
end

local function ResetCharacterAfterFullBag()

    if ResettingCharacter
        or WaitingNextRound then

        return
    end

    ResettingCharacter = true
    WaitingNextRound = true

    CancelTween()

    task.wait(
        Config.ResetDelay
    )

    if not WaitingNextRound then

        ResettingCharacter =
            false

        return
    end

    local Character =
        Player.Character

    if Character then

        local Humanoid =
            Character:
            FindFirstChildOfClass(
                "Humanoid"
            )

        if Humanoid
            and Humanoid.Health > 0 then

            pcall(function()
                Humanoid.Health = 0
            end)

            task.wait(0.15)

            if Humanoid.Parent
                and Humanoid.Health > 0 then

                pcall(function()
                    Character:BreakJoints()
                end)
            end

        else

            pcall(function()
                Character:BreakJoints()
            end)
        end
    end

    ResettingCharacter =
        false

end

Addon=AttachKaitun({
    env=Env,config=Config,cancel=CancelTween,validCandy=IsValidCandy,
    snapshot=function()
        return {bag=CurrentBag,maxBag=MaxBag,waiting=WaitingNextRound,moving=IsMoving}
    end,
    setBag=function(bag,maximum) CurrentBag=bag;MaxBag=maximum or MaxBag end,
    abortReset=function() WaitingNextRound=false;ResettingCharacter=false end,
})
local Gui=Addon.Gui

Addon.Connect(CoinCollected.OnClientEvent,function(
    CoinID,
    Amount,
    Maximum,
    Extra
)

    if CoinID ~= "Candy" then
        return
    end

    CurrentBag =
        tonumber(Amount)
        or CurrentBag

    MaxBag =
        tonumber(Maximum)
        or MaxBag

    local Value =
        nil

    if type(Extra)
        == "table" then

        Value =
            Extra.Value
    end

    if CurrentBag >= MaxBag
        and MaxBag > 0
        and Config.AutoCandy then

        task.spawn(
            ResetCharacterAfterFullBag
        )
    end
end)

Addon.Connect(CoinsStarted.OnClientEvent,function()

    CurrentBag = 0

    WaitingNextRound =
        false

    ResettingCharacter =
        false

    FailedTargets = setmetatable(
        {},
        {
            __mode = "k"
        }
    )

    if Config.AutoCandy then

    end

end)

Addon.Connect(Player.CharacterAdded,function(Character)

    CancelTween()

    task.wait(1)

    if WaitingNextRound then

    end
end)

task.spawn(function()

    while Gui.Parent do

        task.wait(0.1)

        if not Addon.BeforeCycle() then continue end

        if not Config.AutoCandy then
            continue
        end

        if WaitingNextRound then

            task.wait(0.5)

            continue
        end

        if IsMoving then
            continue
        end

        local Character,
            Humanoid,
            Root =
            GetCharacter()

        if not Root then

            task.wait(1)

            continue
        end

        if MaxBag > 0
            and CurrentBag >= MaxBag then

            task.spawn(
                ResetCharacterAfterFullBag
            )

            task.wait(0.5)

            continue
        end

        local Candy,
            Distance =
            GetNearestCandy()

        if not Candy then

            task.wait(0.4)

            continue
        end

        local OldBag =
            CurrentBag

        local CandyName =
            Candy:GetFullName()

        local Reached =
            StepMoveToCandy(
                Candy
            )

        if not Config.AutoCandy then
            continue
        end

        if WaitingNextRound then
            continue
        end

        if Reached then

            local Success,
                Reason =
                WaitForCollect(
                    Candy,
                    OldBag
                )

            if Success then

                if CurrentBag
                    >= MaxBag
                    and MaxBag > 0 then

                    task.spawn(
                        ResetCharacterAfterFullBag
                    )

                    continue
                end

                local DelayStart =
                    os.clock()

                while Config.AutoCandy
                    and not WaitingNextRound
                    and (
                        os.clock()
                        - DelayStart
                    ) < Config.CollectDelay do

                    task.wait(0.1)
                end

            else

                if Reason ~= "Stopped"
                    and Reason
                        ~= "WaitingNextRound" then

                    if Candy
                        and Candy.Parent then

                        FailedTargets[Candy] =
                            os.clock()
                            + Config.FailedTargetDelay
                    end

                    task.wait(1)
                end
            end
        end
    end
end)

print("[Skider MM2] Loaded")
print("[Skider MM2] User: "..Player.Name)
print("[Skider MM2] Mode: "..(Settings.mode==1 and "Crates" or "Battle Pass"))
print("[Skider MM2] UI: "..(Settings.fullscreenUI and "Fullscreen" or "Compact"))
return Addon
