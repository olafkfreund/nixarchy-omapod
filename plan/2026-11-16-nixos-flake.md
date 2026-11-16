---
status: draft
issue: none (issues disabled on olafkfreund/nixarchy-omapod)
spec: spec/2026-11-16-nixos-flake.md
coders:
  1: coder   # package + flake skeleton: Nix boilerplate, many small parts
  2: codex   # merge-settings.py: small, tricky ownership/lock logic with a test table
  3: coder   # NixOS module: short, conventional
  4: coder   # Home Manager module: several options, conventional Nix
  5: coder   # VM test: Nix + Python test driver, needs the modules' shape from 3-4
  6: coder   # CI workflow: one YAML file
  7: coder   # README section
reviewers:
  - codex    # independent read of the full diff against this plan before the PR
# agy: out of use by owner decision (#2748); the default routing would have sent
# step 7 (large mechanical doc edit) to agy, so it goes to coder instead.
---

# Plan: Install omaPOD on NixOS with a flake

Branch `feat/nixos-flake`. Builds run on p620 (local, KVM present), never p510. Each step
is built and committed by the session (Opus) after the coder hands it back; coders do not
stage, commit or push.

## Approved decisions (from the spec; no need to open it)

- **Files:** `flake.nix`, `flake.lock`, `nix/package.nix`, `nix/nixos.nix`,
  `nix/home.nix`, `nix/merge-settings.py`, `nix/test_merge_settings.py`, `nix/test.nix`,
  `.github/workflows/nix.yml`, `README.md`. No app code under `omapod/`, no `install.sh`,
  `manifest.json` or `plugin/` changes.
- **Flake:** inputs `nixpkgs` (`github:NixOS/nixpkgs/nixos-unstable`) and `home-manager`
  (`github:nix-community/home-manager`, `inputs.nixpkgs.follows = "nixpkgs"`; used only
  by the VM test). Systems `x86_64-linux`, `aarch64-linux`. Outputs:
  `packages.<s>.{default,omapod}`, `apps.<s>.default`, `overlays.default`
  (`omapod = final.callPackage ./nix/package.nix {}`), `nixosModules.default`,
  `homeManagerModules.default`, `checks.<s>.package`, `checks.x86_64-linux.vm`. Modules
  default `package` to `self.packages.${pkgs.stdenv.hostPlatform.system}.omapod`. No
  devShell, formatter or Cachix.
- **Package** (`stdenv.mkDerivation`, `pname = "omapod"`, version parsed from
  `omapod/__init__.py` line `VERSION = "0.1.5"`):
  - `python = python3.withPackages (ps: [ ps.pygobject3 ])`.
  - `nativeBuildInputs = [ wrapGAppsHook4 gobject-introspection makeWrapper ]`;
    `buildInputs = [ gtk4 libadwaita gdk-pixbuf pango graphene glib ]`.
  - Layout: `$out/share/omapod/omapod/` (Python package, no `__pycache__`);
    `$out/share/omapod/widget/{manifest.json,plugin/BarWidget.qml,LICENSE}` (no app source
    beside it); `$out/share/applications/io.github.arikisonfire.OmaPod.desktop` from
    `data/io.github.arikisonfire.OmaPod.desktop.in` with `@BIN@` → `$out/bin/omapod`;
    `$out/share/icons/hicolor/scalable/apps/io.github.arikisonfire.OmaPod.svg`;
    `$out/libexec/omapod-merge-settings`.
  - `dontWrapGApps = true`; `postFixup`: `makeWrapper ${python}/bin/python3
    $out/bin/omapod --add-flags "-P -m omapod" --prefix PYTHONPATH : $out/share/omapod
    --suffix PATH : ${lib.makeBinPath [ mpv xdg-utils ]} "''${gappsWrapperArgs[@]}"`, and
    the same for `$out/libexec/omapod-merge-settings` with `--add-flags
    "-P $out/share/omapod/merge-settings.py"` (script copied there).
  - `doCheck = true`; `nativeCheckInputs = [ python mpv openssl xvfb-run dbus ]`;
    `checkPhase`: `export HOME=$TMPDIR OMAPOD_MPV_AO=null`, then
    `xvfb-run -a dbus-run-session -- ${python.interpreter} -B -m unittest discover -v -s
    tests -t .` and `${python.interpreter} -B -m unittest -v nix/test_merge_settings.py`
    (with `PYTHONPATH=$PWD`). `git` is NOT a check input, so `tests/test_install.py`
    skips by design.
  - `meta = { license = lib.licenses.gpl3Plus; mainProgram = "omapod";
    platforms = lib.platforms.linux; homepage = "https://github.com/arikisonfire/omapod"; }`.
