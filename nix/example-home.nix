{
  programs.omapod = {
    enable = true; # installs omaPOD

    # package = ...;              # default: the package from this flake
    # defaultHandler = true;      # default app for podcast links and OPML, if xdg.mimeApps.enable

    refreshTimer.enable = true;
    # refreshTimer.onCalendar = "hourly";

    # keybindings.enable = true;
    # keybindings.backend = "nixarchy";  # or "hyprland"
    keybindings.binds = {
      "SUPER + CTRL + SHIFT + N" = null; # drop a default
      "SUPER + CTRL + SHIFT + 1" = "speed 1.5"; # add one
    };

    widget.enable = true;
    # widget.showTitle = true;
    widget.maxTitleWidth = 240;
    # widget.hideWhenStopped = false;
    # widget.launchCommand = "";
    # widget.socketPath = "";

    settings.speed = 1.5;
  };
}
