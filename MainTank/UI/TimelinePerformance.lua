-- MainTank VanillaPlus TLP2O1 - Overall Timeline saved-bucket parity
-- Lua 5.0 / WoW 1.12.1 only. Presentation-only. No SavedVariables changes.
-- Loaded last: preserves all existing RC6 attribution/tooltip calculations.
-- TLP1 missed the full GetDisplayTimeline RC6 rebuild on every arrow/page.
-- TLP2 caches THAT authoritative result, plus per-second event/detail views.
if not MainTank then return end
local MT = MainTank
local floor = math.floor
local max = math.max
local min = math.min
local EMPTY = {}

local OldGetEvents = MT.GetDisplayEvents
local OldGetTimeline = MT.GetDisplayTimeline
local OldGetDetails = MT.GetTimelineDetails
local OldUpdate = MT.UpdateTimelineWindow
local OldCreate = MT.CreateTimelineWindow

MT.tlpStats = {draws=0, indexBuilds=0, timelineBuilds=0,
               timelineHits=0, detailsBuilds=0, detailsHits=0,
               lastSeconds=0, lastEventCount=0, lastIndexMs=0,
               lastTimelineMs=0, lastDetailsMs=0, lastTotalMs=0,
               slowestTotalMs=0, overallSummaryBars=0}

local function TLP_Clear(owner)
    owner.tlpCache = nil
    owner.tlpQueryEvents = nil
    owner.tlpDrawing = nil
end

-- Narrowly redirect existing RC6 details math to just one second, but NEVER
-- replace the normal event accessor for Pie/Details/Export/other pages.
function MT:GetDisplayEvents()
    if self.tlpQueryEvents ~= nil then return self.tlpQueryEvents end
    return OldGetEvents(self)
end

-- Cache is tied to the actual immutable display-event array, view and size.
-- An added combat event (or rebuilt saved-fight snapshot) invalidates it.
local function TLP_Ensure(owner, events)
    local n = table.getn(events)
    local cache = owner.tlpCache
    local overallSource = nil
    local overallElapsed = nil
    if owner.currentView == "OVERALL" and not owner.inCombat then
        overallSource = owner.overallTimeline
        overallElapsed = owner.overallCombatElapsed
    end
    if cache and cache.events == events and cache.count == n and
       cache.view == owner.currentView and cache.inCombat == (owner.inCombat and true or false) and
       cache.overallSource == overallSource and
       cache.overallElapsed == overallElapsed then
        return cache
    end

    local indexedAt = GetTime and GetTime() or 0
    cache = {events=events, count=n, view=owner.currentView,
             inCombat=owner.inCombat and true or false, seconds={}, details={},
             timeline=nil, maximum=0, overallSource=overallSource,
             overallElapsed=overallElapsed}
    local i, e, sec, list
    for i=1,n do
        e = events[i]
        if type(e) == "table" then
            sec = floor(tonumber(e.time) or 0)
            if sec < 0 then sec = 0 end
            if sec > cache.maximum then cache.maximum = sec end
            list = cache.seconds[sec]
            if not list then
                list = {}
                cache.seconds[sec] = list
            end
            list[table.getn(list)+1] = e
        end
    end
    -- Historical Overall contains authoritative persisted buckets for fights
    -- whose detailed events have been pruned from Recent/Archive. Page bounds
    -- must include those buckets, not just the surviving runtime event list.
    -- Never synthesize or persist events from an Overall summary bucket.
    if overallSource then
        cache.timeline = overallSource
        local bucketSecond
        for bucketSecond in pairs(overallSource) do
            if type(bucketSecond) == "number" and bucketSecond > cache.maximum then
                cache.maximum = bucketSecond
            end
        end
    end
    owner.tlpCache = cache
    owner.tlpStats.indexBuilds = owner.tlpStats.indexBuilds + 1
    owner.tlpStats.lastEventCount = n
    owner.tlpStats.lastIndexMs = ((GetTime and GetTime() or indexedAt)-indexedAt)*1000
    return cache
end

-- The original RC6 GetDisplayTimeline walks and re-attributes EVERY event.
-- Preserve its exact result; calculate it only once per unchanged fight.
function MT:GetDisplayTimeline()
    local cache = self.tlpDrawing and self.tlpCache or nil
    if not cache then return OldGetTimeline(self) end
    if cache.timeline ~= nil then
        self.tlpStats.timelineHits = self.tlpStats.timelineHits + 1
        return cache.timeline
    end
    local started = GetTime and GetTime() or 0
    local timeline = OldGetTimeline(self)
    self.tlpStats.lastTimelineMs = self.tlpStats.lastTimelineMs +
        ((GetTime and GetTime() or started)-started)*1000
    cache.timeline = timeline or {}
    self.tlpStats.timelineBuilds = self.tlpStats.timelineBuilds + 1
    -- Event attribution in the original RC6 pass may have just upgraded old
    -- event values. Detail cache is always built AFTER that authoritative pass.
    cache.details = {}
    return cache.timeline
