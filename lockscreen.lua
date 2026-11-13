-- A lock screen without a look: the password typed, checked with PAM in
-- the shady-auth helper, a fingerprint reader listening at the same time,
-- and the lock taken over by a shell started while the session is locked.
-- The rice draws it.
--
--     local lockscreen = require("lockscreen").install {
--         view = function(ctx, lock)          -- lock.length, lock.busy, ...
--             return shell.text(shell.date("%H:%M"))
--         end,
--     }
--     lockscreen.lock()
--
-- Options:
--   name         the lock popup's name, default "lock"
--   view         function(ctx, state) -> widget, the whole screen
--   before_lock  function(), run before locking, e.g. to close panels
--   fallback     function() -> bool, run when this shell cannot lock (no
--                helper, or no session lock in the compositor); default: a
--                notification saying so
--   fingerprint  the PAM service for the reader, default
--                "shady-lock-fingerprint"; it is used only when
--                /etc/pam.d has it. false: no reader
--   wrong        the message for a password PAM said no to without a reason
--
-- The state a view reads (and should not change):
--   length       characters typed
--   busy         the password is being checked
--   message      what PAM or the reader said last ("" for nothing)
--   error        the last attempt failed (message says why)
--   attempts     failed attempts so far, for a shake keyed on it
--
-- Any key types into the password; Enter checks it, Escape clears it,
-- BackSpace takes one character back.

local M = {}

local function file_exists(p)
    local f = io.open(p, "r")
    if f then f:close() end
    return f ~= nil
end

function M.install(opts)
    opts = opts or {}
    local name = opts.name or "lock"
    local service = opts.fingerprint
    if service == nil then service = "shady-lock-fingerprint" end
    local wrong = opts.wrong or "That was not it."

    local password = ""
    local state = { length = 0, busy = false, message = "", error = false, attempts = 0 }
    local fingerprint, checking

    local function set_password(p)
        password = p
        state.length = utf8.len(p) or #p
    end

    local function cancel(which)
        if which == "fingerprint" and fingerprint then
            shell.cancel_authentication(fingerprint); fingerprint = nil
        elseif which == "checking" and checking then
            shell.cancel_authentication(checking); checking = nil
        end
    end

    local function reset()
        set_password("")
        state.busy, state.message, state.error = false, "", false
    end

    local function listen_fingerprint()
        if not service or fingerprint or not shell.locked() or not file_exists("/etc/pam.d/" .. service) then
            return
        end
        fingerprint = shell.authenticate(nil, function(ok)
            fingerprint = nil
            if ok then
                cancel("checking")
                reset()
                shell.unlock()
            elseif shell.locked() then
                -- A wrong finger or a timeout: listen again a little later.
                shell.after(1500, listen_fingerprint)
            end
        end, { service = service, on_message = function(_, text)
            if not state.busy then state.message, state.error = text, false; shell.redraw() end
        end })
    end

    local function submit()
        -- An empty password too: PAM decides whether the account takes one.
        if state.busy then return end
        state.busy, state.message, state.error = true, "", false
        local started, id = pcall(shell.authenticate, password, function(ok, reason)
            checking, state.busy = nil, false
            if ok then
                cancel("fingerprint")
                reset()
                shell.unlock()
            else
                set_password("")
                state.error = true
                state.message = (reason and reason ~= "") and reason or wrong
                state.attempts = state.attempts + 1
            end
            shell.redraw()
        end)
        if started then
            checking = id
        else
            state.busy, state.error = false, true
            set_password("")
            state.message = "The password cannot be checked."
        end
    end

    local handle = { state = state }

    -- Whether this shell can lock: without the helper nothing would unlock.
    function handle.available() return shell.can_authenticate() end

    function handle.lock()
        if opts.before_lock then opts.before_lock() end
        if shell.locked() then return true end
        if shell.can_authenticate() then
            reset()
            if shell.lock() then
                listen_fingerprint()
                return true
            end
        end
        if opts.fallback then return opts.fallback() end
        shell.notify("Cannot lock the screen", shell.can_authenticate()
            and "The compositor offers no session lock." or "The shady-auth helper is not installed.")
        return false
    end

    -- Whatever unlocked, attempts begun under this lock must not answer the next.
    shell.on("unlocked", function()
        cancel("fingerprint")
        cancel("checking")
        reset()
    end)

    -- A shell started while the session is locked takes the lock over, so
    -- it can still be unlocked.
    shell.on("value", function(k, v)
        if k == "session.lock" and v == "abandoned" then handle.lock() end
    end)

    shell.popup {
        name = name,
        lock = true,
        keyboard = "exclusive",
        view = function(ctx) return opts.view(ctx, state) end,
        on_key = function(key, typed)
            if key == "Return" or key == "KP_Enter" then
                submit()
            elseif key == "Escape" then
                set_password("")
                state.message, state.error = "", false
            elseif key == "BackSpace" then
                local cut = utf8.offset(password, -1)
                if cut then set_password(password:sub(1, cut - 1)) end
            elseif typed ~= "" and not state.busy and #password < 512 then
                set_password(password .. typed)
                if state.error then state.message, state.error = "", false end
            end
            shell.redraw()
        end,
    }

    return handle
end

return M
