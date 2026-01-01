{ pkgs, username, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users."${username}" = {
    home.stateVersion = "25.11";

    home.packages = with pkgs; [
      awscli2
      # aws-sam-cli
      bat
      chezmoi
      codex
      colima
      deno
      docker
      eza
      fzf
      gh
      git
      htop
      jnv
      jq
      just
      mas
      nano
      nixd
      nixfmt-rfc-style
      nodePackages.aws-cdk
      python313Packages.cfn-lint
      python313Packages.httpie
      reviewdog
      ripgrep
      sheldon
      shfmt
      ssm-session-manager-plugin
      starship
      tldr
      tree
      uv
      wget
      xdg-ninja
      yq-go
      zenn-cli
      zoxide
    ];
  };
}
