VERSION = "1.1.0"

local micro = import("micro")
local shell = import("micro/shell")
local config = import("micro/config")
local buffer = import("micro/buffer")

-- filetype -> format commands (%f = filepath)
-- NOTE: shell.RunCommand does NOT use a shell, so &&/||/; won't work.
--       Use a list of commands to run them sequentially.
local formatters = {
	-- go       = { "gofmt -w %f" },
	html = { "prettier --write %f" },
	json = { "prettier --write %f" },
	lua = { "stylua %f" },
	markdown = { "prettier --write %f" },
	nix = { "nixfmt %f" },
	python = { "ruff check --fix %f", "ruff format %f" },
	shell = { "shfmt -w %f" },
	yaml = { "prettier --write %f" },
}

-- filetype -> file extension (for temp files)
local ft_ext = {
	html = "html",
	json = "json",
	lua = "lua",
	markdown = "md",
	nix = "nix",
	python = "py",
	shell = "sh",
	yaml = "yaml",
}

-- Run formatter commands for the given filetype on a file path.
local function runFormatters(ft, path)
	local cmds = formatters[ft]
	if not cmds then
		return false
	end
	for _, cmd in ipairs(cmds) do
		cmd = cmd:gsub("%%f", path)
		shell.RunCommand(cmd)
	end
	return true
end

-- Remove trailing blank lines, keeping a single final newline.
local function trimTrailingNewlines(path)
	local f = io.open(path, "r")
	if not f then
		return
	end
	local content = f:read("*a")
	f:close()

	local trimmed = content:gsub("\n+$", "\n")
	if trimmed == content then
		return
	end

	f = io.open(path, "w")
	if not f then
		return
	end
	f:write(trimmed)
	f:close()
end

function init()
	config.MakeCommand("format", formatCmd, config.NoComplete)
end

-- Build sorted filetype list for fzf picker.
local function formatterKeys()
	local keys = {}
	for k, _ in pairs(formatters) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

-- Pick filetype via fzf, then run formatCmd.
function formatPick(bp)
	local list = table.concat(formatterKeys(), "\n")
	local cmd = "sh -c 'echo \"" .. list .. '" | fzf --prompt="Format: " --reverse\''
	local output = shell.RunInteractiveShell(cmd, false, true)
	if output ~= nil then
		output = output:gsub("%s+$", "")
		if output ~= "" then
			formatCmd(bp, { output })
		end
	end
end

-- Format the current buffer without saving to disk.
-- Usage: format <filetype>  (e.g. "format markdown")
function formatCmd(bp, args)
	if not args or #args == 0 then
		micro.InfoBar():Error("Usage: format <filetype>")
		return
	end
	local ft = args[1]
	if not formatters[ft] then
		micro.InfoBar():Message("No formatter for filetype: " .. ft)
		return
	end

	-- Collect buffer content
	local lines = {}
	for i = 0, bp.Buf:LinesNum() - 1 do
		lines[#lines + 1] = bp.Buf:Line(i)
	end
	local content = table.concat(lines, "\n")

	-- Write to temp file and run formatters
	local ext = ft_ext[ft] or "txt"
	local tmpPath = os.tmpname() .. "." .. ext
	local f = io.open(tmpPath, "w")
	if not f then
		micro.InfoBar():Message("Failed to create temp file")
		return
	end
	f:write(content)
	f:close()
	runFormatters(ft, tmpPath)

	-- Read formatted content
	f = io.open(tmpPath, "r")
	if not f then
		os.remove(tmpPath)
		micro.InfoBar():Message("Failed to read formatted file")
		return
	end
	local formatted = f:read("*a")
	f:close()
	os.remove(tmpPath)

	if formatted == content then
		micro.InfoBar():Message("Already formatted")
		return
	end

	-- Replace buffer content (undoable)
	bp.Buf:Remove(buffer.Loc(0, 0), buffer.Loc(0, bp.Buf:LinesNum()))
	bp.Buf:Insert(buffer.Loc(0, 0), formatted)
	bp.Cursor:Relocate()
	micro.InfoBar():Message("Formatted")
end

function onSave(bp)
	local path = bp.Buf.AbsPath
	trimTrailingNewlines(path)
	runFormatters(bp.Buf:FileType(), path)
	bp.Buf:ReOpen()
	return true
end
