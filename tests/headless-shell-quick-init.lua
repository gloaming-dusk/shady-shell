-- The default UI's sheets, with the system sources off (SHADY_SHELL_OFFLINE),
-- so the machine sheet has the same rows everywhere: the day sheet opens
-- from the clock, the machine sheet from a published `meridian.do`, its
-- focus and do-not-disturb rows write their state files (focus_timer,
-- toasts), and Log out asks
-- before it ends the session.
local shell = assert(os.getenv("SHADY_SHELL_BIN"))
local probe = assert(os.getenv("SHADY_AUTOMATION_PROBE"))
local status = assert(os.getenv("SHADY_SHELL_QUICK_STATUS"))
local state = assert(os.getenv("XDG_STATE_HOME")) .. "/shady/"

local started = false

local function mark(line)
    local f = assert(io.open(status, "a"))
    f:write(line, "\n")
    f:close()
end

local function saved(name)
    local f = io.open(state .. name, "r")
    if not f then return "" end
    local text = f:read("a")
    f:close()
    return text
end

local function click(x, y)
    shady.automation.move_pointer(x, y)
    shady.automation.click("left")
end

shady.on("window.mapped", function(window)
    if window.app_id ~= "shady-quick-a" or started then return end
    started = true

    -- The day sheet, from the clock; then the calendar's next month.
    click(1238, 19)
    shady.automation.after(200, function()
        click(1235, 288)
    end)

    -- The shell ignores the values replayed when it connects, for 2 s.
    shady.automation.after(3200, function()
        shady.publish("meridian.do", "controls 1")
        shady.automation.after(300, function()
            -- Focus for 25 minutes, then do-not-disturb.
            click(1176, 225)
            shady.automation.after(200, function()
                assert(saved("focus"):find("until=%d+"), "focus did not start")
                mark("FOCUS=PASS")
                click(1100, 183)
                shady.automation.after(200, function()
                    assert(saved("notifications"):find("dnd=1"), "do not disturb did not turn on")
                    mark("DND=PASS")
                    -- Log out: the first click only asks.
                    click(1108, 276)
                    shady.automation.after(300, function()
                        mark("QUIT_REQUESTED=PASS")
                        click(1108, 276)
                    end)
                end)
            end)
        end)
    end)
end)

shady.spawn(string.format("%q", shell))
shady.automation.after(200, function()
    shady.spawn(string.format(
        "SHADY_AUTOMATION_PROBE_APP_ID=shady-quick-a SHADY_AUTOMATION_PROBE_COLOR=0xff803030 %q",
        probe))
end)
