local config = import("micro/config")

function init()
    if linter then
        local wrapper = config.ConfigDir .. "/plug/autoformat/cfn-lint-micro.sh"
        linter.makeLinter("cfnlint", "yaml", "sh", {wrapper, "%f"}, "%f:%l:%c:%m",
            nil, nil, nil, nil, nil, function(buf)
                return buf.Path:match("template%.yaml$") ~= nil
            end)
    end
end
