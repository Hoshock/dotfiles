{ username, homedir, ... }:
{
  nix.settings.trusted-users = [
    "root"
    username
  ];

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
