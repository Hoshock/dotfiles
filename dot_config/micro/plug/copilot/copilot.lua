VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local util = import("micro/util")

----------------------------------------------------------------
-- Inline Completion State
----------------------------------------------------------------
local lspJob = nil
local reqFilePath = nil
local requestId = 0
local pendingCallbacks = {}
local lspReady = false
local lspStarting = false
local openedDocs = {}
local docVersions = {}
local currentSuggestion = nil
local suggestionBuf = nil
local suggestionVersion = 0
local responseBuf = ""
local previewBuf = nil

----------------------------------------------------------------
-- Chat State
----------------------------------------------------------------
local AI_BUF_PATH = "[AI]"
local currentModel = ""
local lastDetectedModel = ""
local CHAT_LOG = "/tmp/micro-copilot-chat.log"
local MODEL_FILE = "/tmp/micro-copilot-lastmodel.txt"
local SAVED_MODEL_FILE = ""
local MAX_HISTORY = 5
local MAX_HISTORY_CHARS = 2000
local aiRunning = false
local currentJob = nil
local HOME = os.getenv("HOME") or ""
local chatHistory = {}

----------------------------------------------------------------
-- JSON-RPC transport (Content-Length framing to .req file)
----------------------------------------------------------------
local function sendFrame(tbl)
	if not reqFilePath then
		return false
	end
	local encoded = json.encode(tbl)
	local frame = "Content-Length: " .. #encoded .. "\r\n\r\n" .. encoded
	local f = io.open(reqFilePath, "ab")
	if not f then
		return false
	end
	f:write(frame)
	f:flush()
	f:close()
	return true
end

local function sendRPC(method, params, callback)
	requestId = requestId + 1
	local id = requestId
	if not sendFrame({ jsonrpc = "2.0", id = id, method = method, params = params }) then
		return nil
	end
	if callback then
		pendingCallbacks[id] = callback
	end
	return id
end

local function sendNotify(method, params)
	sendFrame({ jsonrpc = "2.0", method = method, params = params })
end

local function respondToServer(id, result)
	sendFrame({ jsonrpc = "2.0", id = id, result = result })
end

----------------------------------------------------------------
-- Message dispatch
----------------------------------------------------------------
local function handleServerRequest(msg)
	if msg.method == "window/showDocument" then
		if msg.params and msg.params.uri then
			local uri = msg.params.uri:gsub("'", "")
			os.execute("open '" .. uri .. "' &")
		end
		if msg.id then
			respondToServer(msg.id, { success = true })
		end
	elseif msg.method == "window/showMessageRequest" then
		if msg.params and msg.params.message then
			micro.InfoBar():Message("Copilot: " .. msg.params.message)
		end
		if msg.id then
			respondToServer(msg.id, json.null)
		end
	end
end

local function handleMessage(msg)
	if msg.id and msg.id ~= json.null then
		local cb = pendingCallbacks[msg.id]
		if cb then
			pendingCallbacks[msg.id] = nil
			cb(msg.result, msg.error)
		end
	elseif msg.method then
		handleServerRequest(msg)
	end
end

----------------------------------------------------------------
-- Response parser (JSONL from proxy stdout)
----------------------------------------------------------------
local function processLine(line)
	if line:match("^REQ:") then
		reqFilePath = line:gsub("%s+$", ""):match("^REQ:(.+)")
		doInitialize()
	elseif (lspStarting or lspReady) and #line > 0 then
		local ok, msg = pcall(json.decode, line)
		if ok and type(msg) == "table" and msg.jsonrpc then
			handleMessage(msg)
		end
	end
end

function onStdout(rawData)
	responseBuf = responseBuf .. rawData:gsub("\r", "")
	while true do
		local pos = responseBuf:find("\n")
		if not pos then
			break
		end
		processLine(responseBuf:sub(1, pos - 1))
		responseBuf = responseBuf:sub(pos + 1)
	end
	if #responseBuf > 100000 then
		responseBuf = ""
	end
end

function onExit()
	lspReady = false
	lspStarting = false
	lspJob = nil
	reqFilePath = nil
	openedDocs = {}
	docVersions = {}
	responseBuf = ""
end

