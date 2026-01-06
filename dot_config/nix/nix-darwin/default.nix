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
  };
  users.users."${username}".home = homedir;
}
