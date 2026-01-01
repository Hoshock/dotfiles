export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="/run/user/$UID"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export SHELL_SESSIONS_DISABLE=1

if [[ ! -d "$HOME/Projects" ]]; then
    mkdir -p "$HOME/Projects"
fi
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply --source "$HOME/Projects/dotfiles" https://github.com/Hoshock/dotfiles.git
rm -rf .local/bin/chezmoi

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install)
sudo nix run --extra-experimental-features "nix-command flakes" nix-darwin#darwin-rebuild -- switch --flake "$XDG_CONFIG_HOME/nix#$(scutil --get LocalHostName)"