----------------------------------------------------------------
-- LSP lifecycle
----------------------------------------------------------------
local function startLSP()
	if lspJob or lspStarting then
		return
	end
	lspStarting = true
	local script = config.ConfigDir .. "/plug/copilot/copilot-proxy.py"
	lspJob = shell.JobStart("python3 -u '" .. script .. "'", function(out)
		onStdout(out)
	end, function() end, function()
		onExit()
	end)
	if not lspJob then
		micro.InfoBar():Error("Copilot: failed to start")
		lspStarting = false
	end
end

local function stopLSP()
	reqFilePath = nil
	if lspJob then
		shell.JobStop(lspJob)
		lspJob = nil
	end
	lspReady = false
	lspStarting = false
	openedDocs = {}
	docVersions = {}
	currentSuggestion = nil
	suggestionBuf = nil
	previewBuf = nil
	micro.InfoBar():Message("Copilot: stopped")
end

-- forward declaration used by processLine
function doInitialize()
	sendRPC("initialize", {
		processId = json.null,
		capabilities = {
			textDocument = {
				synchronization = { dynamicRegistration = false, didSave = false },
				inlineCompletion = { dynamicRegistration = false },
			},
		},
		initializationOptions = {
			editorInfo = { name = "micro", version = "2.0" },
			editorPluginInfo = { name = "micro-copilot", version = VERSION },
		},
		rootUri = json.null,
	}, function(_, err)
		if err then
			micro.InfoBar():Error("Copilot: init failed")
			return
		end
		sendNotify("initialized", {})
		lspReady = true
		lspStarting = false
		micro.InfoBar():Message("Copilot: ready")
	end)
end

----------------------------------------------------------------
-- Document sync (full-text on every change)
----------------------------------------------------------------
local function getURI(buf)
	local path = buf.AbsPath or buf.Path
	if not path or path == "" then
		return nil
	end
	return "file://" .. path
end

local function getLanguageId(buf)
	local ft = buf:FileType()
	if ft == "shell" then
		return "shellscript"
	end
	if ft == "unknown" then
		return "plaintext"
	end
	return ft
end

local function ensureDocOpen(bp)
	if not lspReady then
		return false
	end
	local uri = getURI(bp.Buf)
	if not uri then
		return false
	end
	if openedDocs[uri] then
		return true
	end
	docVersions[uri] = 1
	sendNotify("textDocument/didOpen", {
		textDocument = {
			uri = uri,
			languageId = getLanguageId(bp.Buf),
			version = 1,
			text = util.String(bp.Buf:Bytes()),
		},
	})
	openedDocs[uri] = true
	return true
end

local function sendDidChange(bp)
	local uri = getURI(bp.Buf)
	if not uri or not openedDocs[uri] then
		return
	end
	docVersions[uri] = (docVersions[uri] or 0) + 1
	sendNotify("textDocument/didChange", {
		textDocument = { uri = uri, version = docVersions[uri] },
		contentChanges = { { text = util.String(bp.Buf:Bytes()) } },
	})
end

----------------------------------------------------------------
-- Preview pane (multiline suggestions)
----------------------------------------------------------------
local function setPreviewContent(text)
	if not previewBuf then
		return false
	end
	local ok = pcall(function()
		previewBuf.Type.Readonly = false
		previewBuf:Remove(buffer.Loc(0, 0), buffer.Loc(0, previewBuf:LinesNum()))
		previewBuf:Insert(buffer.Loc(0, 0), text)
		previewBuf.Type.Readonly = true
	end)
	if not ok then
		previewBuf = nil
	end
	return ok
end

local function showPreview(text, bp)
	if setPreviewContent(text) then
		return
	end
	previewBuf = buffer.NewBuffer(text, "copilot-preview")
	previewBuf.Type.Scratch = true
	previewBuf.Type.Readonly = true
	bp:HSplitBuf(previewBuf)
end

local function clearPreview()
	setPreviewContent("")
end

----------------------------------------------------------------
-- Inline completion
----------------------------------------------------------------
local function clearSuggestion()
	currentSuggestion = nil
	suggestionBuf = nil
	clearPreview()
end

