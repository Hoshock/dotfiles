-- chat.lua — AI chat subsystem
-- Public API: chat table + aiPrompt/cmdAIModel globals (for keybindings)

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local util = import("micro/util")

chat = {}

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local AI_BUF_PATH = "[AI]"
local currentModel = ""
local lastDetectedModel = ""
local CHAT_LOG = "/tmp/micro-copilot-chat.log"
local SAVED_MODEL_FILE = ""
local MAX_HISTORY_CHARS = 10000
local aiRunning = false
local currentJob = nil
local HOME = os.getenv("HOME") or ""
local chatHistory = {}

----------------------------------------------------------------
-- Logging
----------------------------------------------------------------
local function chatLog(msg)
	pcall(function()
		local f = io.open(CHAT_LOG, "a")
		if f then
			f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
			f:close()
		end
	end)
end

----------------------------------------------------------------
-- Model management
----------------------------------------------------------------
local function getDisplayModel()
	if currentModel ~= "" then
		return currentModel
	end
	if lastDetectedModel ~= "" then
		return lastDetectedModel
	end
	return ""
end

local function saveModel()
	pcall(function()
		local f = io.open(SAVED_MODEL_FILE, "w")
		if f then
			f:write(currentModel)
			f:close()
		end
	end)
	config.SetGlobalOptionNative("copilot.model", getDisplayModel())
end

local function loadModel()
	pcall(function()
		local f = io.open(SAVED_MODEL_FILE, "r")
		if f then
			local m = f:read("*l")
			f:close()
			if m and m ~= "" then
				currentModel = m
			end
		end
	end)
end

local function modelTag(m)
	if m ~= nil and m ~= "" then
		return " (" .. m .. ")"
	end
	return ""
end

----------------------------------------------------------------
-- History usage tracking
----------------------------------------------------------------
local function historyChars()
	local total = 0
	for i = 1, #chatHistory do
		total = total + #chatHistory[i].prompt + #chatHistory[i].response
	end
	return total
end

----------------------------------------------------------------
-- Response cleaning (strip tool output from history context)
----------------------------------------------------------------
local function isToolHeader(line)
	if #line < 3 then
		return false
	end
	local b1, b2, b3 = line:byte(1, 3)
	-- U+25CF "●" = 226 151 143, U+2717 "✗" = 226 156 151
	if b1 == 226 then
		if b2 == 151 and b3 == 143 then
			return true
		end
		if b2 == 156 and b3 == 151 then
			return true
		end
	end
	return false
end

local function stripToolLogs(text)
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
				-- still in tool block
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

