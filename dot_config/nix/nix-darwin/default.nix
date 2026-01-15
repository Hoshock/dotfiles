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
      sudo mdutil -i off /
      sudo mdutil -E /
    '';
  };
  users.users."${username}".home = homedir;
}