local function onCompletionResult(result, bp)
	if not result then
		return
	end
	local items = result.items or result
	if type(items) ~= "table" or #items == 0 then
		return
	end
	local item = items[1]
	local text = item.insertText
	if type(text) == "table" then
		text = text.value
	end
	if not text or text == "" then
		return
	end

	suggestionBuf = bp
	currentSuggestion = { text = text, range = item.range, command = item.command }

	local firstLine = text:match("^([^\n]*)") or text
	local lineCount = select(2, text:gsub("\n", "")) + 1

	if lineCount > 1 then
		showPreview(text, bp)
		micro.InfoBar():Message(">> " .. firstLine .. "  [+" .. (lineCount - 1) .. " lines]  [Tab]")
	else
		clearPreview()
		micro.InfoBar():Message(">> " .. firstLine .. "  [Tab]")
	end
end

local function requestCompletion(bp)
	if not lspReady or not ensureDocOpen(bp) then
		return
	end
	local uri = getURI(bp.Buf)
	if not uri then
		return
	end

	sendDidChange(bp)

	local cursor = bp.Buf:GetActiveCursor()
	suggestionVersion = suggestionVersion + 1
	local myVersion = suggestionVersion

	sendRPC("textDocument/inlineCompletion", {
		textDocument = { uri = uri, version = docVersions[uri] or 1 },
		position = { line = cursor.Y, character = cursor.X },
		context = { triggerKind = 2 },
		formattingOptions = {
			tabSize = bp.Buf.Settings["tabsize"] or 4,
			insertSpaces = bp.Buf.Settings["tabstospaces"] or true,
		},
	}, function(result, err)
		if err or myVersion ~= suggestionVersion then
			return
		end
		onCompletionResult(result, bp)
	end)
end

local function acceptSuggestion(bp)
	if not currentSuggestion then
		return false
	end
	local text = currentSuggestion.text
	local range = currentSuggestion.range
	local command = currentSuggestion.command

	if range then
		local startLoc = buffer.Loc(range.start.character, range.start.line)
		local endLoc = buffer.Loc(range["end"].character, range["end"].line)
		bp.Buf:Remove(startLoc, endLoc)
		bp.Buf:Insert(startLoc, text)
	else
		local cursor = bp.Buf:GetActiveCursor()
		bp.Buf:Insert(buffer.Loc(cursor.X, cursor.Y), text)
	end

	if command and command.command then
		sendRPC("workspace/executeCommand", {
			command = command.command,
			arguments = command.arguments or json.array({}),
		}, nil)
	end

	clearSuggestion()
	micro.InfoBar():Message("")
	return true
end

----------------------------------------------------------------
-- Chat: logging
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
-- Chat: model management
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

