self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.omapod;
  desktop = "io.github.arikisonfire.OmaPod.desktop";
in
{
  options.programs.omapod = {
    enable = lib.mkEnableOption "omaPOD, a podcast player for Omarchy";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.omapod;
      defaultText = lib.literalExpression "omapod.packages.\${pkgs.stdenv.hostPlatform.system}.omapod";
      description = "The omaPOD package to use.";
    };

    defaultHandler = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Make omaPOD the system-wide default for podcast links and OPML files.
        A user's own `~/.config/mimeapps.list` still wins.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    xdg.mime.defaultApplications = lib.mkIf cfg.defaultHandler (
      lib.genAttrs [
        "x-scheme-handler/podcast"
        "x-scheme-handler/itpc"
        "x-scheme-handler/pcast"
        "x-scheme-handler/antennapod-subscribe"
        "text/x-opml"
        "text/x-opml+xml"
      ] (_: desktop)
    );
  };
}