end

-- An Overall second may outlive its individual events. Provide exactly the
-- quantities persisted in the authoritative Timeline bucket without guessing
-- which dodge/parry/resist school generated them.
local function TLP_OverallSummaryDetails(bucket)
    return {
        raw=tonumber(bucket.raw) or 0,
        physicalRaw=tonumber(bucket.physicalRaw) or 0,
        magicRaw=tonumber(bucket.magicRaw) or 0,
        taken=tonumber(bucket.taken) or 0,
        physicalTaken=tonumber(bucket.physicalTaken) or 0,
        magicTaken=tonumber(bucket.magicTaken) or 0,
        armor=tonumber(bucket.armor) or 0,
        block=tonumber(bucket.block) or 0,
        avoidance=tonumber(bucket.avoidance) or 0,
        resist=tonumber(bucket.resist) or 0,
        absorb=tonumber(bucket.absorb) or 0,
        events=tonumber(bucket.events) or 0,
        damageEvents=0,
        dodge=0, parry=0, miss=0,
        dodgeCount=0, parryCount=0, missCount=0,
        partialBlock=0, fullBlock=0,
        partialBlockCount=0, fullBlockCount=0,
        physicalAbsorb=0, magicAbsorb=0, schools={},
        flatDR=0, physicalDR=0, magicDR=0,
        physicalFlatDR=0, magicFlatDR=0,
        tlpSummaryOnly=true
    }
end

local function TLP_ApplyOverallBucket(details, bucket)
    -- The stored Overall bucket wins over any incomplete runtime-event subset.
    -- These are the precise fields written by AddToTimelineBucket.
    local names={"raw","physicalRaw","magicRaw","taken","physicalTaken",
                 "magicTaken","armor","block","avoidance","resist","absorb","events"}
    local i, name
    for i=1,table.getn(names) do
        name=names[i]
        if bucket[name] ~= nil then details[name]=bucket[name] end
    end
end

function MT:GetTimelineDetails(firstSecond,lastSecond)
    local cache = self.tlpCache
    if cache and type(firstSecond) == "number" and firstSecond == lastSecond
       and cache.view == self.currentView and
       cache.inCombat == (self.inCombat and true or false) then
        local detail = cache.details[firstSecond]
        if detail then
            self.tlpStats.detailsHits = self.tlpStats.detailsHits + 1
            return detail
        end
        local source = cache.seconds[firstSecond] or EMPTY
        local overallBucket
        if self.currentView == "OVERALL" and not self.inCombat and cache.timeline then
            overallBucket = cache.timeline[firstSecond]
        end
        if overallBucket and table.getn(source) == 0 then
            -- Older Overall seconds can have valid bars yet no retained events.
            -- Bypass the event-only RC6 details function for those seconds.
            detail = TLP_OverallSummaryDetails(overallBucket)
            cache.details[firstSecond] = detail
            self.tlpStats.overallSummaryBars = self.tlpStats.overallSummaryBars + 1
            return detail
        end
        local before = self.tlpQueryEvents
        self.tlpQueryEvents = source
        -- The original RC6 implementations remain authoritative. Restrict
        -- their input; never approximate or reimplement mitigation formulas.
        local started = GetTime and GetTime() or 0
        local ok, result = pcall(OldGetDetails,self,firstSecond,lastSecond)
        self.tlpQueryEvents = before
        self.tlpStats.lastDetailsMs = self.tlpStats.lastDetailsMs +
            ((GetTime and GetTime() or started)-started)*1000
        if not ok then error(result) end
        if overallBucket then TLP_ApplyOverallBucket(result, overallBucket) end
        cache.details[firstSecond] = result
        self.tlpStats.detailsBuilds = self.tlpStats.detailsBuilds + 1
        return result
    end
    return OldGetDetails(self,firstSecond,lastSecond)
end

function MT:UpdateTimelineWindow()
    if not self.timelineFrame then return OldUpdate(self) end
    local startTime = GetTime and GetTime() or 0
    local events = OldGetEvents(self) or EMPTY
    local stats = self.tlpStats
    stats.lastIndexMs = 0
    stats.lastTimelineMs = 0
    stats.lastDetailsMs = 0
    local cache = TLP_Ensure(self,events)

    -- Live combats can send dozens of events per second. The old RecordEvent
    -- calls this redraw per event; cap the PRESENTATION to ~4Hz while active.
    -- The parser and all saved combat events remain completely unthrottled.
    if self.inCombat and cache.count > 0 and self.tlpLastDraw and
       startTime > 0 and (startTime-self.tlpLastDraw) < 0.25 and
       cache.pageDrawn == (self.timelinePage or 0) and
       cache.modeDrawn == (self.timelineMode or "RAW") then
        return
    end

    local maxPage = floor(cache.maximum / 60)
    local page = floor(tonumber(self.timelinePage) or 0)
    page = max(0,min(page,maxPage))
    self.timelinePage = page

    self.tlpDrawing = true
    local ok, result = pcall(OldUpdate,self)
    self.tlpDrawing = nil
    if not ok then error(result) end
    cache.pageDrawn = page
    cache.modeDrawn = self.timelineMode or "RAW"
    self.tlpLastDraw = startTime
    self.tlpStats.draws = self.tlpStats.draws + 1
    self.tlpStats.lastSeconds = ((GetTime and GetTime() or startTime)-startTime)
    self.tlpStats.lastTotalMs = self.tlpStats.lastSeconds*1000
    if self.tlpStats.lastTotalMs > self.tlpStats.slowestTotalMs then
        self.tlpStats.slowestTotalMs = self.tlpStats.lastTotalMs
    end
    return result
