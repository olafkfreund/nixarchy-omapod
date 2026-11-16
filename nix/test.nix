{
  self,
  home-manager,
  pkgs,
}:
let
  omapod = self.packages.${pkgs.stdenv.hostPlatform.system}.omapod;
  hardening = "tests.test_hardening";
in
pkgs.testers.runNixOSTest {
  name = "omapod";

  nodes.machine =
    { ... }:
    {
      imports = [
        self.nixosModules.default
        home-manager.nixosModules.home-manager
      ];

      programs.omapod.enable = true;
      users.users.alice = {
        isNormalUser = true;
        linger = true;
        uid = 1000;
      };

      home-manager.users.alice = {
        imports = [
          self.homeManagerModules.default
          ./example-home.nix
        ];
        home.stateVersion = "25.11";
      };

      environment.systemPackages = [
        pkgs.xvfb-run
        pkgs.dbus
        pkgs.jq
      ];

      # A settings file the user "already had": the merge must keep it.
      systemd.services.seed-omapod = {
        before = [ "home-manager-alice.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "alice";
          UMask = "0077";
        };
        script = ''
          mkdir -p /home/alice/.config/omapod
          echo '{"rewind_secs": 5}' > /home/alice/.config/omapod/settings.json
        '';
      };
    };

  testScript = ''
    cfg = "/home/alice/.config/omapod/settings.json"

    def as_alice(cmd):
        return "su - alice -c 'export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; " + cmd + "'"

    machine.start()

    with subtest("1 units"):
        machine.wait_for_unit("home-manager-alice.service")
        machine.wait_for_unit("default.target", "alice")

    with subtest("2 mime handlers"):
        desktop = "/run/current-system/sw/share/applications/io.github.arikisonfire.OmaPod.desktop"
        for scheme in ["podcast", "itpc", "pcast", "antennapod-subscribe"]:
            machine.succeed(f"grep -q 'x-scheme-handler/{scheme}' {desktop}")
        machine.succeed("grep -q io.github.arikisonfire.OmaPod.desktop /etc/xdg/mimeapps.list")

    with subtest("3 key bindings"):
        binds = "/home/alice/.config/hypr/omapod-binds.lua"
        for c in ["toggle", "rewind", "forward", "show", "speed 1.5"]:
            machine.succeed(f"grep -q 'ctl {c}' {binds}")
        machine.fail(f"grep -q 'ctl skip' {binds}")

    with subtest("4 settings merged"):
        machine.wait_until_succeeds(f"jq -e '.speed == 1.5 and .rewind_secs == 5' {cfg}")
        assert machine.succeed(f"stat -c %a {cfg}").strip() == "600"

    with subtest("5 app changes survive"):
        machine.succeed(as_alice(f"jq \".speed = 2.0\" {cfg} > {cfg}.tmp && mv {cfg}.tmp {cfg}"))
        machine.succeed(as_alice("systemctl --user restart omapod-settings.service"))
        machine.succeed(f"jq -e '.speed == 2.0' {cfg}")

    with subtest("6 widget"):
        w = "/home/alice/.config/omarchy/plugins/io.github.arikisonfire.pod"
        machine.succeed(f"jq -e '.barWidget.defaults.maxTitleWidth == 240' {w}/manifest.json")
        machine.succeed(f"test -f {w}/plugin/BarWidget.qml && test -f {w}/.nix-managed")
        machine.fail(f"test -e {w}/omapod")

    with subtest("7 refresh timer"):
        machine.succeed(as_alice("systemctl --user is-enabled omapod-refresh.timer"))
        machine.succeed(as_alice("systemctl --user start omapod-refresh.service"))

    with subtest("8 app answers"):
        machine.succeed(as_alice("OMAPOD_MPV_AO=null nohup xvfb-run -a dbus-run-session -- omapod >/tmp/omapod.log 2>&1 &"))
        machine.wait_until_succeeds(as_alice("omapod ctl state | jq -e ."), timeout=60)

    with subtest("9 running app blocks the merge"):
        machine.succeed(as_alice("systemctl --user restart omapod-settings.service"))
        machine.succeed(as_alice("journalctl --user -u omapod-settings -n 5 | grep -q \"omaPOD is running\""))

    with subtest("10 OMAPOD_HOME ignored"):
        machine.succeed(as_alice("systemctl --user set-environment OMAPOD_HOME=/tmp/elsewhere"))
        machine.succeed(as_alice("omapod ctl quit"))
        machine.wait_until_fails(as_alice("omapod ctl state"))
        machine.succeed(as_alice("systemctl --user restart omapod-settings.service"))
        machine.fail("test -e /tmp/elsewhere")

    with subtest("11 hardening tests that need a real filesystem"):
        out = machine.succeed(as_alice(
            "rm -rf /tmp/src /tmp/testhome; mkdir /tmp/testhome; cp -r ${self} /tmp/src && chmod -R u+w /tmp/src && cd /tmp/src && "
            "OMAPOD_MPV_AO=null HOME=/tmp/testhome xvfb-run -a dbus-run-session -- ${omapod}/libexec/omapod-python -B -m unittest -v "
            "${hardening}.ImportedFolders.test_choosing_the_folder_here_gives_its_podcast_its_files_back "
            "${hardening}.LocalFolders.test_files_stay_unless_the_user_confirms_and_then_go_to_the_trash "
            "${hardening}.SharedFolders.test_files_of_an_added_folder_that_others_can_change_stay 2>&1"
        ))
        assert "Ran 3 tests" in out and "OK" in out and "skipped" not in out, out
  '';
}
