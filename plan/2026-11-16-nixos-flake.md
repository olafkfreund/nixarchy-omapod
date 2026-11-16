---
status: approved
issue: none (issues disabled on olafkfreund/nixarchy-omapod)
spec: spec/2026-11-16-nixos-flake.md
coders:
  1: coder   # package + flake skeleton: Nix boilerplate, many small parts
  1a: codex  # mpv credential fix + detection test + test runner: small, security-sensitive
  2: codex   # merge-settings.py: small, tricky ownership/lock logic with a test table
  3: coder   # NixOS module: short, conventional
  4: coder   # Home Manager module + shared example: several options, conventional Nix
  5: coder   # VM test: Nix + Python test driver, needs the modules from 3-4
  6: coder   # CI workflow: one YAML file
  7: coder   # README section
reviewers:
  - codex    # independent read of the full diff against this plan before the PR
# agy: out of use by owner decision (#2748). Default routing would have sent step 7
# (large mechanical doc edit) to agy; it goes to coder instead.
---

# Plan: Install omaPOD on NixOS with a flake

Branch `feat/nixos-flake`. Builds run on p620 (local, KVM present), never p510. The
session (Opus) builds, verifies and commits each step after its coder hands it back;
coders never stage, commit or push.

## Changes against the approved spec (approving this plan approves them)

- **A. Shared example file.** New `nix/example-home.nix`: the Home Manager config used
  by the VM test, the step-4 eval harness and, verbatim, the README. One source, so the
  README example is proven to evaluate.
- **B. Widget defaults check moves after merge.** The spec asked to check once by hand
  whether the Omarchy shell seeds a new bar entry from `barWidget.defaults`, then keep,
  re-document or drop the five `widget.*` options. That check needs the real Omarchy
  shell (not in the VM), and writing this machine's `~/.config/omarchy/plugins` reloads
  every plugin in your bar, so the session will not do it by itself. Instead the PR ships
  the options marked in the README as "unverified: may only prefill the bar's settings
  form", and the check happens once you adopt the module (step 8). If you would rather
  do the check before the PR, say so and step 8 moves before step 9.
- **C. Damaged or missing sidecar** (the spec's ownership table and failure rule
  disagreed for a value that already equals the declaration): in a run without a usable
  sidecar, only keys absent from `settings.json` are written and recorded; every key
  already present counts as the user's and is not recorded, even if it equals the
  declared value. The first-ever run is such a run.
- **D. Removal:** removing the import cannot clean up the widget folder (the activation
  script goes with it). The README says: set `widget.enable = false`, rebuild, then
  remove the import.

## Changes found during step 1 (re-approval needed)

- **E. App fix: mpv 0.42 sends podcast passwords before being asked.** Found by
  `tests/test_hardening.py:348` failing in the Nix build. Cause, confirmed by tracing
  (`--msg-level=all=trace`) against a local server: mpv 0.42 serves `http(s)://` through
  a new libcurl backend (`[curl]` in the log), and libcurl sends URL credentials as
  `Authorization: Basic` on the **first** request. The app's design
  (`omapod/player/controller.py:300-305`) relies on FFmpeg, which sends them only after
  a 401. FFmpeg 9.0.2 alone (ffprobe) and mpv with `--curl-enabled=no` both send nothing
  until asked. Credentials still never reached another host (libcurl drops them on
  cross-host redirects), so the exposure is: the podcast's own server gets the password
  on paths that did not ask for it. Not Nix-specific: any mpv ≥ 0.42 built with libcurl
  does this, Arch included. You chose to fix it in this task (new step 1a). This
  widens scope to `omapod/player/mpv.py` and `tests/`.
- **F. Three hardening tests cannot run in the build sandbox.** There `/` is owned by
  uid 65534 (`nobody`), so `omapod.config.others_can_change()` correctly reports every
  path as changeable by others: `ImportedFolders.test_choosing_the_folder_here_gives_its_podcast_its_files_back`,
  `LocalFolders.test_files_stay_unless_the_user_confirms_and_then_go_to_the_trash`,
  `SharedFolders.test_files_of_an_added_folder_that_others_can_change_stay` (all in
  `tests/test_hardening.py`). Same treatment as the approved Xvfb fallback: excluded
  from the build by name, run in the VM test (step 5, item 11). `test_tiling` and
  `test_dock` pass in the sandbox, so they stay in the build.
