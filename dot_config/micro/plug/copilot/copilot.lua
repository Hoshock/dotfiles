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

-- Global: called from shell.JobStart callback (needs forward declaration for processLine)
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

-- Global: called from shell.JobStart exit callback
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

-- Global: forward declaration used by processLine
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
	chat.preQuit(bp)
	local uri = getURI(bp.Buf)
	if uri and openedDocs[uri] then
		sendNotify("textDocument/didClose", { textDocument = { uri = uri } })
		openedDocs[uri] = nil
		docVersions[uri] = nil
	end
end

----------------------------------------------------------------
-- Commands
----------------------------------------------------------------
function init()
	chat.init()

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
		chat.cmd(bp, args)
	end, config.NoComplete)

	config.MakeCommand("copilot-model", function(bp, args)
		chat.modelCmd(bp, args)
	end, config.NoComplete)
end
