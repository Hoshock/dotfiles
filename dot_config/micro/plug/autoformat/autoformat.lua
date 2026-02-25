VERSION = "1.0.0"

local shell = import("micro/shell")

-- filetype -> format commands (%f = filepath)
-- NOTE: shell.RunCommand does NOT use a shell, so &&/||/; won't work.
--       Use a list of commands to run them sequentially.
local formatters = {
    -- go       = { "gofmt -w %f" },
    html       = { "prettier --write %f" },
    json       = { "prettier --write %f" },
    -- lua      = { "stylua %f" },
    markdown   = { "prettier --write %f" },
    -- nix      = { "nixfmt %f" },
    python     = { "ruff check --fix %f", "ruff format %f" },
    shell      = { "shfmt -w %f" },
    yaml       = { "prettier --write %f" },
}

-- Remove trailing blank lines, keeping a single final newline.
local function trimTrailingNewlines(path)
    local f = io.open(path, "r")
    if not f then return end
    local content = f:read("*a")
    f:close()

    local trimmed = content:gsub("\n+$", "\n")
    if trimmed == content then return end

    f = io.open(path, "w")
    if not f then return end
    f:write(trimmed)
    f:close()
end

function onSave(bp)
    local path = bp.Buf.AbsPath
    trimTrailingNewlines(path)

    local ft = bp.Buf:FileType()
    local cmds = formatters[ft]
    if cmds then
        for _, cmd in ipairs(cmds) do
            cmd = cmd:gsub("%%f", path)
            shell.RunCommand(cmd)
        end
    end

    bp.Buf:ReOpen()
    return true
end
