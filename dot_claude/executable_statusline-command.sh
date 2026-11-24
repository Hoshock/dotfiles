#!/bin/sh
# Two-line status line.
#   line 1: same layout as the starship prompt (~/.config/starship.toml):
#           [repo] [dir] [branch + status] [time]
#   line 2: [model] [effort ●●●○○]  ctx bar  mode
# VCS: jj is preferred when the directory is a jj repo (colocated or not), otherwise git.
input=$(cat)
set -f # no globbing: "*" / "?" in values must stay literal

# ---------- palette (gruvbox_dark, same as starship) ----------
ESC=$(printf '\033')
RST="${ESC}[0m"
C_FG0="251;241;199"
C_BG0="29;32;33"
C_BG1="60;56;54"
C_ORANGE="214;93;14"
C_YELLOW="215;153;33"
C_AQUA="104;157;106"
C_PURPLE="177;98;134"
# bright variants for text / backgrounds that must stand out
C_GRAY="168;153;132"
C_B_GREEN="184;187;38"
C_B_YELLOW="250;189;47"
C_B_ORANGE="254;128;25"
C_B_RED="251;73;52"
C_B_AQUA="142;192;124"
C_TRACK="80;73;69"

fg() { printf '%s[38;2;%sm' "$ESC" "$1"; }
bgc() { printf '%s[48;2;%sm' "$ESC" "$1"; }

# ---------- glyphs (Nerd Font) ----------
CAP_L=$(printf '\356\202\266')
ARROW=$(printf '\356\202\260')
CAP_R=$(printf '\356\202\264')
I_GIT=$(printf '\363\260\212\242')
I_JJ=$(printf '\363\261\227\206')
I_DIR=$(printf '\363\260\235\260')
I_PROJECTS=$(printf '\363\260\262\213')
I_BRANCH=$(printf '\357\220\230')
I_CLOCK=$(printf '\357\220\272')

# ---------- powerline segment builder ----------
seg_out=""
prev=""
# add_seg <bg rgb> <fg rgb> <text>   (text may contain fg-only escapes)
add_seg() {
    if [ -z "$prev" ]; then
        # first segment: no leading space (the cap glyph already pads, as in starship)
        seg_out="${seg_out}$(fg "$1")${CAP_L}$(bgc "$1")$(fg "$2")$3 "
    else
        seg_out="${seg_out}$(fg "$prev")$(bgc "$1")${ARROW}$(fg "$2") $3 "
    fi
    prev=$1
}
end_segs() {
    [ -n "$prev" ] && seg_out="${seg_out}${RST}$(fg "$prev")${CAP_R}${RST}"
    prev=""
}

# pct_color <int>: green < 50 <= yellow < 80 <= red
pct_color() {
    if [ "$1" -ge 80 ]; then
        fg "$C_B_RED"
    elif [ "$1" -ge 50 ]; then
        fg "$C_B_YELLOW"
    else
        fg "$C_B_GREEN"
    fi
}

# ---------- parse stdin (single jq call; unit separator avoids empty-field collapse) ----------
fields=$(echo "$input" | jq -r '[
    .model.display_name // "",
    .effort.level // "",
    .context_window.used_percentage // "",
    .workspace.current_dir // .cwd // "",
    (.prompt_cache.warm | if . == null then "" else tostring end),
    .prompt_cache.expires_at // "",
    .prompt_cache.hit_ratio // "",
    .context_window.current_usage.cache_read_input_tokens // "",
    .context_window.current_usage.cache_creation_input_tokens // "",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.seven_day.resets_at // "",
    .cost.total_cost_usd // ""
] | map(tostring) | join("\u001f")')
OLDIFS=$IFS
IFS=$(printf '\037')
# shellcheck disable=SC2086
set -- $fields
IFS=$OLDIFS
model=$1
effort=$2
ctx_used=$3
cwd=$4
cache_warm=$5
cache_exp=$6
cache_hit=$7
cache_r=$8
cache_w=$9
rl5_pct=${10}
rl5_reset=${11}
rl7_pct=${12}
rl7_reset=${13}
cost_usd=${14}

if [ -n "$ANTHROPIC_BASE_URL" ]; then
    mode="API"
else
    mode="Team"
fi

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

# ---------- line 1: starship layout ----------
# repo_name <root>: first directory under ~/Projects, else the repo root's name (as in starship)
repo_name() {
    case "$PWD" in
    "$HOME/Projects/"*)
        p=${PWD#"$HOME/Projects/"}
        printf '%s' "${p%%/*}"
        ;;
    *) basename "$1" ;;
    esac
}

# dir_label [root]: "<root name>/<subpath>" inside a repo, "~/..." path otherwise;
# last 3 components (starship truncation_length = 3, truncate_to_repo)
dir_label() {
    if [ -n "$1" ]; then
        p="$(basename "$1")${PWD#"$1"}"
    else
        case "$PWD" in
        "$HOME"*) p="~${PWD#"$HOME"}" ;;
        *) p=${PWD#/} ;;
        esac
    fi
    printf '%s' "$p" | awk -F/ -v proj="$I_PROJECTS" '{
        n = NF; s = ""
        for (i = (n > 3 ? n - 2 : 1); i <= n; i++) s = s (s == "" ? "" : "/") ($i == "Projects" ? proj : $i)
        printf "%s%s", (n > 3 ? "…/" : ""), s
    }'
}

