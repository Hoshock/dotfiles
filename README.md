# dotfiles

Modern chezmoi and nix-based setup for my systems.

## Tech Stack

| Category    | Tool                                                                                                             | Purpose                                             |
| ----------- | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| Dotfiles    | [chezmoi](https://github.com/twpayne/chezmoi)                                                                    | Configuration file management                       |
| CLI Tools   | [nix-darwin](https://github.com/LnL7/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager) | CLI application management                          |
| GUI Apps    | [nix-darwin](https://github.com/LnL7/nix-darwin) + [Homebrew Cask](https://github.com/Homebrew/homebrew-cask)    | GUI application and system configuration management |
| Task Runner | [just](https://github.com/casey/just)                                                                            | Command automation                                  |
| Zsh Config  | [sheldon](https://github.com/rossmacarthur/sheldon)                                                              | Zsh plugin management                               |

### Tool Selection

#### Dotfiles

I previously used [rcm](https://github.com/thoughtbot/rcm), a symlink-based dotfiles manager. It worked perfectly fine, but the project is no longer actively maintained.

[chezmoi](https://github.com/twpayne/chezmoi) is a modern, Go-based alternative that has gained significant popularity. While it uses a copy-based approach rather than symlinks, it offers rich features such as encryption and templating that made the switch worthwhile.

#### CLI Tools

I previously used [Homebrew](https://github.com/Homebrew/brew) to manage CLI tools. However, it had limitations with dependency version conflicts and version pinning.

[Nix](https://nixos.org/) has gained widespread popularity as a purely functional package manager, and after evaluating it, I decided to migrate. Since I don't typically use devcontainers or Docker, I manage commonly used CLI tools with [home-manager](https://github.com/nix-community/home-manager). As I'm on macOS, home-manager is integrated as a plugin through [nix-darwin](https://github.com/LnL7/nix-darwin).

I use `home.packages` instead of `programs.*` in home-manager to avoid automatic configuration generation. All dotfiles are strictly managed and deployed through chezmoi. While Nix could handle file placement via `xdg.configFile` or `home.file`, I intentionally avoid this to maintain a clear separation of responsibilities.

#### GUI Apps

Installing GUI applications via Nix prevents modifying their settings through the app's UI due to the Nix store's immutable nature. To avoid this, all GUI apps are installed through [Homebrew Cask](https://github.com/Homebrew/homebrew-cask). Since nix-darwin can manage Homebrew declaratively, the configuration remains declarative. For the same reason, VS Code extensions are also managed via Homebrew.

macOS system preferences (such as Dock behavior and menu bar settings) are managed through nix-darwin, as well.

#### Task Runner

The traditional approach is to define functions in `.zshrc`, but this bloats the file and shell scripts generally have poor readability and maintainability. Tools like [mise](https://github.com/jdx/mise) exist, but they are overly feature-rich for just running tasks.

[just](https://github.com/casey/just) is a Rust-based task runner that focuses solely on task execution. Unlike Make, it's purpose-built for running tasks, keeping the feature set minimal and the learning curve low.

#### Zsh Config

I previously used [zinit](https://github.com/zdharma-continuum/zinit), but the original development team disbanded and the project is now maintained by the community, which raised concerns about long-term stability.

[sheldon](https://github.com/rossmacarthur/sheldon) is a Rust-based plugin manager that offers improved performance over zinit. Its TOML-based configuration also provides better readability.

## Usage

### Prerequisites

- System git installed
- Manually migrated
  - `~/.config/chezmoi/key.txt`
  - `~/.ssh/*.pem`

### Initial Setup

Copy the content of [setup.sh](setup.sh) and run it in your terminal.

> [!NOTE]
> Git clone will be done via `setup.sh`, so no need to clone the repository manually.
> You can make `setup.sh` executable in your system of course, but it's simpler to just copy and paste it in your terminal.

### Later Update

Just run `jg update`.
