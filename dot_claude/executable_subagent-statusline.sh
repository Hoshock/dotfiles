#!/bin/sh
# Subagent rows in the agent panel, styled like line 2 of statusline-command.sh:
#   ✦ <model> ▸ <effort ●●●○○> · ctx <bar> <pct> · <label>
# stdin: {"columns": N, "tasks": [{id, name?, status, description, label, model?, effort?, contextWindowSize?, tokenCount}, ...]}
# stdout: one {"id": ..., "content": ...} line per task (see the statusline docs, "Subagent status lines").
# A task without effort runs on the session's effort. Take it from the latest assistant entry of the
# session transcript (transcript_path); its format is internal, so a miss just leaves effort out.
input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
session_effort=""
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
    session_effort=$(tail -n 200 "$transcript" |
        jq -r 'select(.type == "assistant") | .effort // empty' 2>/dev/null | tail -n 1)
fi
printf '%s' "$input" | exec jq -c --arg session_effort "$session_effort" '
def esc: "\u001b[";
def fg($rgb): esc + "38;2;" + $rgb + "m";
def rst: esc + "0m";
def gray: fg("168;153;132");
def track: fg("80;73;69");
# display width: count East Asian wide characters as 2
def width: [explode[] | if . >= 4352 then 2 else 1 end] | add // 0;
def clip($w):
    if width <= $w then .
    else reduce explode[] as $c ({s: "", w: 0};
        (if $c >= 4352 then 2 else 1 end) as $cw
        | if .w + $cw <= $w - 1 then .s += ([$c] | implode) | .w += $cw else . end)
        | .s + "…"
    end;
# claude-fable-5-1 -> Fable 5.1
def model_name:
    sub("^claude-"; "") | sub("\\[.*\\]$"; "")
    | capture("^(?<n>[a-z]+)-(?<v>[0-9]+(-[0-9]+)?)")? // {n: ., v: ""}
    | (.n[:1] | ascii_upcase) + .n[1:] + (if .v == "" then "" else " " + (.v | gsub("-"; ".")) end);
def effort_seg:
    if . == null then ""
    elif type == "number" then " " + gray + "▸" + rst + " " + gray + (tostring) + rst
    else
        ({low: [1, "168;153;132"], medium: [2, "142;192;124"], high: [3, "250;189;47"],
          xhigh: [4, "254;128;25"]}[.] // [5, "251;73;52"]) as [$lv, $c]
        | " " + gray + "▸" + rst + " " + fg($c) + . + " "
          + ([range(1; 6) | if . <= $lv then fg($c) + "●" else track + "○" end] | join("")) + rst
    end;
def pct_color: if . >= 80 then fg("251;73;52") elif . >= 50 then fg("250;189;47") else fg("184;187;38") end;
def ctx_seg($tokens; $size):
    if ($size // 0) > 0 then
        (($tokens * 100 / $size) | floor) as $p
        | ([($p * 12 / 100) | floor, 12] | min) as $f
        | ($p | pct_color) as $cc
        | gray + "ctx " + $cc + ("━" * $f // "") + track + ("━" * (12 - $f) // "") + " " + $cc + "\($p)%" + rst
    else gray + "ctx " + track + ("━" * 12) + " " + gray + "--" + rst
    end;

(.columns // 80) as $cols
| .tasks[]?
| (.status // "running") as $st
| (if $st == "running" then "" elif $st == "completed" then fg("184;187;38") + "✓ " + rst else fg("251;73;52") + "✗ " + rst end) as $mark
| (if .model then fg("211;134;155") + "✦ " + esc + "1m" + (.model | model_name) + esc + "22m" + rst else gray + "✦ …" + rst end) as $m
| ($mark + $m + ((.effort // (if $session_effort == "" then null else $session_effort end)) | effort_seg) + gray + " · " + rst + ctx_seg(.tokenCount // 0; .contextWindowSize)) as $head
# visible width of $head without escapes, then fit the label into the rest
| ($head | gsub("\u001b\\[[0-9;]*m"; "") | width) as $hw
| ([.name, (.label // .description)] | map(select(. != null and . != "")) | if length == 2 and .[0] == .[1] then .[:1] else . end | join(" · ")) as $text
| ($cols - $hw - 3) as $room
| {id, content: ($head + (if $room >= 6 and $text != "" then gray + " · " + ($text | clip($room)) + rst else "" end))}
'
