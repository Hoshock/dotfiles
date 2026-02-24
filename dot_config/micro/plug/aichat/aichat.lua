VERSION = "3.5.0"

local micro  = import("micro")
local config = import("micro/config")
local shell  = import("micro/shell")
local buffer = import("micro/buffer")
local util   = import("micro/util")

local AI_BUF_PATH = "[AI]"
local currentModel = ""
local lastDetectedModel = ""
local LOG_FILE = "/tmp/micro-aichat.log"
local MODEL_FILE = "/tmp/micro-ai-lastmodel.txt"
local SAVED_MODEL_FILE = ""  -- set in init()
local MAX_HISTORY = 5
local MAX_HISTORY_CHARS = 2000
local aiRunning = false
local currentJob = nil
local HOME = os.getenv("HOME") or ""

local history = {}

----------------------------------------------------------------
-- logging
----------------------------------------------------------------
function logFile(msg)
    pcall(function()
        local f = io.open(LOG_FILE, "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
end

----------------------------------------------------------------
-- model persistence
----------------------------------------------------------------
function saveModel()
    pcall(function()
        local f = io.open(SAVED_MODEL_FILE, "w")
        if f then
            f:write(currentModel)
            f:close()
        end
    end)
    config.SetGlobalOptionNative("aichat.model", getDisplayModel())
end

function loadModel()
    pcall(function()
        local f = io.open(SAVED_MODEL_FILE, "r")
        if f then
            local m = f:read("*l")
            f:close()
            if m and m ~= "" then
                currentModel = m
                logFile("loaded saved model: " .. m)
            end
        end
    end)
end

----------------------------------------------------------------
-- init
----------------------------------------------------------------
function init()
    logFile("===== init: VERSION=" .. VERSION .. " =====")
    SAVED_MODEL_FILE = config.ConfigDir .. "/.aichat-model"
    config.RegisterCommonOption("aichat", "model", "")
    config.MakeCommand("ai", cmdAI, config.NoComplete)
    config.MakeCommand("aimodel", cmdAIModel, config.NoComplete)
    config.MakeCommand("aiclear", cmdAIClear, config.NoComplete)
    loadModel()
    readDetectedModel()
    config.SetGlobalOptionNative("aichat.model", getDisplayModel())
end

function getDisplayModel()
    if currentModel ~= "" then return currentModel end
    if lastDetectedModel ~= "" then return lastDetectedModel end
    return ""
end

function readDetectedModel()
    pcall(function()
        local f = io.open(MODEL_FILE, "r")
        if f then
            local m = f:read("*l")
            f:close()
            if m and m ~= "" then
                lastDetectedModel = m
                logFile("detected model: " .. m)
            end
        end
    end)
end

function getPlugDir()
    return config.ConfigDir .. "/plug/aichat"
end

function shortenPath(path)
    if HOME ~= "" and path:sub(1, #HOME) == HOME then
        return "~" .. path:sub(#HOME + 1)
    end
    return path
end

----------------------------------------------------------------
-- response cleaning for history context
----------------------------------------------------------------
function isToolHeader(line)
    if #line < 3 then return false end
    local b1, b2, b3 = line:byte(1, 3)
    -- U+25CF "●" = 226 151 143
    -- U+2717 "✗" = 226 156 151
    if b1 == 226 then
        if b2 == 151 and b3 == 143 then return true end
        if b2 == 156 and b3 == 151 then return true end
    end
    return false
end

function stripToolLogs(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    local result = {}
    local skip = false
    for _, line in ipairs(lines) do
        if isToolHeader(line) then
            skip = true
        elseif skip then
            if line:match("^%s") or line:match("^%(") then
                -- indented or path continuation — still in tool block
            else
                skip = false
                result[#result + 1] = line
            end
        else
            result[#result + 1] = line
        end
    end
    local joined = table.concat(result, "\n")
    joined = joined:gsub("\n\n\n+", "\n\n")
    joined = joined:gsub("^%s+", ""):gsub("%s+$", "")
    return joined
end

function cleanForHistory(text)
    local cleaned = stripToolLogs(text)
    if #cleaned > MAX_HISTORY_CHARS then
        cleaned = cleaned:sub(#cleaned - MAX_HISTORY_CHARS + 1)
    end
    return cleaned
end

----------------------------------------------------------------
-- pane management
----------------------------------------------------------------
function findPane(isAI)
    local tabs = micro.Tabs()
    if tabs == nil then return nil end
    for i = 1, #tabs.List do
        local tab = tabs.List[i]
        for j = 1, #tab.Panes do
            local p = tab.Panes[j]
            if p ~= nil and p.Buf ~= nil then
                if isAI and p.Buf.Path == AI_BUF_PATH then return p end
                if not isAI and p.Buf.Path ~= AI_BUF_PATH then return p end
            end
        end
    end
    return nil
end

function getOrCreateAIPane()
    local pane = findPane(true)
    if pane ~= nil then return pane end

    local aiBuf = buffer.NewBuffer("", AI_BUF_PATH)
    aiBuf.Type.Scratch = true
    aiBuf:SetOptionNative("filetype", "markdown")
    aiBuf:SetOptionNative("softwrap", true)

    local editorPane = findPane(false) or micro.CurPane()
    editorPane:VSplitBuf(aiBuf)

    return findPane(true)
end

----------------------------------------------------------------
-- Alt-i handler: prompt in infobar
----------------------------------------------------------------
function aiPrompt(bp)
    micro.InfoBar():Prompt("AI> ", "", "ai", nil,
        function(input, cancelled)
            if not cancelled and input ~= "" then
                runAI(bp, input)
            end
        end
    )
    return true
end

----------------------------------------------------------------
-- :aimodel [name]
----------------------------------------------------------------
function cmdAIModel(bp, args)
    if args ~= nil and #args > 0 then
        currentModel = args[1]
        saveModel()
        micro.InfoBar():Message("Model: " .. currentModel)
        return
    end
    local modelsFile = getPlugDir() .. "/models.txt"
    local cmd = "sh -c 'fzf --prompt=\"Model: \" --reverse < \""
        .. modelsFile .. "\"'"
    local output = shell.RunInteractiveShell(cmd, false, true)
    if output ~= nil then
        output = output:gsub("%s+$", "")
        if output ~= "" then
            currentModel = output
            saveModel()
            micro.InfoBar():Message("Model: " .. currentModel)
        end
    end
end

----------------------------------------------------------------
-- :aiclear — reset conversation
----------------------------------------------------------------
function cmdAIClear(bp, args)
    history = {}
    local pane = findPane(true)
    if pane ~= nil then
        local buf = pane.Buf
        buf:Remove(buf:Start(), buf:End())
    end
    micro.InfoBar():Message("AI: conversation cleared")
end

----------------------------------------------------------------
-- :ai <prompt> — command mode entry point
----------------------------------------------------------------
function cmdAI(bp, args)
    if #args == 0 then
        micro.InfoBar():Error("Usage: ai <prompt>")
        return
    end
    local prompt = ""
    for i = 1, #args do
        if i > 1 then prompt = prompt .. " " end
        prompt = prompt .. args[i]
    end
    runAI(bp, prompt)
end

----------------------------------------------------------------
-- core AI logic (shared by cmdAI and aiPrompt)
----------------------------------------------------------------
function runAI(bp, prompt)
    logFile("ai: called, prompt=" .. prompt)

    if aiRunning then
        micro.InfoBar():Error("AI: processing...")
        return
    end

    local ok, err = pcall(function()
        local editorPane = findPane(false) or bp
        local editorBuf = editorPane.Buf
        local cursor = editorBuf:GetActiveCursor()
        local fpath = shortenPath(editorBuf.AbsPath or editorBuf.Path or "untitled")
        local ftype = editorBuf:FileType()

        local fname = fpath:match("[^/]+$") or fpath
        local code, contextType
        if cursor:HasSelection() then
            code = util.String(cursor:GetSelection())
            contextType = "Selection"
        else
            code = util.String(editorBuf:Bytes())
            contextType = "File"
        end

        local context = contextType .. ": " .. fpath .. "\n```" .. ftype .. "\n" .. code .. "\n```"
        local fullPrompt = buildPrompt(context, prompt)
        logFile("ai: model=[" .. currentModel .. "] prompt_len=" .. tostring(#fullPrompt))

        local aiPane = getOrCreateAIPane()
        if aiPane == nil then
            micro.InfoBar():Error("AI: cannot create pane")
            return
        end

        local aiBuf = aiPane.Buf
        local prefix = ""
        if aiBuf:LinesNum() > 1 then
            prefix = "\n\n"
        end

        local displayModel = getDisplayModel()
        local contextDisplay = "Context: " .. fname
        if contextType == "Selection" then
            contextDisplay = contextDisplay .. " (Selection)"
        end
        local header = prefix
            .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            .. "Q: " .. prompt .. "\n"
            .. "Model: " .. (displayModel ~= "" and displayModel or "...") .. "\n"
            .. contextDisplay .. "\n"
            .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        aiBuf:Insert(aiBuf:End(), header)

        local tmpFile = "/tmp/micro-ai-prompt.txt"
        local f = io.open(tmpFile, "w")
        if not f then
            micro.InfoBar():Error("AI: cannot write temp file")
            return
        end
        f:write(fullPrompt)
        f:close()

        local scriptPath = getPlugDir() .. "/ai-run.sh"
        local cmd = "bash '" .. scriptPath .. "' '" .. tmpFile .. "'"
        if currentModel ~= "" then
            cmd = cmd .. " '" .. currentModel .. "'"
        end

        micro.InfoBar():Message("AI" .. modelTag(currentModel) .. ": thinking...")
        aiRunning = true
        local fullOutput = ""

        currentJob = shell.JobStart(cmd,
            function(chunk)
                fullOutput = fullOutput .. chunk
                local p = findPane(true)
                if p ~= nil then
                    p.Buf:Insert(p.Buf:End(), chunk)
                    p:GotoLoc(p.Buf:End())
                end
            end,
            function(chunk)
                logFile("ai: stderr=" .. chunk)
            end,
            function()
                aiRunning = false
                currentJob = nil
                readDetectedModel()
                config.SetGlobalOptionNative("aichat.model", getDisplayModel())
                logFile("ai: done, len=" .. tostring(#fullOutput))
                local p = findPane(true)
                if fullOutput ~= "" then
                    history[#history + 1] = {
                        prompt = prompt,
                        response = cleanForHistory(fullOutput),
                    }
                    if #history > MAX_HISTORY then
                        table.remove(history, 1)
                    end
                    micro.InfoBar():Message("AI" .. modelTag(currentModel) .. ": done")
                else
                    if p ~= nil then
                        p.Buf:Insert(p.Buf:End(), "(no response)\n")
                    end
                    micro.InfoBar():Error("AI: no response")
                end
                if p ~= nil then
                    p:GotoLoc(p.Buf:End())
                end
            end
        )
    end)

    if not ok then
        aiRunning = false
        logFile("ai: ERROR: " .. tostring(err))
        micro.InfoBar():Error("AI: " .. tostring(err))
    end
end

----------------------------------------------------------------
-- prompt builder (includes conversation history)
----------------------------------------------------------------
function buildPrompt(context, prompt)
    local result = context

    if #history > 0 then
        result = result .. "\n\nPrevious conversation:\n"
        for i = 1, #history do
            result = result .. "\nUser: " .. history[i].prompt
            result = result .. "\nAssistant: " .. history[i].response
        end
    end

    result = result .. "\n\n" .. prompt
    return result
end

function modelTag(m)
    if m ~= nil and m ~= "" then return " (" .. m .. ")" end
    return ""
end

----------------------------------------------------------------
-- pane close handler
----------------------------------------------------------------
function preQuit(bp)
    if bp.Buf ~= nil and bp.Buf.Path == AI_BUF_PATH then
        history = {}
        if currentJob ~= nil and aiRunning then
            shell.JobStop(currentJob)
            currentJob = nil
            aiRunning = false
            logFile("ai: cancelled by pane close")
        end
        logFile("ai: pane closed, history cleared")
    end
end