- **G. Step-1 implementation details** (coder): the package source is
  `lib.fileset.toSource` of what the tests need, including `README.md` and `install.sh`
  (`test_layout` and `test_install.LaunchersTest` read them); checkPhase puts a
  `dbus-run-session` wrapper first on `PATH` that adds
  `--config-file=${dbus}/share/dbus-1/session.conf` (the sandbox has no
  `/etc/dbus-1/session.conf`, and `test_tiling` calls `dbus-run-session` itself);
  `meta.description` added.

- **H. Step-4 details** (coder, reviewed by the lead): the widget install writes
  `.nix-managed` into the staging dir before the `mv`, so a crash never leaves an
  unmarked folder; an extra assertion checks bind key names (`attrsOf` cannot type
  keys); the step-4 assertion check had a stray `!` and is corrected; the
  `omapod-settings` service exists whenever the module is enabled (also with
  `settings = { }`, so keys Nix wrote earlier are dropped when removed).

## Approved decisions (from the spec; no need to open it)

- **Files:** `flake.nix`, `flake.lock`, `nix/package.nix`, `nix/nixos.nix`,
  `nix/home.nix`, `nix/example-home.nix`, `nix/merge-settings.py`,
  `nix/test_merge_settings.py`, `nix/test.nix`, `.github/workflows/nix.yml`,
  `README.md`, `nix/run-tests.py`; and for change E only `omapod/player/mpv.py` and
  `tests/test_player.py`, `tests/test_hardening.py` (added tests only) and
  `tests/census.txt` (deviation in step 1a: the census test in `tests/test_exposure.py`
  requires every new outside call to be listed; two lines added for `Mpv.start →
  shutil.which` and `_curl_enabled_option → subprocess.run`). No other change under
  `omapod/`, `tests/`, `plugin/`, `data/`,
  nor to `install.sh` or `manifest.json`.
- **Flake:** inputs `nixpkgs` (`github:NixOS/nixpkgs/nixos-unstable`) and `home-manager`
  (`github:nix-community/home-manager`, `inputs.nixpkgs.follows = "nixpkgs"`; used only
  by checks). Systems `x86_64-linux`, `aarch64-linux`. Outputs:
  `packages.<s>.{default,omapod}`, `apps.<s>.default`, `overlays.default`
  (`omapod = final.callPackage ./nix/package.nix {}`), `nixosModules.default`,
  `homeManagerModules.default`, `checks.<s>.package`, `checks.x86_64-linux.vm`. Modules
  default `package` to `self.packages.${pkgs.stdenv.hostPlatform.system}.omapod`, so no
  overlay is needed. No devShell, formatter or Cachix.
