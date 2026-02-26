local config = import("micro/config")
local buffer = import("micro/buffer")

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
	if linter then
		local wrapper = config.ConfigDir .. "/plug/autoformat/cfn-lint-micro.sh"
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
