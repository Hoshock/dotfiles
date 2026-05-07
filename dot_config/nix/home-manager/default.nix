{
  pkgs,
  username,
  nodejsPkg,
  pnpmPkg,
  ...
}:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users."${username}" = {
    home.stateVersion = "25.11";

    home.packages = with pkgs; [
      aws-cdk-cli
      awscli2
      bat
      chezmoi
      colima
      copilot-language-server
      delta
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
      lazygit
      mas
      micro
      nano
      nixd
      nixfmt
      nodejsPkg
      pnpmPkg
      prettier
      python313Packages.cfn-lint
      python313Packages.httpie
      reviewdog
      ripgrep
      ruff
      sheldon
      shellcheck
      shfmt
      starship
      stylua
      terminal-notifier
      tldr
      tree
      ty
      uv
      wget
      xdg-ninja
      yq-go
      zoxide
    ];
  };
}