local function readDetectedModel()
	pcall(function()
		local f = io.open(MODEL_FILE, "r")
		if f then
			local m = f:read("*l")
			f:close()
			if m and m ~= "" then
				lastDetectedModel = m
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
-- Chat: response cleaning
----------------------------------------------------------------
local function isToolHeader(line)
	if #line < 3 then
		return false
	end
	local b1, b2, b3 = line:byte(1, 3)
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
	if #cleaned > MAX_HISTORY_CHARS then
		cleaned = cleaned:sub(#cleaned - MAX_HISTORY_CHARS + 1)
	end
	return cleaned
end

----------------------------------------------------------------
-- Chat: pane management
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
-- Chat: prompt builder
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
-- Chat: core logic
----------------------------------------------------------------
local function runChat(bp, prompt)
	chatLog("chat: called, prompt=" .. prompt)

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

		local scriptPath = config.ConfigDir .. "/plug/copilot/ai-run.sh"
		local cmd = "bash '" .. scriptPath .. "' '" .. tmpFile .. "'"
		if currentModel ~= "" then
			cmd = cmd .. " '" .. currentModel .. "'"
		end

		micro.InfoBar():Message("AI" .. modelTag(currentModel) .. ": thinking...")
		aiRunning = true
		local fullOutput = ""

		currentJob = shell.JobStart(cmd, function(chunk)
			fullOutput = fullOutput .. chunk
			local p = findPane(true)
			if p ~= nil then
				p.Buf:Insert(p.Buf:End(), chunk)
				p:GotoLoc(p.Buf:End())
			end
		end, function(chunk)
			chatLog("chat: stderr=" .. chunk)
		end, function()
			aiRunning = false
			currentJob = nil
			readDetectedModel()
			config.SetGlobalOptionNative("copilot.model", getDisplayModel())
			local p = findPane(true)
			if fullOutput ~= "" then
				chatHistory[#chatHistory + 1] = {
					prompt = prompt,
					response = cleanForHistory(fullOutput),
				}
				if #chatHistory > MAX_HISTORY then
					table.remove(chatHistory, 1)
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
		end)
	end)

	if not ok then
		aiRunning = false
		chatLog("chat: ERROR: " .. tostring(err))
		micro.InfoBar():Error("AI: " .. tostring(err))
	end
end

----------------------------------------------------------------
-- Event hooks
----------------------------------------------------------------
function onRune(bp, r)
	if bp.Buf.Type.Scratch then
		return
	end
	clearSuggestion()
	if lspReady then
		requestCompletion(bp)
	elseif not lspStarting and not lspJob then
		startLSP()
	end
end

function onBackspace(bp)
	clearSuggestion()
	if lspReady then
		requestCompletion(bp)
	end
end

function onDelete(bp)
	clearSuggestion()
	if lspReady then
		requestCompletion(bp)
	end
end

function preInsertTab(bp)
	if currentSuggestion and suggestionBuf == bp then
		acceptSuggestion(bp)
		return false
	end
	return true
end

function preEscape(bp)
	if currentSuggestion then
		clearSuggestion()
		micro.InfoBar():Message("")
		return false
	end
	return true
end

function onBufPaneOpen(bp)
	if not bp.Buf.Type.Scratch and lspReady then
		ensureDocOpen(bp)
	end
end

function preQuit(bp)
	-- Chat pane close: clear history and stop running job
	if bp.Buf ~= nil and bp.Buf.Path == AI_BUF_PATH then
		chatHistory = {}
		if currentJob ~= nil and aiRunning then
			shell.JobStop(currentJob)
			currentJob = nil
			aiRunning = false
		end
	end
	-- LSP doc close: notify server
	local uri = getURI(bp.Buf)
	if uri and openedDocs[uri] then
		sendNotify("textDocument/didClose", { textDocument = { uri = uri } })
		openedDocs[uri] = nil
		docVersions[uri] = nil
	end
end

-- Alt-i handler: prompt in infobar
function aiPrompt(bp)
	micro.InfoBar():Prompt("AI> ", "", "ai", nil, function(input, cancelled)
		if not cancelled and input ~= "" then
			runChat(bp, input)
		end
	end)
	return true
end

-- Alt-m handler: fzf model picker
function cmdAIModel(bp)
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

----------------------------------------------------------------
-- Commands
----------------------------------------------------------------
function init()
	SAVED_MODEL_FILE = config.ConfigDir .. "/.copilot-model"
	config.RegisterCommonOption("copilot", "model", "")

	-- Inline completion
	config.MakeCommand("copilot-lsp-start", function(bp)
		if lspReady or lspStarting then
			micro.InfoBar():Message("Copilot: already running")
		else
			startLSP()
		end
	end, config.NoComplete)

	config.MakeCommand("copilot-lsp-stop", function()
		stopLSP()
	end, config.NoComplete)

	config.MakeCommand("copilot-auth", function(bp)
		if not lspReady then
			micro.InfoBar():Error("Copilot: LSP not running. Run :copilot-lsp-start first")
			return
		end
		sendRPC("signIn", {}, function(result, err)
			if err then
				micro.InfoBar():Error("Copilot: auth error")
				return
			end
			if result and result.userCode then
				micro.InfoBar():Message("Copilot: enter code " .. result.userCode .. " at github.com/login/device")
				os.execute("open 'https://github.com/login/device' &")
			elseif result and result.status == "OK" then
				micro.InfoBar():Message("Copilot: already authenticated")
			else
				micro.InfoBar():Message("Copilot: auth response received")
			end
		end)
	end, config.NoComplete)

	config.MakeCommand("copilot-preview", function(bp)
		if not currentSuggestion then
			micro.InfoBar():Message("Copilot: no suggestion")
			return
		end
		showPreview(currentSuggestion.text, bp)
	end, config.NoComplete)

	-- Chat
	config.MakeCommand("copilot-chat", function(bp, args)
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
	end, config.NoComplete)

	config.MakeCommand("copilot-model", function(bp, args)
		if args ~= nil and #args > 0 then
			currentModel = args[1]
			saveModel()
			micro.InfoBar():Message("Model: " .. currentModel)
			return
		end
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
	end, config.NoComplete)

	-- Load saved model
	loadModel()
	readDetectedModel()
	config.SetGlobalOptionNative("copilot.model", getDisplayModel())
end
