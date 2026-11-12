-- Start the shell with the config from SHADY_SHELL_CONFIG and say when the
-- test's windows map; the test script ends via shadyctl.
shady.spawn(string.format("%q", assert(os.getenv("SHADY_SHELL_BIN"))))
shady.on("window.mapped", function(window)
    shady.log("shell-blur: mapped " .. (window.app_id or ""))
end)
shady.automation.after(25000, function()
    shady.log("shell-blur: timed out")
    shady.quit()
end)
shady.set("spatial_mode", false)
