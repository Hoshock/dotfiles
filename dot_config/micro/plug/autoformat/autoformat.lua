VERSION = "1.0.0"

local shell = import("micro/shell")

-- filetype -> format command (%f = filepath)
local formatters = {
    -- go       = "gofmt -w %f",
    json       = "prettier --write %f",
    -- lua      = "stylua %f",
    markdown   = "prettier --write %f",
    -- nix      = "nixfmt %f",
    python     = "ruff check --fix %f && ruff format %f",
    shell      = "shfmt -w %f",
    yaml       = "prettier --write %f",
    zsh        = "shfmt -w %f",
}

function onSave(bp)
    local ft = bp.Buf:FileType()
    local cmd = formatters[ft]
    if cmd == nil then
        return true
    end

    local path = bp.Buf.AbsPath
    cmd = cmd:gsub("%%f", path)
    shell.RunCommand(cmd)
    bp.Buf:ReOpen()
    return true
end
