-- MainTank VanillaPlus TLP2 - cached Timeline view/index/details
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
               lastSeconds=0, lastEventCount=0}

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
    if cache and cache.events == events and cache.count == n and
       cache.view == owner.currentView and cache.inCombat == (owner.inCombat and true or false) then
        return cache
    end

    cache = {events=events, count=n, view=owner.currentView,
             inCombat=owner.inCombat and true or false, seconds={}, details={},
             timeline=nil, maximum=0}
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
    owner.tlpCache = cache
    owner.tlpStats.indexBuilds = owner.tlpStats.indexBuilds + 1
    owner.tlpStats.lastEventCount = n
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
    local timeline = OldGetTimeline(self)
    cache.timeline = timeline or {}
    self.tlpStats.timelineBuilds = self.tlpStats.timelineBuilds + 1
    -- Event attribution in the original RC6 pass may have just upgraded old
    -- event values. Detail cache is always built AFTER that authoritative pass.
    cache.details = {}
    return cache.timeline
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
        local before = self.tlpQueryEvents
        self.tlpQueryEvents = cache.seconds[firstSecond] or EMPTY
        -- The original RC6 implementations remain authoritative. Restrict
        -- their input; never approximate or reimplement mitigation formulas.
        local ok, result = pcall(OldGetDetails,self,firstSecond,lastSecond)
        self.tlpQueryEvents = before
        if not ok then error(result) end
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
    return result
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
       " events "..s.lastEventCount.." last "..floor(s.lastSeconds*1000+0.5).."ms"
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("MainTank "..message) end
end
