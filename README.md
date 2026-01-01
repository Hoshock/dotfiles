# dotfiles

Modern chezmoi and nix-based setup for my systems.

## Tech Stack

| Category    | Tool                                                                                                             | Purpose                       |
| ----------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| Dotfiles    | [chezmoi](https://www.chezmoi.io/)                                                                               | Configuration file management |
| CLI Tools   | [nix-darwin](https://github.com/LnL7/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager) | CLI application management    |
| GUI Apps    | [nix-darwin](https://github.com/LnL7/nix-darwin) + [Homebrew](https://brew.sh/)                                  | GUI application management    |
| Task Runner | [just](https://github.com/casey/just)                                                                            | Command automation            |
| Zsh Config  | [sheldon](https://github.com/rossmacarthur/sheldon)                                                              | Zsh plugin management         |

## Prerequisites

- System git installed
- `~/.config/chezmoi/key.txt` manually migrated

## Initial Setup

Copy the content of [setup.sh](setup.sh) and run it in your terminal.

> [!NOTE]
> Git clone will be done via `setup.sh`, so no need to clone the repository manually.
> You can make `setup.sh` executable in your system of course, but it's simpler to just copy and paste it in your terminal.

## Later Updates

Just run `jg update`.
