-- MainTank VanillaPlus TLP1 - one-pass Timeline event indexing
-- Pure presentation optimization for the 60-bar Timeline page.
-- Keeps existing RC6 attribution, combat parser, authoritative saved events,
-- archive/history retention, SavedVariables, and SI2/DC2 startup untouched.
-- Load AFTER UI/NavigationPolish.lua and Modules/TooltipSafe.lua.

if not MainTank then return end
local MT = MainTank
local floor = math.floor
local max = math.max
local min = math.min
local EMPTY = {}
local PrevDisplayEvents = MT.GetDisplayEvents
local PrevTimelineDetails = MT.GetTimelineDetails
local PrevTimelineUpdate = MT.UpdateTimelineWindow
local PrevTimelineCreate = MT.CreateTimelineWindow

-- Only while the old RC6 details function is executing on a single-second
-- Timeline bar do we expose that second's saved events to its existing math.
-- Everywhere else GetDisplayEvents still returns the full authoritative view.
function MT:GetDisplayEvents()
    if self.tlpQueryEvents ~= nil then return self.tlpQueryEvents end
    return PrevDisplayEvents(self)
end

function MT:GetTimelineDetails(firstSecond, lastSecond)
    local cache = self.tlpPageCache
    if cache and type(firstSecond) == "number" and firstSecond == lastSecond and
       cache.view == self.currentView and cache.page == (self.timelinePage or 0) and
       firstSecond >= cache.first and firstSecond <= cache.last then
        local saved = self.tlpQueryEvents
        self.tlpQueryEvents = cache.seconds[firstSecond] or EMPTY
        -- Preserve ALL existing RC6/VanillaPlus detail calculations unchanged.
        -- Restoring this temporary query flag even on error is essential.
        local ok, result = pcall(PrevTimelineDetails, self, firstSecond, lastSecond)
        self.tlpQueryEvents = saved
        if not ok then error(result) end
        return result
    end
    return PrevTimelineDetails(self, firstSecond, lastSecond)
end

function MT:UpdateTimelineWindow()
    if not self.timelineFrame then return PrevTimelineUpdate(self) end

    local events = PrevDisplayEvents(self) or {}
    local count = table.getn(events)
    local maximumSecond = 0
    local i, e, sec

    -- One complete pass to establish the page limit. Combat records are still
    -- owned by MainTank; no event or saved timeline bucket is modified.
    for i = 1, count do
        e = events[i]
        if type(e) == "table" then
            sec = floor(tonumber(e.time) or 0)
            if sec > maximumSecond then maximumSecond = sec end
        end
    end
    local maximumPage = floor(maximumSecond / 60)
    local page = floor(tonumber(self.timelinePage) or 0)
    page = max(0, min(page, maximumPage))
    self.timelinePage = page

    -- Index just the selected minute. Each event is now visited at most twice
    -- per redraw, rather than once for every one of the 60 Timeline bars.
    local first = page * 60
    local last = first + 59
    local seconds = {}
    local list
    for i = 1, count do
        e = events[i]
        if type(e) == "table" then
            sec = floor(tonumber(e.time) or 0)
            if sec >= first and sec <= last then
                list = seconds[sec]
                if not list then
                    list = {}
                    seconds[sec] = list
                end
                list[table.getn(list) + 1] = e
            end
        end
    end

    self.tlpPageCache = {
        view = self.currentView,
        page = page,
        first = first,
        last = last,
        seconds = seconds
    }
    return PrevTimelineUpdate(self)
end

-- Release large-fight event references when Timeline is no longer visible.
-- Older clients and custom UIs use different navigation paths; OnHide catches
-- all of them without changing the navigation or startup architecture.
function MT:CreateTimelineWindow()
    local frame = PrevTimelineCreate(self)
    if frame and not frame.tlpHideHooked then
        frame.tlpHideHooked = true
        local oldOnHide = frame:GetScript("OnHide")
        frame:SetScript("OnHide", function()
            if oldOnHide then oldOnHide() end
            MT.tlpPageCache = nil
            MT.tlpQueryEvents = nil
        end)
    end
    return frame
end
