-- SETTINGS
local CFG = {
    -- UI library file
    UI_LIB        = "ui_lib.lua",

    -- Program
    TITLE         = "BLAST DOOR CONTROL SYSTEM - A",
    STATE_FILE    = "state",

    -- Network addresses
    NET_ID        = "blast_door_control_system_a",           -- this computer
    PEER_IDS      = { "blast_door_control_system_b" },       -- other computer
    RELAY_ID      = "redstone_relay_3",                      -- relay address in network
    RELAY_SIDE    = "front",                                 -- relay side that outputs the signal
    PULSE_TIME    = 1,                                       -- pulse length, seconds
    IS_PRIMARY    = true,                                    -- wins state conflicts (A = true, B = false)
    HEARTBEAT     = 5,                                       -- seconds between idle state broadcasts
    BUSY_TIMEOUT  = 5,                                       -- follower gives up if leader is silent this long

    -- Wired modem
    MODEM_SIDE    = "left",
    PROTOCOL      = "blast_door_control_system_protocol",

    -- Animation
    ANIM_DURATION = 14,       -- seconds for open/close animation
    ANIM_STEPS    = 42,       -- progress bar steps (best around 3x ANIM_DURATION)

    -- Audio
    SPEAKER_SIDE  = "top",
    SOUND_FILE    = "alarm.dfpwm",
    GAIN          = 2.0,

    -- Commands
    CMD_OPEN      = "open",
    CMD_CLOSE     = "close",
}

-- UI
local ui = dofile(CFG.UI_LIB)

-- Runtime state
local state    = "CLOSED"
local isBusy   = false
local progress = 0
local leaderId = nil   -- NET_ID of current leader
local rev      = 0     -- bumped on every door state change; newer rev wins
local target   = nil   -- door target while this computer leads; saved to resume after reboot

local speaker = peripheral.wrap(CFG.SPEAKER_SIDE)
local dfpwm   = require("cc.audio.dfpwm")

-- Network helpers
local peerSet = {}
for _, id in ipairs(CFG.PEER_IDS) do
    peerSet[id] = true
end

local function isPeer(netId)
    return netId and peerSet[netId] == true
end

local function netOpen()
    if not peripheral.isPresent(CFG.MODEM_SIDE) then return false end
    if not rednet.isOpen(CFG.MODEM_SIDE) then
        rednet.open(CFG.MODEM_SIDE)
    end
    return true
end

local function netSend(msg)
    msg.from = CFG.NET_ID
    rednet.broadcast(msg, CFG.PROTOCOL)
end

-- Redstone relay is a peripheral, not a rednet node. Never let it crash the program
local function relaySet(on)
    return pcall(peripheral.call, CFG.RELAY_ID, "setOutput", CFG.RELAY_SIDE, on)
end

local function signalRelayPulse()
    relaySet(true)
    sleep(CFG.PULSE_TIME)
    for _ = 1, 5 do                       -- make sure the signal really goes off
        if relaySet(false) then break end
        sleep(1)
    end
end

-- Audio
local function playAlarm()
    if not speaker or not fs.exists(CFG.SOUND_FILE) then return end
    local decoder = dfpwm.make_decoder()
    local f = fs.open(CFG.SOUND_FILE, "rb")
    if not f then return end
    while true do
        local chunk = f.read(16 * 1024)
        if not chunk then break end
        local buffer = decoder(chunk)
        for i = 1, #buffer do
            local sample = buffer[i] * CFG.GAIN
            if sample > 127 then
                sample = 127
            elseif sample < -128 then
                sample = -128
            end
            buffer[i] = sample
        end
        while not speaker.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    f.close()
end

-- Persistence
local function loadState()
    if not fs.exists(CFG.STATE_FILE) then return end
    local ok, data = pcall(function()
        local h = fs.open(CFG.STATE_FILE, "r")
        local raw = h.readAll()
        h.close()
        return textutils.unserializeJSON(raw)
    end)
    if ok and type(data) == "table" then
        if type(data.state) == "string" then state = data.state end
        if type(data.isBusy) == "boolean" then isBusy = data.isBusy end
        if type(data.progress) == "number" then progress = data.progress end
        if type(data.rev) == "number" then rev = data.rev end
        if type(data.target) == "string" then target = data.target end
    end
end

local function saveState()
    local tmp = CFG.STATE_FILE .. ".tmp"
    local ok = pcall(function()
        local h = fs.open(tmp, "w")
        h.write(textutils.serializeJSON({
            state    = state,
            isBusy   = isBusy,
            progress = progress,
            rev      = rev,
            target   = target,
        }))
        h.close()
    end)
    if ok then
        fs.delete(CFG.STATE_FILE)
        fs.move(tmp, CFG.STATE_FILE)
    end
end

-- UI draw
local function drawUI()
    term.setCursorBlink(false)
    ui.clearContent()
    ui.title(CFG.TITLE)

    ui.label(5, "State:")
    if state == "OPEN" then
        ui.value(6, "OPENED", ui.ORANGE)
    else
        ui.value(6, "CLOSED", ui.WHITE)
    end

    if isBusy then
        local msg = (state == "OPEN") and "Closing in progress..." or "Opening in progress..."
        ui.label(8, msg)
        ui.progressBar(9, 30, progress)
        return
    end

    ui.prompt(8)
    ui.commands(17, CFG.CMD_OPEN .. " / " .. CFG.CMD_CLOSE)
end