- **Package** (`stdenv.mkDerivation`, `pname = "omapod"`, version parsed from
  `omapod/__init__.py` line `VERSION = "0.1.5"`):
  - `python = python3.withPackages (ps: [ ps.pygobject3 ])`.
  - `nativeBuildInputs = [ wrapGAppsHook4 gobject-introspection makeWrapper ]`;
    `buildInputs = [ gtk4 libadwaita gdk-pixbuf pango graphene glib ]` (covers every
    `gi.repository` import: Adw Gdk GdkPixbuf Gio GLib GObject Graphene Gsk Gtk Pango).
  - Layout: `$out/share/omapod/omapod/` (Python package, no `__pycache__`);
    `$out/share/omapod/merge-settings.py`;
    `$out/share/omapod/widget/{manifest.json,plugin/BarWidget.qml,LICENSE}` (no app
    source beside it, so the widget runs `uwsm-app -- omapod` from `PATH`, not bare
    `python3`); `$out/share/applications/io.github.arikisonfire.OmaPod.desktop` from
    `data/io.github.arikisonfire.OmaPod.desktop.in` with `@BIN@` → `$out/bin/omapod`;
    `$out/share/icons/hicolor/scalable/apps/io.github.arikisonfire.OmaPod.svg`.
  - `dontWrapGApps = true`; in `postFixup`: `makeWrapper ${python}/bin/python3
    $out/bin/omapod --add-flags "-P -m omapod" --prefix PYTHONPATH : $out/share/omapod
    --suffix PATH : ${lib.makeBinPath [ mpv xdg-utils ]} "''${gappsWrapperArgs[@]}"`,
    and `$out/libexec/omapod-merge-settings` the same but `--add-flags "-P
    $out/share/omapod/merge-settings.py"`.
  - `doCheck = true`; `nativeCheckInputs = [ python mpv openssl xvfb-run dbus ]`;
    `checkPhase`: `export HOME=$TMPDIR OMAPOD_MPV_AO=null`; `xvfb-run -a
    dbus-run-session -- ${python.interpreter} -B -m unittest discover -v -s tests -t .`;
    then `PYTHONPATH=$PWD ${python.interpreter} -B -m unittest -v
    nix/test_merge_settings.py`. `git` is not a check input, so `tests/test_install.py`
    skips by design (it tests `install.sh`).
  - `meta = { license = lib.licenses.gpl3Plus; mainProgram = "omapod";
    platforms = lib.platforms.linux; homepage = "https://github.com/arikisonfire/omapod"; }`.
