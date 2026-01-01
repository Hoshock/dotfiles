# dotfiles

## Prerequisites

- System git installed

## Initial Setup

Copy the content of [setup.sh](setup.sh) and run it in your terminal.

> [!NOTE]
> Git clone will be done via `setup.sh`, so no need to clone the repository manually.
> You can make `setup.sh` executable in your system of course, but it's simpler to just copy and paste it in your terminal.

## Later Updates

After relaunch zsh,

```shell
jg darwin   # apply nix-darwin configuration
jg gc       # apply garbage collection to nix store
```