-- Put the cursor back on the input line (drawUI leaves it on another row, and read() redraws on whatever row the cursor is on)
local function focusInput()
    term.setTextColor(ui.ORANGE)
    term.setBackgroundColor(ui.BLACK)
    term.setCursorPos(5, 9)
    term.setCursorBlink(true)
end

local function armInput()
    drawUI()
    term.setTextColor(ui.ORANGE)
    term.setBackgroundColor(ui.BLACK)
    term.setCursorPos(5, 9)
    term.write(string.rep(" ", ui.WIDTH - 4))
    term.setCursorPos(5, 9)
    term.setCursorBlink(true)
end

local function broadcastState()
    netSend({
        type     = "state",
        state    = state,
        busy     = isBusy,
        progress = progress,
        leader   = leaderId,
        rev      = rev,
    })
end

-- Animation
local function runAnimation(targetState, resumeFrom)
    isBusy   = true
    progress = resumeFrom or 0
    leaderId = CFG.NET_ID
    target   = targetState
    saveState()
    broadcastState()
    drawUI()

    if not resumeFrom then signalRelayPulse() end   -- on resume the door was already triggered

    parallel.waitForAll(
        function()
            playAlarm()
        end,
        function()
            local stepTime = CFG.ANIM_DURATION / CFG.ANIM_STEPS
            local first = resumeFrom and (math.floor(resumeFrom / 100 * CFG.ANIM_STEPS) + 1) or 1
            for i = first, CFG.ANIM_STEPS do
                progress = math.floor((i / CFG.ANIM_STEPS) * 100)
                saveState()
                broadcastState()
                drawUI()
                sleep(stepTime)
            end
        end
    )

    state    = targetState
    rev      = rev + 1
    target   = nil
    isBusy   = false
    progress = 0
    leaderId = nil
    saveState()
    broadcastState()
    drawUI()
end

local function applyRemoteState(msg)
    local oldState, oldBusy, oldProgress = state, isBusy, progress
    if type(msg.state) == "string" then state = msg.state end
    if type(msg.busy) == "boolean" then isBusy = msg.busy end
    if type(msg.progress) == "number" then progress = msg.progress end
    if msg.leader ~= nil then leaderId = msg.leader end
    if type(msg.rev) == "number" and msg.rev > rev then rev = msg.rev end
    saveState()
    if state ~= oldState or isBusy ~= oldBusy or progress ~= oldProgress then
        drawUI()
        if not isBusy then focusInput() end
    end
end

local function tryLead(action)
    if isBusy then return end
    if action == CFG.CMD_OPEN and state == "OPEN" then return end
    if action == CFG.CMD_CLOSE and state == "CLOSED" then return end
    runAnimation((action == CFG.CMD_OPEN) and "OPEN" or "CLOSED")
end

-- Main
loadState()

-- Were we leading an animation when we went down? Then the door was already triggered: resume it.
local resumeTarget, resumeProgress
if isBusy and target then
    resumeTarget, resumeProgress = target, progress
end

isBusy   = false
progress = 0
leaderId = nil
target   = nil
saveState()

netOpen()
relaySet(false)          -- clear a signal left on by a crash
drawUI()
if resumeTarget then
    runAnimation(resumeTarget, resumeProgress)
else
    broadcastState()
end

while true do
    local inputResult = nil

    if isBusy then
        local lastSeen = os.clock()
        while isBusy do
            local _, msg = rednet.receive(CFG.PROTOCOL, 0.2)
            if type(msg) == "table" and msg.from ~= CFG.NET_ID and msg.type == "state" then
                -- accept every peer state, including the final one (busy=false, leader=nil)
                if isPeer(msg.from) then
                    lastSeen = os.clock()
                    applyRemoteState(msg)
                end
            end
            if isBusy and os.clock() - lastSeen > CFG.BUSY_TIMEOUT then
                -- leader went silent: give up, the peer's heartbeat will resync us
                isBusy, progress, leaderId = false, 0, nil
                saveState()
                drawUI()
            end
        end
    else
        armInput()

        parallel.waitForAny(
            function()
                inputResult = read()
            end,
            function()
                while true do
                    local _, msg = rednet.receive(CFG.PROTOCOL, CFG.HEARTBEAT)
                    if msg == nil then
                        broadcastState()               -- heartbeat: lets the peer notice a stale/newer state
                    elseif type(msg) ~= "table" or msg.from == CFG.NET_ID then
                        -- skip own / junk
                    elseif not isPeer(msg.from) then
                        -- ignore unknown addresses
                    elseif msg.type == "state" then
                        if msg.leader and msg.leader ~= CFG.NET_ID then
                            applyRemoteState(msg)
                            if isBusy then return end
                        elseif not isBusy then
                            local r = tonumber(msg.rev) or 0
                            if r > rev then
                                applyRemoteState(msg)      -- peer is newer: take its state
                            elseif r < rev then
                                broadcastState()           -- peer is stale: tell it ours
                            elseif msg.state ~= state then
                                -- same rev, different state: primary (A) wins
                                if CFG.IS_PRIMARY then broadcastState() else applyRemoteState(msg) end
                            end
                        end
                    elseif msg.type == "cmd" and not isBusy then
                        tryLead(msg.action)
                        return
                    end
                end
            end
        )

        term.setCursorBlink(false)

        if inputResult and not isBusy then
            local cmd = inputResult:match("^%s*(.-)%s*$") or ""
            if cmd == CFG.CMD_OPEN or cmd == CFG.CMD_CLOSE then
                netSend({ type = "cmd", action = cmd, target = "peers" })
                tryLead(cmd)
            else
                drawUI()
            end
        elseif not isBusy then
            drawUI()
        end
    end
end