- **NixOS module** `programs.omapod`: `enable` (`environment.systemPackages`),
  `package`, `defaultHandler` (default true) → `xdg.mime.defaultApplications` for
  `x-scheme-handler/{podcast,itpc,pcast,antennapod-subscribe}`, `text/x-opml`,
  `text/x-opml+xml` = `io.github.arikisonfire.OmaPod.desktop` (system default; the
  user's `~/.config/mimeapps.list` still wins). No user units here.
- **Home Manager module** `programs.omapod`:
  - `enable` (`home.packages`), `package`.
  - `refreshTimer.enable` (false), `refreshTimer.onCalendar` ("hourly"): service
    `omapod-refresh` (`Type=oneshot`, `ExecStart=${package}/bin/omapod --refresh`,
    `Description=Refresh omaPOD podcasts`); timer (`OnCalendar`,
    `RandomizedDelaySec=5min`, `Persistent=true`, `WantedBy=timers.target`).
  - `keybindings.enable` (true), `keybindings.backend` (`"nixarchy"` | `"hyprland"`,
    default `"nixarchy"`), `keybindings.binds` (`attrsOf (nullOr str)`, user values merged
    over defaults; `null` drops one). Keys and values typed
    `strMatching "^[A-Za-z0-9 +_.,-]+$"`. Defaults:
    `"SUPER + CTRL + SHIFT + K" = "toggle"`, `"SUPER + CTRL + SHIFT + COMMA" = "rewind"`,
    `"SUPER + CTRL + SHIFT + PERIOD" = "forward"`, `"SUPER + CTRL + SHIFT + N" = "skip"`,
    `"SUPER + CTRL + SHIFT + O" = "show"`.
    - nixarchy: `xdg.configFile."hypr/omapod-binds.lua".text`, first line
      `-- Generated by programs.omapod; edits are overwritten on rebuild.`, then per bind
      `o.bind("<key>", "omaPOD: <args>", "<package>/bin/omapod ctl <args>")`. Never edit
      `bindings.lua`; the user adds `pcall(require, "hypr.omapod-binds")` to it once.
    - hyprland: `wayland.windowManager.hyprland.settings.bind` entries
      `"<MODS>, <KEY>, exec, <package>/bin/omapod ctl <args>"` (split the key on ` + `;
      the last part is the key, the rest joined by a space are the mods).
  - `widget.enable` (false), `widget.showTitle` (true), `widget.maxTitleWidth`
    (`ints.between 60 600`, 180), `widget.hideWhenStopped` (false),
    `widget.launchCommand` (""), `widget.socketPath` (""). The package's
    `share/omapod/widget/manifest.json` is rewritten at evaluation with the five as
    `barWidget.defaults` (`builtins.fromJSON (builtins.readFile …)` →
    `lib.recursiveUpdate` → `pkgs.writeText`), into a widget dir built with
    `pkgs.runCommand`. `home.activation.omapodWidget`
    (`lib.hm.dag.entryAfter [ "writeBoundary" ]`), target
    `${config.xdg.configHome}/omarchy/plugins/io.github.arikisonfire.pod`:
    absent → copy into `.io.github.arikisonfire.pod.new` beside it, `mv` into place, write
    `.nix-managed`; present with `.nix-managed` → `cmp -s` each file, replace the same way
    only if any differs; present without it (marketplace `.git` clone, `install.sh` copy,
    hand-edited) → leave it, print: "omaPOD: the bar widget at <path> is not managed by
    Nix; to hand it over run `omarchy plugin remove io.github.arikisonfire.pod` or
    `install.sh --uninstall`, then rebuild." With `programs.omapod.enable` and
    `widget.enable = false`: remove the target only if it has `.nix-managed`. Every write
    via `$DRY_RUN_CMD`; quote every path.
  - `settings` (`attrsOf (pkgs.formats.json {}).type`, `{}`): `jsonFile =
    (pkgs.formats.json {}).generate "omapod-settings.json" cfg.settings`; user service
    `omapod-settings` (`Type=oneshot`, `ExecStart=${package}/libexec/omapod-merge-settings
    ${jsonFile}`, `UnsetEnvironment=OMAPOD_HOME`, `WantedBy=default.target`), so Home
    Manager restarts it when the file changes and it runs at login. Assertions refuse
    (message names the key): `podcastindex_key`, `podcastindex_secret`,
    `parental_password_hash`, `local_folders`, `last_page`, `history_repair`,
    `mirror_downloads_ready`, `auto_db_export_last`, `stats_reset_ts`, any key starting
    `window_`, `sync_last_`, `remote_downloads_`, `queue_sync_`, `favorites_sync_`, and
    `proxy.password`. Unknown keys allowed.
  - `defaultHandler` (true): only if `config.xdg.mimeApps.enable`, set
    `xdg.mimeApps.defaultApplications.<type> = lib.mkDefault [ desktop ]` for the six
    types. Never enable `xdg.mimeApps` itself.
- **Merge rules** (`nix/merge-settings.py <declared.json>`), reusing `omapod.config`'s
  `paths`, `instance_lock` and `_atomic_write` (`omapod/config.py:238-251`, `:440-464`);
  read files the way `Settings._read` does (`:270-277`). Use a module-level `MISSING =
  object()` sentinel so an absent value never equals JSON `null`. Sidecar
  `paths.config / ".nix-settings.json"` = per key the value Nix last **wrote**.
  1. `lock = instance_lock("nix-settings")`; `None` → print `omaPOD is running; settings
     apply at next login or rebuild`, exit 0, touch nothing. Keep `lock` open until both
     writes are done.
  2. `settings.json` exists but unreadable or not an object → print a warning, exit 0.
  3. Sidecar missing, unreadable or not an object → "no sidecar" mode (change C).
  4. For each declared key K (declared D, file F, recorded R):
     - F absent → write D, record D.
     - no-sidecar mode and F present → keep F, do not record.
     - F == R → write D, record D.
     - F == D → record D.
     - else → keep F, R unchanged.
  5. For each recorded key no longer declared: F == R → delete from file; drop from the
     sidecar either way.
  6. Write `settings.json` (`_atomic_write`, `json.dumps(…, indent=2, sort_keys=True) +
     "\n"`) only if it changed; then the sidecar the same way.

## Steps

1. **Package and flake skeleton.** Create `nix/package.nix` and `flake.nix` (inputs,
   `packages`, `apps`, `overlays`, `checks.<s>.package`); run `nix flake lock` to create
   `flake.lock`. Leave `merge-settings` (libexec, share file, its checkPhase line) out
   until step 2; module outputs come in steps 3–4.
   → verify:
   ```bash
   nix build -L .#omapod 2>&1 | tee /tmp/claude-omapod-build.log
   grep -E "skipped|^Ran|OK|FAILED" /tmp/claude-omapod-build.log   # only test_install skips
   nix run . -- --version                                           # omaPOD 0.1.5
   test ! -e result/share/omapod/widget/omapod
   nix shell nixpkgs#desktop-file-utils -c desktop-file-validate result/share/applications/*.desktop
   ```
   Traps: `wrapGAppsHook4` fills `gappsWrapperArgs` in `preFixup`, so the manual
   `makeWrapper` goes in `postFixup`. Keep `-P` (keeps the working directory off
   `sys.path`). If `test_tiling`/`test_dock` are flaky in the sandbox: drop them from the
   checkPhase with `-k`-style exclusion, run them in the VM (step 5, fallback), say so in
   README `## Development` and the PR, and update this plan in the same commit.
1a. **App fix: keep mpv on FFmpeg's networking (change E).** In
   `omapod/player/mpv.py`, `Mpv.start` (args list at lines 62-70, `extra_args` appended
   at line 74): add `--curl-enabled=no` **after** `self.extra_args`, so nothing passed
   earlier can turn libcurl back on (mpv takes the last value). Comment the why in one
   line in the file's style (see the `--tls-verify` comment above the list).
   Detection, a small module-level helper called lazily from `start()` (not at import):
   - Resolve `path = shutil.which("mpv")`, then `os.path.realpath(path)` and its
     `st_mtime_ns`; the cache maps `(realpath, mtime)` to the result, so an mpv replaced
     while omaPOD runs is probed again.
   - Probe: `subprocess.run([path, "--list-options"], capture_output=True, text=True,
     timeout=3)`. Exit 0 and `"--curl-enabled"` in stdout → supported (add the flag).
     Exit 0 without it → not supported (no flag; mpv before 0.42 has no libcurl backend
     and rejects unknown options). Any error (timeout, `OSError`, non-zero exit) →
     **fail closed**: add the flag anyway and do not cache, so a curl-enabled mpv never
     runs without it; on an old mpv that start fails visibly and the next start probes
     again.
   - Start the subprocess with that same resolved `path`, not the bare `"mpv"`, so the
     probed and the launched binary are one. Keep the rest of the arg order unchanged.
   - Worst-case added delay is the 3 s timeout, once per mpv binary; normal cost is one
     `--list-options` run (tens of ms) per binary.
   Tests:
   - In `tests/test_player.py`, one detection test with fake `mpv` scripts on `PATH`:
     lists the option → flag present and last; exit 0 without it → no flag; exit 1 → flag
     present and not cached; sleeps past the timeout → flag present; replacing the script
     (new mtime) → probed again. Reset the cache between cases.
   - In `tests/test_hardening.py`, **add** (do not edit existing tests) next to
     `CredentialsStayWithTheirHost.test_stream_redirected_to_another_host_does_not_take_the_password_along`
     (lines 318-349), reusing its helpers (`self.host`, `private`, `credentials`, `AUTH`):
     (a) the first request to a private path carries no credentials, the retry after 401
     does; (b) an authenticated private path redirecting to another host: that host gets
     none; (c) the other host answering 401: it still gets none. Each must fail with
     mpv 0.42 when the flag is removed (check once by hand, then restore).
   Also create `nix/run-tests.py`: runs discovery like `python -m unittest discover -v -s
   tests -t .`, removes the three test ids of change F from the suite, prints each as
   `excluded in the Nix sandbox: <id> (/ is owned by nobody)`, and exits non-zero on
   failure. Use it in `nix/package.nix`'s checkPhase in place of the plain discover.
   In `nix/package.nix` also add `$out/libexec/omapod-python`: `makeWrapper
   ${python}/bin/python3` with the same `PATH` suffix and `"''${gappsWrapperArgs[@]}"`
   as the app but no `--add-flags`, for running tests in the VM (step 5, item 11).
   → verify: `nix build -L .#omapod`: the existing redirect test and the three new
   credential tests pass, the detection test passes, the three exclusions are printed,
   only `test_install` skips; then `nix run . -- --version` and step 1's other checks.
   On this host also (system mpv 0.42): `python3 -B -m unittest -v
   tests.test_hardening.CredentialsStayWithTheirHost tests.test_player` passes.
   Traps: never pass `--curl-enabled=no` when a successful listing lacks it. Probe
   failures are not cached. Do not edit existing tests.
2. **Settings merge.** Create `nix/merge-settings.py` and `nix/test_merge_settings.py`;
   in `nix/package.nix` add the share file, the libexec wrapper and the checkPhase line.
   → verify: `nix build -L .#omapod`; the log shows one passing test for each rule in
   "Merge rules" 1–6, plus: the example (declare 1.5 → user sets 2.0 → declare 2.0, then
   3.0: user's 2.0 stays and becomes Nix-owned at the 2.0 step); busy lock (test holds
   `instance_lock("app")`; file unchanged, exit 0); damaged `settings.json`; damaged
   sidecar; first run with a present key equal to the declared value (not recorded);
   rollback (an older declaration after a newer one); `null` declared vs key absent.
   Traps: `omapod.config.paths` is created at import from `XDG_*`/`OMAPOD_*`; each test
   sets `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_RUNTIME_DIR` to a temp dir, unsets
   `OMAPOD_HOME`/`OMAPOD_RUNTIME_DIR`, and runs the script as a subprocess (fresh
   import) or builds `Paths()` fresh. Never import GTK. Reuse `_atomic_write`, do not copy it.
3. **NixOS module.** Create `nix/nixos.nix`; add `nixosModules.default` to `flake.nix`.
   → verify:
   ```bash
   nix eval --raw --impure --expr 'let f = builtins.getFlake (toString ./.); s = f.inputs.nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ f.nixosModules.default { programs.omapod.enable = true; boot.isContainer = true; system.stateVersion = "25.11"; } ]; }; in s.config.environment.etc."xdg/mimeapps.list".text'
   # six lines naming io.github.arikisonfire.OmaPod.desktop
   ```
   Traps: run from the repo root; `getFlake` of a git dir sees only tracked files, so
   `git add -N` new files first.
4. **Home Manager module and shared example.** Create `nix/home.nix` and
   `nix/example-home.nix` (every option set: `enable`, `refreshTimer.enable`,
   `widget.enable`, `widget.maxTitleWidth = 240`, `keybindings.binds = { "SUPER + CTRL +
   SHIFT + N" = null; "SUPER + CTRL + SHIFT + 1" = "speed 1.5"; }`, `settings.speed =
   1.5`, the rest at defaults with a comment each); add `homeManagerModules.default` to
   `flake.nix`.
   → verify (define `HM` once):
   ```bash
   HM='let f = builtins.getFlake (toString ./.); pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; mk = extra: f.inputs.home-manager.lib.homeManagerConfiguration { inherit pkgs; modules = [ f.homeManagerModules.default ./nix/example-home.nix { home.username = "alice"; home.homeDirectory = "/home/alice"; home.stateVersion = "25.11"; } extra ]; };'
   nix eval --raw --impure --expr "$HM in (mk {}).config.xdg.configFile.\"hypr/omapod-binds.lua\".text"
   # header + 5 o.bind lines (4 defaults without N, plus speed 1.5)
   nix eval --json --impure --expr "$HM in (mk { programs.omapod.keybindings.backend = \"hyprland\"; wayland.windowManager.hyprland.enable = true; }).config.wayland.windowManager.hyprland.settings.bind"
   nix eval --json --impure --expr "$HM in builtins.attrNames (mk {}).config.systemd.user.services"   # omapod-refresh, omapod-settings
   nix eval --impure --expr "$HM in (mk { programs.omapod.settings.local_folders = [ ]; }).activationPackage" 2>&1 | grep -q local_folders || echo "assertion missing"
   ```
   Traps: this module must not set `xdg.mimeApps.enable`. Activation runs as the user;
   every write through `$DRY_RUN_CMD`, every path quoted (`$HOME` may hold spaces).
5. **VM test.** Create `nix/test.nix` (`pkgs.testers.runNixOSTest`); add
   `checks.x86_64-linux.vm` to `flake.nix`, passing `self` and `home-manager`.
   Node: `imports = [ self.nixosModules.default home-manager.nixosModules.home-manager ]`;
   `programs.omapod.enable = true`; `users.users.alice = { isNormalUser = true; linger =
   true; uid = 1000; }`; `home-manager.users.alice = { imports = [
   self.homeManagerModules.default ../nix/example-home.nix ]; home.stateVersion =
   "25.11"; }`; `environment.systemPackages = [ pkgs.xvfb-run pkgs.dbus ]`; a oneshot
   `seed-omapod` (`before = [ "home-manager-alice.service" ]`, `wantedBy =
   [ "multi-user.target" ]`, `User = "alice"`) writing
   `/home/alice/.config/omapod/settings.json` = `{"rewind_secs": 5}`.
   Helper `as_alice(cmd)` = `su - alice -c 'export XDG_RUNTIME_DIR=/run/user/1000
   DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; <cmd>'`.
   Script, in order (each a `succeed`/`wait_until_succeeds`):
   1. `wait_for_unit("home-manager-alice.service")`,
      `wait_for_unit("default.target", "alice")`.
   2. `/run/current-system/sw/share/applications/io.github.arikisonfire.OmaPod.desktop`
      contains all four `x-scheme-handler/` schemes; `/etc/xdg/mimeapps.list` contains
      `io.github.arikisonfire.OmaPod.desktop`.
   3. `~alice/.config/hypr/omapod-binds.lua`: contains `ctl toggle`, `ctl rewind`,
      `ctl forward`, `ctl show`, `ctl speed 1.5`; does not contain `ctl skip`.
   4. `wait_until_succeeds` on `settings.json`: `jq -e '.speed == 1.5 and .rewind_secs
      == 5'`; `stat -c %a` is `600`.
   5. As alice: set `.speed = 2.0` in the file (jq + mv), `systemctl --user restart
      omapod-settings.service`, then `.speed == 2.0` still.
   6. Widget dir has `manifest.json` with `.barWidget.defaults.maxTitleWidth == 240`,
      `plugin/BarWidget.qml`, `.nix-managed`, and no `omapod/`.
   7. As alice: `systemctl --user is-enabled omapod-refresh.timer`; `systemctl --user
      start omapod-refresh.service` succeeds (no podcasts, nothing to do).
   8. As alice, in the background: `OMAPOD_MPV_AO=null xvfb-run -a dbus-run-session --
      omapod >/tmp/omapod.log 2>&1 &`; `wait_until_succeeds(as_alice("omapod ctl state"),
      timeout=60)` and its output parses as JSON.
   9. While it runs: `systemctl --user restart omapod-settings.service` succeeds and
      `journalctl --user -u omapod-settings -n 5` contains `omaPOD is running`.
   10. `OMAPOD_HOME` is ignored: `systemctl --user set-environment
       OMAPOD_HOME=/tmp/elsewhere`, quit the app (`omapod ctl quit`, wait until `ctl
       state` fails), restart `omapod-settings.service`; `/tmp/elsewhere` does not exist.
   11. The three tests of change F, as alice: `cp -r ${self} /tmp/src && cd /tmp/src &&
       OMAPOD_MPV_AO=null HOME=/tmp/testhome ${pkgs.omapod}/libexec/omapod-python -B -m
       unittest -v
       tests.test_hardening.ImportedFolders.test_choosing_the_folder_here_gives_its_podcast_its_files_back
       tests.test_hardening.LocalFolders.test_files_stay_unless_the_user_confirms_and_then_go_to_the_trash
       tests.test_hardening.SharedFolders.test_files_of_an_added_folder_that_others_can_change_stay`
       (use this flake's package, not `pkgs.omapod`, if the overlay is not applied);
       output contains `Ran 3 tests` and `OK`, and no `skipped`.
   → verify: `nix build -L .#checks.x86_64-linux.vm`.
   Traps: the app needs seconds before `ctl state` answers; always `wait_until_succeeds`.
   `dbus-run-session` gives the app its own bus, so step 9 uses alice's user bus for
   systemctl, not the app's.
6. **CI.** Create `.github/workflows/nix.yml`: `on: { push: {}, pull_request: {},
   workflow_dispatch: {} }`, `permissions: { contents: read }`.
   - Job `check`, `runs-on: ubuntu-latest`: `actions/checkout`; KVM step:
     ```bash
     echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
     sudo udevadm control --reload-rules
     sudo udevadm trigger --name-match=kvm
     ls -l /dev/kvm
     ```
     `cachix/install-nix-action` (with `extra_nix_config: system-features = nixos-test
     benchmark big-parallel kvm`); `nix flake check -L`.
   - Job `aarch64`, `runs-on: ubuntu-24.04-arm`: checkout, install-nix,
     `nix build -L .#packages.aarch64-linux.default`.
   - Actions pinned to full commit SHAs with a `# vX.Y.Z` comment; get them with
     `gh api repos/actions/checkout/commits/<tag> -q .sha` and the same for
     `cachix/install-nix-action`.
   → verify: `actionlint .github/workflows/nix.yml` prints nothing. KVM access is proven
   only by the first CI run (step 9).
   Traps: `nix flake check` on x86_64 evaluates but does not build aarch64 outputs; the
   arm job covers that.
7. **README.** In `README.md`, add `## NixOS` right after `## Install` (Arch section
   untouched) containing: flake input + `nix run`; NixOS module import and
   `programs.omapod.enable`; Home Manager import; a line `<!-- example-home.nix -->`
   followed by a ```nix block that is `nix/example-home.nix` verbatim; the
   `pcall(require, "hypr.omapod-binds")` line for `bindings.lua`; settings precedence in
   three bullets (Nix sets defaults, a UI change wins, reset in the UI brings the Nix
   value back) and the refused keys; widget handover and `omarchy plugin enable
   io.github.arikisonfire.pod`; the "unverified" note on the five `widget.*` options
   (change B); update (`nix flake update omapod`, rebuild); remove (change D; library in
   `~/.local/share/omapod` and `~/.config/omapod` stays); known limit: no "newer version
   waits for a restart" notice under Nix. `## Development` gains `nix build -L` and
   `nix flake check -L`.
   → verify:
   ```bash
   diff <(awk '/<!-- example-home.nix -->/{f=1;next} f&&/^```nix/{g=1;next} g&&/^```/{exit} g' README.md) nix/example-home.nix
   for o in $(grep -oE 'programs\.omapod\.[A-Za-z.]+' README.md | sort -u | sed 's/programs\.omapod\.//'); do grep -q "${o##*.}" nix/home.nix nix/nixos.nix || echo "unknown option: $o"; done
   ```
   Traps: keep the Arch instructions exactly as they are; this fork tracks upstream.
8. **Widget defaults check (after merge; needs you).** Change B. Once you adopt the
   module with `widget.enable = true` and add the widget in the bar, read its new entry
   in `~/.config/omarchy/shell.json`: if it carries the Nix values, drop the
   "unverified" note; if not, re-document the options as form defaults or remove them in
   a follow-up.
9. **Review and PR (session).** A fresh Opus reviewer gets only this plan path and
   `git diff main...feat/nixos-flake`; Codex reviews the same diff read-only; confirmed
   findings are fixed and committed. Then ask you before pushing the branch and opening
   the PR (outward-facing). The PR links intent, spec and plan, says which coder did each
   step, and reports the build log skips, the VM test and the CI result for both jobs.

## Tests

| Command | Expected |
|---|---|
| `nix build -L .#omapod` | suite passes; only `test_install` skipped; 3 change-F tests listed as excluded; merge and mpv-detection tests pass |
| `nix run . -- --version` | `omaPOD 0.1.5` |
| step 3 and 4 `nix eval` commands | outputs as noted under each |
| `nix build -L .#checks.x86_64-linux.vm` | VM script steps 1–11 pass |
| `nix flake check -L` | all checks pass |
| `actionlint .github/workflows/nix.yml` | no output |
| step 7 `diff` and option loop | no output |
| GitHub Actions on the PR | `check` and `aarch64` green |

## Rollback

All new files plus one README section, on `feat/nixos-flake`. Undo by deleting the
branch or `git revert` of the implementation commits. Building touches no host config. A
user who adopted the module sets `widget.enable = false`, rebuilds, then removes the
import; the library and settings stay.