- **NixOS module** `programs.omapod`: `enable` (systemPackages), `package`,
  `defaultHandler` (default true) → `xdg.mime.defaultApplications` for
  `x-scheme-handler/{podcast,itpc,pcast,antennapod-subscribe}`, `text/x-opml`,
  `text/x-opml+xml` = `io.github.arikisonfire.OmaPod.desktop`.
- **Home Manager module** `programs.omapod`:
  - `enable` (home.packages), `package`.
  - `refreshTimer.enable` (false), `refreshTimer.onCalendar` ("hourly"): service
    `omapod-refresh` (`Type=oneshot`, `ExecStart=${package}/bin/omapod --refresh`,
    `Description=Refresh omaPOD podcasts`); timer (`OnCalendar`, `RandomizedDelaySec=5min`,
    `Persistent=true`, `WantedBy=timers.target`).
  - `keybindings.enable` (true), `keybindings.backend` (`"nixarchy"` | `"hyprland"`,
    default `"nixarchy"`), `keybindings.binds` (attrsOf (nullOr str), user values merged
    over defaults; `null` drops one). Keys and values typed
    `strMatching "^[A-Za-z0-9 +_.,-]+$"`. Defaults:
    `"SUPER + CTRL + SHIFT + K" = "toggle"`, `"… + COMMA" = "rewind"`,
    `"… + PERIOD" = "forward"`, `"… + N" = "skip"`, `"… + O" = "show"`.
    - nixarchy: `xdg.configFile."hypr/omapod-binds.lua"`, first line
      `-- Generated by programs.omapod; edits are overwritten on rebuild.`, then per bind
      `o.bind("<key>", "omaPOD: <args>", "<package>/bin/omapod ctl <args>")`. Never edit
      `bindings.lua`.
    - hyprland: `wayland.windowManager.hyprland.settings.bind` entries
      `"<MODS>, <KEY>, exec, <package>/bin/omapod ctl <args>"` (split key on ` + `; last
      part is the key, the rest joined by space are the mods).
  - `widget.enable` (false), `widget.showTitle` (true), `widget.maxTitleWidth`
    (ints.between 60 600, 180), `widget.hideWhenStopped` (false), `widget.launchCommand`
    (""), `widget.socketPath` (""). The package's `manifest.json` is rewritten at
    evaluation with these five as `barWidget.defaults` (`builtins.fromJSON` →
    `recursiveUpdate` → `pkgs.writeText`). `home.activation.omapodWidget`
    (`entryAfter ["writeBoundary"]`) on target
    `${config.xdg.configHome}/omarchy/plugins/io.github.arikisonfire.pod`:
    absent → stage + swap + `.nix-managed`; has `.nix-managed` → `cmp` each file, replace
    only if any differs; otherwise → leave it, print notice to hand over with
    `omarchy plugin remove io.github.arikisonfire.pod` or `install.sh --uninstall`. With
    `widget.enable = false` (module enabled): remove the target only if it has
    `.nix-managed`. Use `$DRY_RUN_CMD` for every write.
  - `settings` (attrsOf `(pkgs.formats.json {}).type`, `{}`): user service
    `omapod-settings` (`Type=oneshot`, `ExecStart=${package}/libexec/omapod-merge-settings
    ${jsonFile}`, `WantedBy=default.target`), so Home Manager restarts it when the file
    changes. Assertions refuse: `podcastindex_key`, `podcastindex_secret`,
    `parental_password_hash`, `local_folders`, `last_page`, `history_repair`,
    `mirror_downloads_ready`, `auto_db_export_last`, `stats_reset_ts`, any key starting
    `window_`, `sync_last_`, `remote_downloads_`, `queue_sync_`, `favorites_sync_`, and
    `proxy.password`. Unknown keys allowed.
  - `defaultHandler` (true): only if `config.xdg.mimeApps.enable`, set
    `xdg.mimeApps.defaultApplications.<type> = mkDefault [ desktop ]` for the six types.
    Never enable `xdg.mimeApps` itself.
