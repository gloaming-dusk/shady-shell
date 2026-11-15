-- tests/headless-shell-dismiss.sh: the shell and two windows.
local probe = assert(os.getenv("SHADY_AUTOMATION_PROBE"))
shady.spawn(string.format("%q", assert(os.getenv("SHADY_SHELL_BIN"))))
shady.automation.after(300, function()
    shady.spawn("SHADY_AUTOMATION_PROBE_APP_ID=dismiss-a " .. probe)
    shady.spawn("SHADY_AUTOMATION_PROBE_APP_ID=dismiss-b " .. probe)
end)
