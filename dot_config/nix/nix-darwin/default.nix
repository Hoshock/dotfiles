{ username, homedir, ... }:
{
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

    activationScripts.postActivation.text = ''
      sudo mdutil -a -i off 2>/dev/null || true
      sudo mdutil -a -E 2>/dev/null || true
    '';
  };
  users.users."${username}".home = homedir;
}