- **Merge rules** (`nix/merge-settings.py <declared.json>`): imports `omapod.config`
  (`paths`, `instance_lock`, `_atomic_write`, `Settings._read` logic). Sidecar
  `paths.config / ".nix-settings.json"` = per key the value Nix last WROTE.
  1. `lock = instance_lock("nix-settings")`; None → print
     `omaPOD is running; settings apply at next login or rebuild`, exit 0, touch nothing.
  2. `settings.json` exists but unreadable/not an object → warn, exit 0.
  3. Sidecar missing/damaged → `{}`.
  4. Declared key K, file value F, recorded R, declared D:
     absent F → write D, record D; F == R → write D, record D; F == D → record D;
     else keep F, R unchanged.
  5. Recorded key no longer declared: F == R → delete from file; always drop from sidecar.
  6. Write `settings.json` (atomic, 0600, `json.dumps(..., indent=2, sort_keys=True)+"\n"`)
     only if changed, then the sidecar (same writer).
  7. `OMAPOD_HOME` unset for the service (systemd user env does not have it).

## Steps

1. **Package + flake skeleton.** `nix/package.nix`, `flake.nix` (packages, apps,
   overlay, `checks.<s>.package`; module outputs as `import ./nix/nixos.nix self` etc.
   can wait for steps 3–4). Leave the `merge-settings` libexec and its checkPhase line
   out until step 2.
   → verify: `nix build -L .#omapod` (suite passes; read the `-v` log: only
   `test_install` skipped, `test_dock` and `test_tiling` ran),
   `nix run . -- --version` prints `omaPOD 0.1.5`,
   `ls result/share/omapod/widget` has no `omapod/`,
   `desktop-file-validate result/share/applications/*.desktop`.
   Traps: `wrapGAppsHook4` only fills `gappsWrapperArgs` in `preFixup`, so the manual
   `makeWrapper` goes in `postFixup`. `-P` must stay (security: cwd off `sys.path`). If
   Xvfb tests are flaky in the sandbox, run them only in the VM test (step 5), and record
   that as a plan deviation.
2. **Settings merge.** `nix/merge-settings.py`, `nix/test_merge_settings.py`; wire both
   into `nix/package.nix` (libexec wrapper, checkPhase line).
   → verify: `nix build -L .#omapod`; the test log lists one test per rule in step 4–6
   above, plus: Codex's example (1.5 → user 2.0 → declare 2.0 then 3.0), busy lock
   (hold `instance_lock("app")` in the test, assert file unchanged and exit 0), damaged
   `settings.json`, damaged sidecar, rollback (older declaration after newer).
   Traps: tests set `XDG_CONFIG_HOME`/`XDG_RUNTIME_DIR` to temp dirs and must reload
   `omapod.config` (its `paths` is module-level) or construct `Paths()` fresh. Never
   import GTK. Use the app's `_atomic_write`, don't copy it.
3. **NixOS module.** `nix/nixos.nix`; `nixosModules.default` in `flake.nix`.
   → verify: `nix eval .#nixosModules.default --apply builtins.isFunction` and a throwaway
   `nix eval` of a minimal `nixosSystem` with `programs.omapod.enable = true` reading
   `config.environment.etc."xdg/mimeapps.list".text`.
   Traps: `xdg.mime.defaultApplications` values are lists or strings, both fine.
4. **Home Manager module.** `nix/home.nix`; `homeManagerModules.default`.
   → verify: `nix eval` a `home-manager.lib.homeManagerConfiguration` with every option
   set: check `xdg.configFile."hypr/omapod-binds.lua".text`, the hyprland bind list with
   `backend = "hyprland"`, the systemd units, and that `settings.local_folders = [ ]`
   fails with the assertion message naming the key.
   Traps: `xdg.mimeApps` must not be enabled by this module. Activation scripts use
   `$DRY_RUN_CMD` and run as the user; quote every path (`$HOME` may contain spaces).