end

-- When saved Overall buckets outlive their detailed events, show only known
-- summary quantities. Do not display made-up Dodge/Parry/Miss sub-breakdowns.
local OldShowTimelineTooltip = MT.ShowTimelineTooltip
function MT:ShowTimelineTooltip(owner, second, bucket)
    if bucket and self.currentView == "OVERALL" and not self.inCombat then
        local first = bucket.firstSecond or second or 0
        local last = bucket.lastSecond or first
        if first == last then
            local details = self:GetTimelineDetails(first, last)
            if details and details.tlpSummaryOnly then
                local mode = self.timelineMode or "RAW"
                local tip = self:GetAnalysisTooltip()
                local function Line(label, value, r, g, b)
                    tip:AddDoubleLine(label, self:FormatNumber(value),
                        r or 0.85, g or 0.85, b or 0.85, 1,1,1)
                end
                tip:SetOwner(owner, "ANCHOR_CURSOR")
                tip:SetText(mode.." Timeline - "..first.."s",1,0.82,0)
                if mode == "PHYSICAL" then
                    Line("Raw physical incoming",details.physicalRaw)
                    Line("Physical stopped",math.max(0,details.physicalRaw-details.physicalTaken),0.35,0.85,0.35)
                    Line("Physical damage taken",details.physicalTaken,1,0.35,0.3)
                elseif mode == "MAGIC" then
                    Line("Raw magic incoming",details.magicRaw)
                    Line("Magic stopped",math.max(0,details.magicRaw-details.magicTaken),0.35,0.85,0.35)
                    Line("Magic damage taken",details.magicTaken,1,0.35,0.3)
                else
                    Line("Raw incoming",details.raw,0.35,0.75,1)
                    Line("Raw physical",details.physicalRaw)
                    Line("Raw magic",details.magicRaw)
                    tip:AddLine(" ")
                    Line("Armor",details.armor,0.35,0.85,0.35)
                    Line("Avoidance",details.avoidance,0.35,0.85,0.35)
                    Line("Block",details.block,0.35,0.85,0.35)
                    Line("Resisted",details.resist,0.35,0.85,0.35)
                    Line("Absorbed",details.absorb,0.35,0.85,0.35)
                    tip:AddLine(" ")
                    Line("Damage stopped",math.max(0,details.raw-details.taken),0.35,0.85,0.35)
                    Line("Damage taken",details.taken,1,0.35,0.3)
                end
                Line("Events",details.events)
                tip:AddLine("Summary only: individual events no longer retained",1,0.72,0.3,1)
                tip:Show()
                return
            end
        end
    end
    return OldShowTimelineTooltip(self, owner, second, bucket)
end

function MT:CreateTimelineWindow()
    local frame = OldCreate(self)
    if frame and not frame.tlpHideHooked then
        frame.tlpHideHooked = true
        local oldHide = frame:GetScript("OnHide")
        frame:SetScript("OnHide",function()
            if oldHide then oldHide() end
            TLP_Clear(MT)
            MT.tlpLastDraw = nil
        end)
    end
    return frame
end

-- Lightweight diagnostics for in-game tests: /run MainTank:PrintTimelinePerf()
-- Numbers describe what was executed, not claimed FPS or speedup.
function MT:PrintTimelinePerf()
    local s = self.tlpStats
    local message = "TLP2 draws "..s.draws.." index "..s.indexBuilds..
       " timeline builds "..s.timelineBuilds.." hits "..s.timelineHits..
       " details built "..s.detailsBuilds.." hits "..s.detailsHits..
       " events "..s.lastEventCount.." summary bars "..s.overallSummaryBars..
       " last "..floor(s.lastSeconds*1000+0.5).."ms"
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("MainTank "..message)
        DEFAULT_CHAT_FRAME:AddMessage("MainTank TLP2 last redraw total "..floor(s.lastTotalMs+0.5)..
            "ms (index "..floor(s.lastIndexMs+0.5)..", timeline "..
            floor(s.lastTimelineMs+0.5)..", 60 details "..floor(s.lastDetailsMs+0.5)..
            "); worst "..floor(s.slowestTotalMs+0.5).."ms")
    end
end
