# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

autoload -Uz promptinit
promptinit

eval "$(anyenv init -)"
eval "$(pyenv init -)"

export PATH="$HOME/.local/bin:$PATH"