5. **VM test.** `nix/test.nix` (`pkgs.testers.runNixOSTest`), `checks.x86_64-linux.vm`.
   Scenario and assertions exactly as spec "nix/test.nix": user `alice`
   (`isNormalUser`, `linger = true`), `home-manager.nixosModules.home-manager`, seeded
   `settings.json` `{ "rewind_secs": 5 }` by a oneshot ordered `before =
   [ "home-manager-alice.service" ]`, Home Manager with `refreshTimer.enable`,
   `widget.enable` + `widget.maxTitleWidth = 240`, binds with `"… + N" = null` and
   `"SUPER + CTRL + SHIFT + 1" = "speed 1.5"`, `settings.speed = 1.5`. Checks 1–7 from the
   spec, run as alice with `XDG_RUNTIME_DIR=/run/user/$(id -u alice)`; the GUI under
   `xvfb-run -a dbus-run-session` with `OMAPOD_MPV_AO=null`.
   → verify: `nix build -L .#checks.x86_64-linux.vm`.
   Traps: `wait_for_unit("default.target", "alice")` before user-systemd calls. The
   app needs a few seconds before `ctl state` answers: `wait_until_succeeds`.
6. **CI.** `.github/workflows/nix.yml`: `on: [push, pull_request, workflow_dispatch]`,
   `permissions: contents: read`, job `check` (`ubuntu-latest`: checkout, KVM udev rule
   `KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"` + `udevadm
   trigger`, `cachix/install-nix-action`, `nix flake check -L`), job `aarch64`
   (`ubuntu-24.04-arm`: checkout, install-nix, `nix build -L
   .#packages.aarch64-linux.default`). Actions pinned to full commit SHAs with a
   `# vX.Y.Z` comment (look the SHAs up with `gh api`).
   → verify: `actionlint .github/workflows/nix.yml`.
   Traps: `nix flake check` on x86_64 evaluates aarch64 outputs but does not build them;
   fine.
7. **README.** New `## NixOS` after `## Install` (Arch section untouched): flake input
   and `nix run`; NixOS module; Home Manager example identical to the VM test's config
   plus comments for every option; the `pcall(require, "hypr.omapod-binds")` line for
   `bindings.lua`; settings precedence table (short) and refused keys; widget handover
   and `omarchy plugin enable`; update (`nix flake update omapod`, rebuild); remove (drop
   the import; library in `~/.local/share/omapod`, `~/.config/omapod` stays); known
   limit: no "newer version waits for a restart" notice under Nix. `## Development` gains
   `nix build` and `nix flake check`.
   → verify: every option name in the README exists in `nix/home.nix`/`nix/nixos.nix`
   (grep), and the example block evaluates (`nix eval` it inside step 4's harness).
8. **Widget defaults check (session; needs you).** Not possible in the VM (no Omarchy
   shell), and the session does not write this machine's real
   `~/.config/omarchy/plugins` on its own: that reloads every plugin in your bar. The PR
   and README mark the five `widget.*` options "unverified: may only prefill the bar's
   settings form". After merge, once you adopt the module with `widget.enable = true`
   and add the widget to the bar, check its new entry in `~/.config/omarchy/shell.json`;
   a follow-up adjusts the docs or drops the options.
9. **Review and PR (session).** Fresh Opus reviewer with only this plan path and
   `git diff main...`; Codex read-only review of the same diff; fix confirmed findings.
   Ask before pushing the branch and opening the PR (outward-facing). PR links intent,
   spec and plan, lists which steps each coder did, and says what CI and the VM test
   showed.

## Tests

| Command | Expected |
|---|---|
| `nix build -L .#omapod` | suite passes; only `test_install` skipped |
| `nix run . -- --version` | `omaPOD 0.1.5` |
| `nix build -L .#checks.x86_64-linux.vm` | VM test passes, checks 1–7 |
| `nix flake check -L` | all checks pass |
| `actionlint .github/workflows/nix.yml` | no output |
| GitHub Actions on the PR | both jobs green |

## Rollback

Everything is new files plus one README section on `feat/nixos-flake`. Undo by deleting
the branch, or `git revert` the implementation commits. No host is switched, no user
config is touched by building; a user who adopted the module removes the import and
rebuilds (the widget folder is removed only if `.nix-managed`; settings stay).