jj_root=$(jj root --ignore-working-copy 2>/dev/null)
if [ -n "$jj_root" ]; then
    # --- Jujutsu: nearest bookmark (+distance) or change id; ! dirty, = conflict ---
    info=$(jj log --ignore-working-copy --no-graph --color never -r @ \
        -T 'change_id.shortest(8) ++ "|" ++ if(empty, "", "!") ++ "|" ++ if(conflict, "=", "")' 2>/dev/null)
    OLDIFS=$IFS
    IFS="|"
    # shellcheck disable=SC2086
    set -- $info
    IFS=$OLDIFS
    change_id=$1
    dirty=$2
    conflict=$3
    bookmark=$(jj log --ignore-working-copy --no-graph --color never -n1 \
        -r 'heads(::@ & bookmarks())' -T 'bookmarks.map(|b| b.name()).join(" ")' 2>/dev/null)
    if [ -n "$bookmark" ]; then
        n=$(jj log --ignore-working-copy --no-graph --color never \
            -r 'heads(::@ & bookmarks())..@' -T '"x\n"' 2>/dev/null | wc -l | tr -d ' ')
        text="${I_BRANCH} ${bookmark}"
        [ "${n:-0}" -gt 0 ] && text="${text}+${n}"
    else
        text="${I_BRANCH} ${change_id}"
    fi
    marks="${conflict}${dirty}"
    [ -n "$marks" ] && text="${text} ${marks}"

    add_seg "$C_ORANGE" "$C_FG0" "${I_JJ} $(repo_name "$jj_root")"
    add_seg "$C_YELLOW" "$C_FG0" "${I_DIR} $(dir_label "$jj_root")"
    add_seg "$C_AQUA" "$C_FG0" "$text"
elif toplevel=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$toplevel" ]; then
    # --- git: branch + starship status symbols (= conflict, ! modified, + staged, ? untracked) ---
    gs=$(git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null | awk '
        /^# branch.head/ { h = $3 }
        /^# branch.oid/  { o = substr($3, 1, 7) }
        /^# branch.ab/   { a = substr($3, 2); b = substr($4, 2) }
        /^[12] /         { if (substr($2, 1, 1) != ".") s++; if (substr($2, 2, 1) != ".") m++ }
        /^u /            { c++ }
        /^\?/            { u++ }
        END { printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d", h, o, a, b, s, m, u, c }')
    OLDIFS=$IFS
    IFS=$(printf '\t')
    # shellcheck disable=SC2086
    set -- $gs
    IFS=$OLDIFS
    branch=$1
    oid=$2
    ahead=$3
    behind=$4
    staged=$5
    modified=$6
    untracked=$7
    conflicts=$8

    if [ "$branch" = "(detached)" ]; then
        text="${I_BRANCH} ${oid}"
    else
        text="${I_BRANCH} ${branch}"
    fi
    marks=""
    [ "${conflicts:-0}" -gt 0 ] && marks="${marks}="
    [ "${modified:-0}" -gt 0 ] && marks="${marks}!"
    [ "${staged:-0}" -gt 0 ] && marks="${marks}+"
    [ "${untracked:-0}" -gt 0 ] && marks="${marks}?"
    [ "${ahead:-0}" -gt 0 ] && marks="${marks}⇡${ahead}"
    [ "${behind:-0}" -gt 0 ] && marks="${marks}⇣${behind}"
    [ -n "$marks" ] && text="${text} ${marks}"

    add_seg "$C_ORANGE" "$C_FG0" "${I_GIT} $(repo_name "$toplevel")"
    add_seg "$C_YELLOW" "$C_FG0" "${I_DIR} $(dir_label "$toplevel")"
    add_seg "$C_AQUA" "$C_FG0" "$text"
else
    # --- not a repository: blank orange block, as in starship ---
    add_seg "$C_ORANGE" "$C_FG0" ""
    add_seg "$C_YELLOW" "$C_FG0" "${I_DIR} $(dir_label)"
    add_seg "$C_AQUA" "$C_FG0" ""
fi
add_seg "$C_BG1" "$C_FG0" "${I_CLOCK} $(date +%R)"
end_segs
line1=$seg_out

# ---------- line 2: light text row (no fills, so it reads apart from line 1) ----------
C_MODEL="211;134;155"
dim=$(fg "$C_GRAY")
track=$(fg "$C_TRACK")
line2="${track} ╰─${RST} "

if [ -n "$model" ]; then
    line2="${line2}$(fg "$C_MODEL")${ESC}[1m${model}${ESC}[22m${RST}"
    if [ -n "$effort" ]; then
        case "$effort" in
        low) lv=1 ec=$C_GRAY ;;
        medium) lv=2 ec=$C_B_AQUA ;;
        high) lv=3 ec=$C_B_YELLOW ;;
        xhigh) lv=4 ec=$C_B_ORANGE ;;
        *) lv=5 ec=$C_B_RED ;; # max
        esac
        dots=""
        i=1
        while [ "$i" -le 5 ]; do
            if [ "$i" -le "$lv" ]; then
                dots="${dots}$(fg "$ec")●"
            else
                dots="${dots}${track}○"
            fi
            i=$((i + 1))
        done
        line2="${line2}${dim} / ${RST}$(fg "$ec")${effort} ${dots}${RST}"
    fi
    line2="${line2}${dim} / ${RST}"
