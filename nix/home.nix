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
  widgetId = "io.github.arikisonfire.pod";
  json = pkgs.formats.json { };
  safe = "^[A-Za-z0-9 +_.,-]+$";

  defaultBinds = {
    "SUPER + CTRL + SHIFT + K" = "toggle";
    "SUPER + CTRL + SHIFT + COMMA" = "rewind";
    "SUPER + CTRL + SHIFT + PERIOD" = "forward";
    "SUPER + CTRL + SHIFT + N" = "skip";
    "SUPER + CTRL + SHIFT + O" = "show";
  };
  binds = lib.filterAttrs (_: v: v != null) (defaultBinds // cfg.keybindings.binds);
  ctl = args: "${cfg.package}/bin/omapod ctl ${args}";

  # "SUPER + CTRL + K" -> "SUPER CTRL, K"
  hyprBind =
    key: args:
    let
      parts = lib.splitString " + " key;
    in
    "${lib.concatStringsSep " " (lib.init parts)}, ${lib.last parts}, exec, ${ctl args}";

  mimeTypes = [
    "x-scheme-handler/podcast"
    "x-scheme-handler/itpc"
    "x-scheme-handler/pcast"
    "x-scheme-handler/antennapod-subscribe"
    "text/x-opml"
    "text/x-opml+xml"
  ];

  # Keys omaPOD itself writes; declaring them would fight the app.
  forbiddenKeys = [
    "podcastindex_key"
    "podcastindex_secret"
    "parental_password_hash"
    "local_folders"
    "last_page"
    "history_repair"
    "mirror_downloads_ready"
    "auto_db_export_last"
    "stats_reset_ts"
  ];
  forbiddenPrefixes = [
    "window_"
    "sync_last_"
    "remote_downloads_"
    "queue_sync_"
    "favorites_sync_"
  ];
  badSettings =
    builtins.filter (
      k: builtins.elem k forbiddenKeys || lib.any (p: lib.hasPrefix p k) forbiddenPrefixes
    ) (builtins.attrNames cfg.settings)
    ++ lib.optional (
      cfg.settings ? proxy && builtins.isAttrs cfg.settings.proxy && cfg.settings.proxy ? password
    ) "proxy.password";

  manifest = builtins.fromJSON (builtins.readFile "${cfg.package}/share/omapod/widget/manifest.json");
  widgetDir = pkgs.runCommand "omapod-widget" { } ''
    cp -r ${cfg.package}/share/omapod/widget $out
    chmod -R u+w $out
    cp ${
      pkgs.writeText "manifest.json" (
        builtins.toJSON (
          lib.recursiveUpdate manifest {
            barWidget.defaults = {
              inherit (cfg.widget)
                showTitle
                maxTitleWidth
                hideWhenStopped
                launchCommand
                socketPath
                ;
            };
          }
        )
      )
    } $out/manifest.json
  '';

  widgetScript = ''
    dest="${config.xdg.configHome}/omarchy/plugins/${widgetId}"
    parent="$(dirname "$dest")"
    tmp="$parent/.${widgetId}.new"
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.diffutils
      ]
    }:$PATH"
  ''
  + (
    if cfg.widget.enable then
      ''
        install_widget() {
          $DRY_RUN_CMD rm -rf "$tmp"
          $DRY_RUN_CMD mkdir -p "$parent"
          $DRY_RUN_CMD cp -rT --no-preserve=mode,ownership "${widgetDir}" "$tmp"
          $DRY_RUN_CMD touch "$tmp/.nix-managed"
          $DRY_RUN_CMD rm -rf "$dest"
          $DRY_RUN_CMD mv "$tmp" "$dest"
        }
        if [ ! -e "$dest" ]; then
          install_widget
        elif [ -e "$dest/.nix-managed" ]; then
          if ! diff -rq -x .nix-managed "${widgetDir}" "$dest" >/dev/null 2>&1; then
            install_widget
          fi
        else
          echo "omaPOD: the bar widget at $dest is not managed by Nix; to hand it over run \`omarchy plugin remove ${widgetId}\` or \`install.sh --uninstall\`, then rebuild."
        fi
      ''
    else
      ''
        if [ -e "$dest/.nix-managed" ]; then
          $DRY_RUN_CMD rm -rf "$dest"
        fi
      ''
  );
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
        Make omaPOD the default app for podcast links and OPML files. Only
        applies when `xdg.mimeApps.enable` is set; this module never enables it.
      '';
    };

    refreshTimer = {
      enable = lib.mkEnableOption "a systemd user timer that refreshes all podcasts";
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
        description = "systemd `OnCalendar` value for the refresh timer.";
      };
    };

    keybindings = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Generate key bindings that control omaPOD.";
      };
      backend = lib.mkOption {
        type = lib.types.enum [
          "nixarchy"
          "hyprland"
        ];
        default = "nixarchy";
        description = ''
          `nixarchy` writes `~/.config/hypr/omapod-binds.lua`; add
          `pcall(require, "hypr.omapod-binds")` to your `bindings.lua` once.
          `hyprland` sets `wayland.windowManager.hyprland.settings.bind`.
        '';
      };
      binds = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr (lib.types.strMatching safe));
        default = { };
        description = ''
          Key combination to `omapod ctl` arguments, merged over the defaults.
          Set a key to `null` to drop a default. Keys must match `${safe}`.
        '';
        example = {
          "SUPER + CTRL + SHIFT + N" = null;
          "SUPER + CTRL + SHIFT + 1" = "speed 1.5";
        };
      };
    };

    widget = {
      enable = lib.mkEnableOption "the omaPOD bar widget for the Omarchy shell";
      showTitle = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show the episode title in the bar.";
      };
      maxTitleWidth = lib.mkOption {
        type = lib.types.ints.between 60 600;
        default = 180;
        description = "Maximum title width in pixels.";
      };
      hideWhenStopped = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hide the widget when nothing is loaded.";
      };
      launchCommand = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Command that starts omaPOD; empty uses the installed one.";
      };
      socketPath = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Control socket path; empty uses the default.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf json.type;
      default = { };
      description = ''
        Settings applied to omaPOD's `settings.json` at login and on rebuild.
        Values you change in the app afterwards are kept.
      '';
      example = {
        speed = 1.5;
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ cfg.package ];

        assertions =
          map (k: {
            assertion = false;
            message = "programs.omapod.settings.${k} is managed by omaPOD itself and cannot be declared.";
          }) badSettings
          ++ map (k: {
            assertion = builtins.match safe k != null;
            message = "programs.omapod.keybindings.binds: key \"${k}\" may only contain letters, digits, space and + _ . , -";
          }) (builtins.attrNames cfg.keybindings.binds);

        home.activation.omapodWidget = lib.hm.dag.entryAfter [ "writeBoundary" ] widgetScript;
      }

      (lib.mkIf cfg.refreshTimer.enable {
        systemd.user.services.omapod-refresh = {
          Unit.Description = "Refresh omaPOD podcasts";
          Service = {
            Type = "oneshot";
            ExecStart = "${cfg.package}/bin/omapod --refresh";
          };
        };
        systemd.user.timers.omapod-refresh = {
          Unit.Description = "Refresh omaPOD podcasts";
          Timer = {
            OnCalendar = cfg.refreshTimer.onCalendar;
            RandomizedDelaySec = "5min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      })

      # Always present: with settings = { } it still drops keys Nix wrote before.
      {
        systemd.user.services.omapod-settings = {
          Unit.Description = "Apply declared omaPOD settings";
          Service = {
            Type = "oneshot";
            ExecStart = "${cfg.package}/libexec/omapod-merge-settings ${json.generate "omapod-settings.json" cfg.settings}";
            UnsetEnvironment = "OMAPOD_HOME";
          };
          Install.WantedBy = [ "default.target" ];
        };
      }

      (lib.mkIf (cfg.keybindings.enable && cfg.keybindings.backend == "nixarchy") {
        xdg.configFile."hypr/omapod-binds.lua".text =
          "-- Generated by programs.omapod; edits are overwritten on rebuild.\n"
          + lib.concatStrings (
            lib.mapAttrsToList (k: a: "o.bind(\"${k}\", \"omaPOD: ${a}\", \"${ctl a}\")\n") binds
          );
      })

      (lib.mkIf (cfg.keybindings.enable && cfg.keybindings.backend == "hyprland") {
        wayland.windowManager.hyprland.settings.bind = lib.mapAttrsToList hyprBind binds;
      })

      (lib.mkIf (cfg.defaultHandler && config.xdg.mimeApps.enable) {
        xdg.mimeApps.defaultApplications = lib.genAttrs mimeTypes (_: lib.mkDefault [ desktop ]);
      })
    ]
  );
}
