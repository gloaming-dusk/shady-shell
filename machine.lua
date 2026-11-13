-- The machine, as a shell reads and drives it: sound, screen light, power,
-- radios, the music playing, how busy it is, and the session. It has no
-- look; a rice draws what it returns.
--
--     local machine = require("machine")
--     local volume, muted = machine.volume()     -- in a view: repaints when it changes
--     machine.act.volume(volume + 5)
--
-- Everything is read with plain tools through shell.poll (wpctl, nmcli,
-- bluetoothctl, playerctl, upower, powerprofilesctl, /proc, sysfs), so a
-- poll starts the first time a view asks and a missing tool reads as nil.
-- A value the shell itself just changed wins over the poll for a few
-- seconds, so a slider does not jump back while the poll catches up.
--
-- With SHADY_SHELL_OFFLINE=1 (the headless tests) nothing is read and no
-- command runs: every source is nil and every action only logs.
--
-- Sources (call them in a view):
--   volume()        output volume 0..150 and whether it is muted
--   mic_muted()     whether the default microphone is muted
--   brightness()    screen light 1..100 (bin/shady-brightness)
--   battery()       charge 0..100 and status ("Charging", "Discharging", "Full", ...)
--   battery_time()  minutes and "full" or "empty", from upower
--   wifi()          on, network name, whether a cable is connected
--   bluetooth()     powered, name of a connected device ("" for none)
--   profile()       the power profile ("balanced", ...)
--   media()         {playing, title, artist, position, length} (seconds) or nil
--   cpu()           how busy the processors were lately, 0..1
--   memory()        fraction in use, total GiB
--   disk()          fraction of / in use, GiB free
--   uptime()        seconds since boot
--   have.<tool>     whether wpctl, nmcli, bluetoothctl, playerctl, upower,
--                   powerprofilesctl, systemctl are installed
--   has(command)    whether any program is on PATH
-- Actions (machine.act): volume(v), mute(), mic_mute(), brightness(v),
--   wifi(), bluetooth(), profile(), media("play-pause"|"next"|"previous"),
--   suspend(), reboot(), poweroff()

local M = {}
local act = {}
M.act = act

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Whether a program is on PATH. (Not os.execute: the shell reaps its
-- children itself, so system() never sees the status.)
function M.has(command)
    for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
        local f = io.open(dir .. "/" .. command, "r")
        if f then f:close() return true end
    end
    return false
end

local have = {}
for _, tool in ipairs { "wpctl", "nmcli", "bluetoothctl", "playerctl", "upower", "powerprofilesctl", "systemctl" } do
    have[tool] = M.has(tool)
end
M.have = have

local override = {}
local function remember(k, v) override[k] = { value = v, at = os.time() } end
local function live(k, polled)
    local o = override[k]
    if o and os.time() - o.at < 3 then return o.value end
    return polled
end

-- ---- sound and light ----------------------------------------------------

function M.volume()
    if not have.wpctl then return nil end
    local out = shell.poll("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null", 3000)
    local v = tonumber(out:match("Volume:%s*([%d%.]+)") or "")
    if not v then return nil end
    return live("volume", math.floor(v * 100 + 0.5)), live("mute", out:find("MUTED") ~= nil)
end

function M.mic_muted()
    if not have.wpctl then return nil end
    local out = shell.poll("wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null", 8000)
    if out == "" then return nil end
    return live("mic", out:find("MUTED") ~= nil)
end

local brightness_cmd = string.format("sh %q", shell.data_dir .. "/bin/shady-brightness")
function M.brightness()
    return live("brightness", tonumber(shell.poll(brightness_cmd .. " get 2>/dev/null", 6000)))
end