fi

if [ -n "$ctx_used" ]; then
    pct=$(printf '%.0f' "$ctx_used")
    width=12
    filled=$((pct * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    on=""
    off=""
    i=0
    while [ "$i" -lt "$width" ]; do
        if [ "$i" -lt "$filled" ]; then on="${on}━"; else off="${off}━"; fi
        i=$((i + 1))
    done
    cc=$(pct_color "$pct")
    line2="${line2}${dim}ctx ${cc}${on}${track}${off} ${cc}${pct}%${RST}"
else
    line2="${line2}${dim}ctx ${track}━━━━━━━━━━━━ ${dim}--${RST}"
fi
line2="${line2}${dim} / ${mode}${RST}"

# ---------- line 3: prompt cache / rate limits / cost ----------
# mkbar <pct> <width>: "━" bar in pct_color, track for the rest
mkbar() {
    b_pct=$1
    b_w=$2
    b_filled=$((b_pct * b_w / 100))
    [ "$b_filled" -gt "$b_w" ] && b_filled=$b_w
    b_on=""
    b_off=""
    b_i=0
    while [ "$b_i" -lt "$b_w" ]; do
        if [ "$b_i" -lt "$b_filled" ]; then b_on="${b_on}━"; else b_off="${b_off}━"; fi
        b_i=$((b_i + 1))
    done
    printf '%s%s%s%s' "$(pct_color "$b_pct")" "$b_on" "$track" "$b_off"
}

# fmt_dur <seconds>: 3d4h / 2h10m / 52m
fmt_dur() {
    d_s=$1
    [ "$d_s" -lt 0 ] && d_s=0
    if [ "$d_s" -ge 86400 ]; then
        printf '%dd%dh' $((d_s / 86400)) $((d_s % 86400 / 3600))
    elif [ "$d_s" -ge 3600 ]; then
        printf '%dh%dm' $((d_s / 3600)) $((d_s % 3600 / 60))
    else
        printf '%dm' $((d_s / 60))
    fi
}

# fmt_tok <n>: 120k / 3.2k / 850
fmt_tok() {
    awk -v n="$1" 'BEGIN {
        if (n >= 100000) printf "%dk", n / 1000
        else if (n >= 1000) printf "%.1fk", n / 1000
        else printf "%d", n
    }'
}

# rate_seg <label> <pct> <resets_at>: "5h ━━━━━━ 23% ↻2h10m"
rate_seg() {
    r_pct=$(printf '%.0f' "$2")
    r_out="${dim}$1 $(mkbar "$r_pct" 6) $(pct_color "$r_pct")${r_pct}%${RST}"
    if [ -n "$3" ]; then
        r_out="${r_out}${dim} ↻$(fmt_dur $(($3 - now)))${RST}"
    fi
    printf '%s' "$r_out"
}

now=$(date +%s)
sep="${dim} / ${RST}"
line3=""
add3() {
    if [ -z "$line3" ]; then line3=$1; else line3="${line3}${sep}$1"; fi
}

# cache: warm shows the time left until the cache expires; cold shows why the next turn is heavy
if [ -n "$cache_warm" ]; then
    left=""
    [ -n "$cache_exp" ] && left=$((cache_exp - now))
    if [ "$cache_warm" = "true" ] && { [ -z "$left" ] || [ "$left" -gt 0 ]; }; then
        txt="$(fg "$C_B_GREEN")●warm${RST}"
        if [ -n "$left" ]; then
            if [ "$left" -lt 180 ]; then
                tc=$C_B_RED
            elif [ "$left" -lt 600 ]; then
                tc=$C_B_YELLOW
            else
                tc=$C_B_GREEN
            fi
            txt="${txt} $(fg "$tc")↻$(fmt_dur "$left")${RST}"
        fi
    else
        txt="$(fg "$C_B_RED")○cold${RST}"
    fi
    if [ -n "$cache_r" ] || [ -n "$cache_w" ]; then
        txt="${txt}${dim} r $(fmt_tok "${cache_r:-0}") w $(fmt_tok "${cache_w:-0}")${RST}"
    fi
    add3 "$txt"
fi

[ -n "$rl5_pct" ] && add3 "$(rate_seg 5h "$rl5_pct" "$rl5_reset")"
[ -n "$rl7_pct" ] && add3 "$(rate_seg 7d "$rl7_pct" "$rl7_reset")"
[ -n "$cost_usd" ] && add3 "${dim}$(printf '$%.2f' "$cost_usd")${RST}"

if [ -n "$line3" ]; then
    printf '%s\n%s\n%s' "$line1" "$line2" "${track} ╰─${RST} ${line3}"
else
    printf '%s\n%s' "$line1" "$line2"
fi
