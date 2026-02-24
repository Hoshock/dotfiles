# GitHub Dark Dimmed Color Palette

A unified GitHub Dark Dimmed color scheme across multiple tools, based on the micro syntax highlighting configuration.

## Source

[primer/primitives](https://github.com/primer/primitives) v7.10.0 `dark_dimmed.json`.
[primer/github-vscode-theme](https://github.com/primer/github-vscode-theme) declares `@primer/primitives` as a `devDependency` and imports it via `require("@primer/primitives/dist/json/colors/dark_dimmed.json")` in `src/colors.js`.

The micro color scheme primarily uses primer scale[3] values, which differs slightly from VS Code's actual rendering (scale[1]-[2]).

## Palette

| Hex       | primer scale             | Semantic                         |
| --------- | ------------------------ | -------------------------------- |
| `#22272e` | gray[9] / canvas.default | background                       |
| `#2d333b` | gray[8] / header.bg      | surface (statusline, cursorline) |
| `#3d444d` | --                       | selection, indent guide          |
| `#444c56` | gray[6] / border.default | border                           |
| `#545d68` | gray[5]                  | line number                      |
| `#636e7b` | gray[4] / fg.subtle      | scrollbar                        |
| `#768390` | gray[3] / fg.muted       | comment                          |
| `#adbac7` | gray[1] / fg.default     | text                             |
| `#539bf5` | blue[3]                  | type, class, tag, identifier     |
| `#f47067` | red[3]                   | keyword, error                   |
| `#57ab5a` | green[3]                 | string, diff-added               |
| `#f69d50` | orange[2]                | constant, number                 |
| `#b083f0` | purple[3]                | function, preprocessor           |
| `#c69026` | yellow[3] / attention.fg | warning, diff-modified           |
| `#39c5cf` | ansi.cyan                | link, underline                  |

## Cross-Tool Mapping

### File Structure

```
micro/colorschemes/github-dark-dimmed.micro  <-- palette source of truth
    |
    |  same hex values, manually transcribed
    +---> bat/themes/github-dark-dimmed.tmTheme  <-- tmTheme format (single file)
    |        +---> yazi   (referenced via syntect_theme in theme.toml)
    |        +---> delta  (referenced via --syntax-theme in lazygit pager, requires bat cache)
    |
    +---> lazygit/config.yml gui.theme           <-- UI colors only (diff colors handled by delta)
```

### Syntax Highlighting

| Semantic        | Hex       | micro scope                  | tmTheme scope                           |
| --------------- | --------- | ---------------------------- | --------------------------------------- |
| keyword         | `#f47067` | statement, type.keyword      | keyword, storage                        |
| string          | `#57ab5a` | constant.string              | string, string.quoted                   |
| constant/number | `#f69d50` | constant, constant.number    | constant.numeric, constant.language     |
| function        | `#b083f0` | symbol, special, preproc     | entity.name.function, preprocessor      |
| type/class/tag  | `#539bf5` | identifier, type, symbol.tag | entity.name.type/class, entity.name.tag |
| link/escape     | `#39c5cf` | underlined                   | link, escape, regex                     |
| comment         | `#768390` | comment                      | comment                                 |
| warning/todo    | `#c69026` | todo, diff-modified          | markup.changed                          |

### UI / Editor Background

| Semantic    | Hex       | micro                     | tmTheme          | lazygit                    |
| ----------- | --------- | ------------------------- | ---------------- | -------------------------- |
| background  | `#22272e` | default bg                | background       | inactiveViewSelectedLineBg |
| surface     | `#2d333b` | statusline bg, cursorline | lineHighlight    | selectedLineBg             |
| selection   | `#3d444d` | selection bg              | selection, guide | --                         |
| border      | `#444c56` | --                        | --               | inactiveBorderColor        |
| text        | `#adbac7` | default fg                | foreground       | defaultFgColor             |
| line number | `#545d68` | line-number               | gutterForeground | --                         |

### Diff

| Semantic | Hex       | micro         | tmTheme         | lazygit              |
| -------- | --------- | ------------- | --------------- | -------------------- |
| added    | `#57ab5a` | diff-added    | markup.inserted | (via delta)          |
| deleted  | `#f47067` | diff-deleted  | markup.deleted  | unstagedChangesColor |
| modified | `#c69026` | diff-modified | markup.changed  | markedBaseCommitFg   |

## Scopes in tmTheme Not Available in micro

tmTheme (TextMate) supports finer-grained scopes than micro. The following will appear differently between yazi preview and micro.

| tmTheme scope               | tmTheme color      | Appearance in micro          |
| --------------------------- | ------------------ | ---------------------------- |
| `variable.parameter`        | `#f69d50` (orange) | `#adbac7` (default text)     |
| `string.regexp`             | `#39c5cf` (cyan)   | `#57ab5a` (green, as string) |
| `constant.character.escape` | `#39c5cf` (cyan)   | `#adbac7` (default text)     |

## Maintenance Policy

- The source of truth is `micro/colorschemes/github-dark-dimmed.micro`. When changing colors, start here and propagate to other files.
- `bat/themes/github-dark-dimmed.tmTheme` is a single file shared by yazi and delta. Do not duplicate it.
- Run `bat cache --build` after modifying the tmTheme file.
- Tracking upstream primer/primitives palette updates is optional.