function act.volume(v)
    v = clamp(math.floor(v + 0.5), 0, 150)
    remember("volume", v)
    remember("mute", false)
    shell.spawn(string.format(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ %.2f", v / 100))
end

function act.mute()
    local _, muted = M.volume()
    remember("mute", not muted)
    shell.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
end

function act.mic_mute()
    remember("mic", not M.mic_muted())
    shell.spawn("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
end

function act.brightness(v)
    v = clamp(math.floor(v + 0.5), 1, 100)
    remember("brightness", v)
    shell.spawn(string.format("%s set %d", brightness_cmd, v))
end

-- ---- power ----------------------------------------------------------------

function M.battery()
    local out = shell.poll("cat /sys/class/power_supply/BAT*/capacity /sys/class/power_supply/BAT*/status"
        .. " 2>/dev/null | head -n2 | tr '\\n' ' '", 20000)
    local level, status = out:match("(%d+)%s+(%a+)")
    if not level then return nil end
    return tonumber(level), status
end

function M.battery_time()
    if not have.upower then return nil end
    local out = shell.poll("upower -i $(upower -e 2>/dev/null | grep -m1 BAT) 2>/dev/null"
        .. " | grep -E 'time to (empty|full)' | head -n1", 60000)
    local what, n, unit = out:match("time to (%a+):%s*([%d%.,]+)%s*(%a+)")
    if not what then return nil end
    n = tonumber((n:gsub(",", "."))) or 0
    local minutes = unit:find("^hour") and n * 60 or (unit:find("^min") and n or n / 60)
    return math.floor(minutes + 0.5), what
end

function M.profile()
    if not have.powerprofilesctl then return nil end
    return live("profile", trim(shell.poll("powerprofilesctl get 2>/dev/null", 15000)))
end

local PROFILES = { "power-saver", "balanced", "performance" }
function act.profile()
    local current, next = M.profile(), PROFILES[1]
    for i, p in ipairs(PROFILES) do if p == current then next = PROFILES[i % #PROFILES + 1] end end
    remember("profile", next)
    shell.spawn("powerprofilesctl set " .. next)
end

-- ---- radios -------------------------------------------------------------

function M.wifi()
    if not have.nmcli then return nil end
    local state = trim(shell.poll("nmcli -t -f WIFI general 2>/dev/null", 8000))
    if state == "" then return nil end
    local ssid = trim(shell.poll("nmcli -t -f active,ssid device wifi 2>/dev/null"
        .. " | sed -n 's/^yes://p' | head -n1", 8000))
    local wired = trim(shell.poll("nmcli -t -f TYPE,STATE device 2>/dev/null"
        .. " | grep -m1 '^ethernet:connected'", 15000))
    return live("wifi", state == "enabled"), ssid, wired ~= ""
end

function act.wifi()
    local on = M.wifi()
    remember("wifi", not on)
    shell.spawn("nmcli radio wifi " .. (on and "off" or "on"))
end

function M.bluetooth()
    if not have.bluetoothctl then return nil end
    local out = shell.poll("bluetoothctl show 2>/dev/null | grep -m1 Powered", 10000)
    if out == "" then return nil end
    local connected = trim(shell.poll("bluetoothctl devices Connected 2>/dev/null"
        .. " | head -n1 | cut -d' ' -f3-", 10000))
    return live("bluetooth", out:find("yes") ~= nil), connected
end

function act.bluetooth()
    local on = M.bluetooth()
    remember("bluetooth", not on)
    shell.spawn("bluetoothctl power " .. (on and "off" or "on"))
end

-- ---- music --------------------------------------------------------------

function M.media()
    if not have.playerctl then return nil end
    local out = shell.poll("playerctl metadata --format"
        .. " '{{status}}\t{{position}}\t{{mpris:length}}\t{{title}}\t{{artist}}' 2>/dev/null", 2000)
    local status, pos, len, title, artist = out:match("^(%a+)\t(%d*)\t(%d*)\t([^\t]*)\t([^\n]*)")
    if not status or status == "Stopped" or (title == "" and artist == "") then return nil end
    return {
        playing = live("playing", status == "Playing"),
        title = trim(title), artist = trim(artist),
        position = (tonumber(pos) or 0) / 1e6, length = (tonumber(len) or 0) / 1e6,
    }
end

function act.media(what)
    if what == "play-pause" then
        local m = M.media()
        if m then remember("playing", not m.playing) end
    end
    shell.spawn("playerctl " .. what)
end

-- ---- how busy it is ---------------------------------------------------------

local cpu_seen, cpu_prev, cpu_busy

function M.cpu()
    local out = shell.poll("head -n1 /proc/stat", 3000)
    if out ~= cpu_seen then
        cpu_seen = out
        local n = {}
        for v in out:gmatch("%d+") do n[#n + 1] = tonumber(v) end
        if #n >= 4 then
            local total, idle = 0, n[4] + (n[5] or 0)
            for i = 1, math.min(#n, 8) do total = total + n[i] end
            if cpu_prev and total > cpu_prev.total then
                cpu_busy = 1 - (idle - cpu_prev.idle) / (total - cpu_prev.total)
            end
            cpu_prev = { total = total, idle = idle }
        end
    end
    return cpu_busy
end

function M.memory()
    local out = shell.poll("grep -E '^(MemTotal|MemAvailable):' /proc/meminfo", 5000)
    local total = tonumber(out:match("MemTotal:%s*(%d+)") or "")
    local free = tonumber(out:match("MemAvailable:%s*(%d+)") or "")
    if not total or not free or total == 0 then return nil end
    return 1 - free / total, total / 1048576
end

function M.disk()
    local out = shell.poll("df -Pk / 2>/dev/null | tail -n1", 60000)
    local used, avail = out:match("^%S+%s+%d+%s+(%d+)%s+(%d+)")
    used, avail = tonumber(used), tonumber(avail)
    if not used or used + avail == 0 then return nil end
    return used / (used + avail), avail / 1048576
end

function M.uptime()
    return tonumber((shell.poll("cut -d' ' -f1 /proc/uptime", 60000)):match("^%d+") or "")
end

-- ---- the session -------------------------------------------------------

function act.suspend() shell.spawn("sleep 0.5; systemctl suspend") end
function act.reboot() shell.spawn("systemctl reboot") end
function act.poweroff() shell.spawn("systemctl poweroff") end

if os.getenv("SHADY_SHELL_OFFLINE") == "1" then
    for name, fn in pairs(M) do
        if type(fn) == "function" and name ~= "has" then M[name] = function() return nil end end
    end
    for name in pairs(act) do
        act[name] = function() shell.log("machine: offline, not running " .. name) end
    end
    for tool in pairs(have) do have[tool] = false end
end

return M
