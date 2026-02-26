local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")

local HOME = os.getenv("HOME") or ""

function shortname(buf)
	if buf == nil then
		return ""
	end
	local path = buf:GetName()
	if HOME ~= "" and path:sub(1, #HOME) == HOME then
		return "~" .. path:sub(#HOME + 1)
	end
	return path
end

-- Ctrl-k: kill line or partial line.
-- At column 0: delete entire line.
-- At or past end of line: join with next line.
-- Otherwise: delete from cursor to end of line.
function killLine(bp)
	local line = bp.Buf:Line(bp.Cursor.Y)
	local col = bp.Cursor.X
	local lineLen = #line
	local y = bp.Cursor.Y
	if col == 0 then
		-- At beginning of line: delete entire line
		local numLines = bp.Buf:LinesNum()
		if y < numLines - 1 then
			bp.Buf:Remove(buffer.Loc(0, y), buffer.Loc(0, y + 1))
		elseif y > 0 then
			local prevLen = #bp.Buf:Line(y - 1)
			bp.Buf:Remove(buffer.Loc(prevLen, y - 1), buffer.Loc(0, y))
		end
	elseif col >= lineLen then
		bp.Buf:Remove(buffer.Loc(lineLen, y), buffer.Loc(0, y + 1))
	else
		bp.Buf:Remove(buffer.Loc(col, y), buffer.Loc(lineLen, y))
	end
	bp.Cursor:Relocate()
	bp:Relocate()
end

function init()
	micro.SetStatusInfoFn("initlua.shortname")

	if linter then
		local wrapper = config.ConfigDir .. "/plug/formatter/cfn-lint-micro.sh"
		linter.makeLinter(
			"cfnlint",
			"yaml",
			"sh",
			{ wrapper, "%f" },
			"%f:%l:%c:%m",
			nil,
			nil,
			nil,
			nil,
			nil,
			function(buf)
				return buf.Path:match("template%.yaml$") ~= nil
			end
		)
	end
end
