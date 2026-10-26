{
  lib,
  username,
  homedir,
  ...
}:
let
  # 会社 VPN / オフィスの FortiSASE は TLS を Fortinet の CA で署名し直す。
  # dotfiles は public なので証明書はコミットせず、chezmoi が ~/FortiSASE から生成する。
  corpCA = ../certs/corp-ca.pem;
in
{
  nix.settings.trusted-users = [
    "root"
    username
  ];

  # /etc/ssl/certs/ca-certificates.crt (NIX_SSL_CERT_FILE) に追加される。
  # 信頼する CA が増えるだけなので、社外のネットワークでもそのまま動く。
  security.pki.certificateFiles = lib.optional (builtins.pathExists corpCA) corpCA;

  system = {
    stateVersion = 6;
    primaryUser = username;

    defaults = {
      dock = {
        autohide = true;
        mru-spaces = false;
        show-recents = false;
      };

      finder = {
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      # cask のアプリ自身の自動更新を止め、just -g brew-upgrade がクールタイム付きで更新する。
      # ブラウザ (arc, google-chrome) と google-japanese-ime は自動更新のまま (brew-upgrade の skip 対象)。
      CustomUserPreferences =
        lib.genAttrs
          [
            "com.clipy-app.Clipy"
            "com.cmuxterm.app"
            "net.freemacsoft.AppCleaner"
            "org.sbarex.QLMarkdown"
            "org.sbarex.SourceCodeSyntaxHighlight"
          ]
          (_: {
            # Sparkle
            SUAutomaticallyUpdate = false;
            SUEnableAutomaticChecks = false;
          })
        // {
          # SlackNoAutoUpdates は 2024-09 に廃止され AutoUpdate に置き換わった。両方入れておく
          "com.tinyspeck.slackmacgap" = {
            AutoUpdate = false;
            SlackNoAutoUpdates = true;
          };
        };

      # root で実行されるので、ドメイン名だけだと /var/root/Library/Preferences に書かれてしまう。絶対パスで指定する
      CustomSystemPreferences = {
        "/Library/Preferences/us.zoom.config".AU2_EnableAutoUpdate = false;
      };
    };

    # Homebrew 6.0 から HOMEBREW_REQUIRE_TAP_TRUST がデフォルト有効になり、
    # サードパーティ tap は trust.json への登録が必要。activation 内の brew bundle は
    # XDG_CONFIG_HOME を持たず ~/.homebrew/trust.json を参照するため、bundle より前に配置する。
    activationScripts.preActivation.text = ''
      install -d -o ${username} "${homedir}/.homebrew"
      echo '{"trustedtaps":["manaflow-ai/cmux","microsoft/apm"]}' > "${homedir}/.homebrew/trust.json"
      chown ${username} "${homedir}/.homebrew/trust.json"
    '';

    activationScripts.postActivation.text = ''
      sudo mdutil -i off /
      sudo mdutil -E /
    '';
  };
  users.users."${username}".home = homedir;
}
