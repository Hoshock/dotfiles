{ ... }:
{
  homebrew = {
    enable = true;
    onActivation.autoUpdate = true;

    brews = [
      "aws-sam-cli"
    ];

    casks = [
      "appcleaner"
      "arc"
      "clipy"
      "font-hack-nerd-font"
      "font-monaspace"
      "google-chrome"
      "google-japanese-ime"
      "karabiner-elements"
      "qlmarkdown"
      "slack"
      "syntax-highlight"
      # "thebrowsercompany-dia"
      "visual-studio-code"
      "zoom"
    ];

    masApps = {
      "Stay" = 435410196;
      "Window Tidy" = 456609775;
    };

    extraConfig = ''
      vscode "formulahendry.auto-rename-tag"
      vscode "njpwerner.autodocstring"
      vscode "amazonwebservices.aws-toolkit-vscode"
      vscode "aaron-bond.better-comments"
      vscode "biomejs.biome"
      vscode "Anthropic.claude-code"
      vscode "kddejong.vscode-cfn-lint"
      vscode "openai.chatgpt"
      vscode "vivaxy.vscode-conventional-commits"
      vscode "pranaygp.vscode-css-peek"
      vscode "ms-toolsai.datawrangler"
      vscode "denoland.vscode-deno"
      vscode "hediet.vscode-drawio"
      vscode "EditorConfig.EditorConfig"
      vscode "dbaeumer.vscode-eslint"
      vscode "tamasfe.even-better-toml"
      vscode "mhutchie.git-graph"
      vscode "github.vscode-github-actions"
      vscode "GitHub.copilot-chat"
      vscode "GitHub.vscode-pull-request-github"
      vscode "GitHub.remotehub"
      vscode "GitHub.github-vscode-theme"
      vscode "ms-vscode.hexeditor"
      vscode "ecmel.vscode-html-css"
      vscode "oderwat.indent-rainbow"
      vscode "ms-toolsai.jupyter"
      vscode "ms-toolsai.vscode-jupyter-cell-tags"
      vscode "ms-toolsai.jupyter-keymap"
      vscode "ms-toolsai.jupyter-renderers"
      vscode "ms-toolsai.vscode-jupyter-slideshow"
      vscode "ms-vscode.live-server"
      vscode "ritwickdey.LiveServer"
      vscode "yzhang.markdown-all-in-one"
      vscode "bierner.markdown-mermaid"
      vscode "DavidAnson.vscode-markdownlint"
      vscode "PKief.material-icon-theme"
      vscode "jnoortheen.nix-ide"
      vscode "Nuxtr.nuxtr-vscode"
      vscode "42Crunch.vscode-openapi"
      vscode "oxc.oxc-vscode"
      vscode "johnpapa.vscode-peacock"
      vscode "esbenp.prettier-vscode"
      vscode "alefragnani.project-manager"
      vscode "ms-python.vscode-pylance"
      vscode "ms-python.python"
      vscode "ms-python.debugpy"
      vscode "mechatroner.rainbow-csv"
      vscode "ms-vscode-remote.remote-ssh"
      vscode "ms-vscode-remote.remote-ssh-edit"
      vscode "ms-vscode.remote-explorer"
      vscode "ms-vscode.remote-repositories"
      vscode "charliermarsh.ruff"
      vscode "gurumukhi.selected-lines-count"
      vscode "timonwong.shellcheck"
      vscode "mkhl.shfmt"
      vscode "ReneSaarsoo.sql-formatter-vsc"
      vscode "stylelint.vscode-stylelint"
      vscode "shardulm94.trailing-spaces"
      vscode "vitest.explorer"
      vscode "Vue.volar"
      vscode "CelianRiboulet.webvalidator"
      vscode "nefrob.vscode-just-syntax"
      vscode "redhat.vscode-yaml"
      vscode "mosapride.zenkaku"
    '';
  };
}
