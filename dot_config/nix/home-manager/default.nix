{ pkgs, username, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users."${username}" = {
    home.stateVersion = "25.11";

    home.packages = with pkgs; [
      awscli2
      aws-sam-cli
      bat
      chezmoi
      codex
      colima
      deno
      direnv
      docker
      duckdb
      eza
      fzf
      gh
      git
      htop
      jnv
      jq
      just
      just-lsp
      mas
      nano
      nixd
      nixfmt
      nodejs_24
      nodePackages.aws-cdk
      python313Packages.cfn-lint
      python313Packages.httpie
      reviewdog
      ripgrep
      ruff
      sheldon
      shfmt
      # ssm-session-manager-plugin
      starship
      terminal-notifier
      tldr
      tree
      ty
      uv
      wget
      xdg-ninja
      yq-go
      zenn-cli
      zoxide
    ];
  };
}