local function cleanForHistory(text)
	local cleaned = stripToolLogs(text)
	-- Per-entry cap: half of total budget so one entry can't monopolize
	local cap = math.floor(MAX_HISTORY_CHARS / 2)
	if #cleaned > cap then
		cleaned = cleaned:sub(#cleaned - cap + 1)
	end
	return cleaned
end

local function trimHistory()
	while #chatHistory > 0 and historyChars() > MAX_HISTORY_CHARS do
		table.remove(chatHistory, 1)
	end
end

----------------------------------------------------------------
-- Pane management
----------------------------------------------------------------
local function shortenPath(path)
	if HOME ~= "" and path:sub(1, #HOME) == HOME then
		return "~" .. path:sub(#HOME + 1)
	end
	return path
end

local function findPane(isAI)
	local tabs = micro.Tabs()
	if tabs == nil then
		return nil
	end
	for i = 1, #tabs.List do
		local tab = tabs.List[i]
		for j = 1, #tab.Panes do
			local p = tab.Panes[j]
			if p ~= nil and p.Buf ~= nil then
				if isAI and p.Buf.Path == AI_BUF_PATH then
					return p
				end
				if not isAI and p.Buf.Path ~= AI_BUF_PATH then
					return p
				end
			end
		end
	end
	return nil
end

local function getOrCreateAIPane()
	local pane = findPane(true)
	if pane ~= nil then
		return pane
	end

	local aiBuf = buffer.NewBuffer("", AI_BUF_PATH)
	aiBuf.Type.Scratch = true
	aiBuf:SetOptionNative("filetype", "markdown")
	aiBuf:SetOptionNative("softwrap", true)

	local editorPane = findPane(false) or micro.CurPane()
	editorPane:VSplitBuf(aiBuf)

	return findPane(true)
end

----------------------------------------------------------------
-- Prompt builder
----------------------------------------------------------------
local function buildPrompt(context, prompt)
	local result = context
	if #chatHistory > 0 then
		result = result .. "\n\nPrevious conversation:\n"
		for i = 1, #chatHistory do
			result = result .. "\nUser: " .. chatHistory[i].prompt
			result = result .. "\nAssistant: " .. chatHistory[i].response
		end
	end
	result = result .. "\n\n" .. prompt
	return result
end

----------------------------------------------------------------
-- Core chat logic
----------------------------------------------------------------
local function runChat(bp, prompt)
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
		local histInfo = "History: "
			.. #chatHistory
			.. " turns ("
			.. historyChars()
			.. "/"
			.. MAX_HISTORY_CHARS
			.. " chars)"
		local header = prefix
			.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
			.. "Q: "
			.. prompt
			.. "\n"
			.. "Model: "
			.. (displayModel ~= "" and displayModel or "...")
			.. "\n"
			.. contextDisplay
			.. "\n"
			.. histInfo
			.. "\n"
			.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
		aiBuf:Insert(aiBuf:End(), header)

		-- Write prompt to temp file for safe shell argument passing
		local tmpFile = os.tmpname()
		local f = io.open(tmpFile, "w")
		if not f then
			micro.InfoBar():Error("AI: cannot write temp file")
			return
		end
		f:write(fullPrompt)
		f:close()

		-- Build command: read prompt from file, pass as argument to copilot CLI
		local cmd = 'bash -c \'exec copilot -p "$(<"$1")" --allow-tool write'
		if currentModel ~= "" then
			cmd = cmd .. ' --model "$2"'
		end
		cmd = cmd .. "' _ '" .. tmpFile .. "'"
		if currentModel ~= "" then
			cmd = cmd .. " '" .. currentModel .. "'"
		end

		micro.InfoBar():Message("AI" .. modelTag(currentModel) .. ": thinking...")
		aiRunning = true
		local fullOutput = ""
		local stderrBuf = ""

		currentJob = shell.JobStart(cmd, function(chunk)
			fullOutput = fullOutput .. chunk
			local p = findPane(true)
			if p ~= nil then
				p.Buf:Insert(p.Buf:End(), chunk)
				p:GotoLoc(p.Buf:End())
			end
		end, function(chunk)
			stderrBuf = stderrBuf .. chunk
		end, function()
			aiRunning = false
			currentJob = nil
			os.remove(tmpFile)

			-- Extract model name from copilot CLI stderr
			local detected = stderrBuf:match("Breakdown by AI model[^\n]*\n%s*(%S+)")
			if detected and detected ~= "" then
				lastDetectedModel = detected
			end
			if stderrBuf ~= "" then
				chatLog(stderrBuf)
			end

			config.SetGlobalOptionNative("copilot.model", getDisplayModel())
			local p = findPane(true)
			if fullOutput ~= "" then
				chatHistory[#chatHistory + 1] = {
					prompt = prompt,
					response = cleanForHistory(fullOutput),
				}
				trimHistory()
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
		end)
	end)

	if not ok then
		aiRunning = false
		chatLog("chat: ERROR: " .. tostring(err))
		micro.InfoBar():Error("AI: " .. tostring(err))
	end
end

----------------------------------------------------------------
-- Public API (called from copilot.lua)
----------------------------------------------------------------
function chat.init()
	SAVED_MODEL_FILE = config.ConfigDir .. "/.copilot-model"
	config.RegisterCommonOption("copilot", "model", "")
	loadModel()
	config.SetGlobalOptionNative("copilot.model", getDisplayModel())
end

function chat.run(bp, prompt)
	runChat(bp, prompt)
end

function chat.cmd(bp, args)
	if #args == 0 then
		micro.InfoBar():Error("Usage: copilot-chat <prompt>")
		return
	end
	local prompt = ""
	for i = 1, #args do
		if i > 1 then
			prompt = prompt .. " "
		end
		prompt = prompt .. args[i]
	end
	runChat(bp, prompt)
end

function chat.modelCmd(bp, args)
	if args and #args > 0 then
		currentModel = args[1]
		saveModel()
		micro.InfoBar():Message("Model: " .. currentModel)
		return
	end
	-- fzf picker
	local modelsFile = config.ConfigDir .. "/plug/copilot/models.txt"
	local cmd = 'sh -c \'fzf --prompt="Model: " --reverse < "' .. modelsFile .. "\"'"
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

function chat.preQuit(bp)
	if bp.Buf ~= nil and bp.Buf.Path == AI_BUF_PATH then
		chatHistory = {}
		if currentJob ~= nil and aiRunning then
			shell.JobStop(currentJob)
			currentJob = nil
			aiRunning = false
		end
	end
end

----------------------------------------------------------------
-- Global handlers (for keybindings: lua:copilot.aiPrompt etc.)
----------------------------------------------------------------
function aiPrompt(bp)
	micro.InfoBar():Prompt("AI> ", "", "ai", nil, function(input, cancelled)
		if not cancelled and input ~= "" then
			runChat(bp, input)
		end
	end)
	return true
end

function cmdAIModel(bp)
	chat.modelCmd(bp)
end
