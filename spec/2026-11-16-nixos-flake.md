---
status: draft
issue: none (issues disabled on olafkfreund/nixarchy-omapod; proceeding without, per intent approval)
intent: intent/2026-11-16-nixos-flake.md
---

# Spec: Install omaPOD on NixOS with a flake

## Decisions carried from the intent approval

| # | Question | Decision |
|---|---|---|
| 1 | Issue | None; slug without issue number |
| 2 | Module shape | NixOS module (install) **and** Home Manager module (per-user) |
| 3 | Keybindings | Home Manager, on by default, every key changeable or removable, one switch off. **Changed default keys, see below** |
| 4 | App settings | Free-form `settings`, applied as defaults the UI may override; secrets and state keys refused |
| 5 | Widget | Installed only; `omarchy plugin enable` stays with the user |
| 6 | Support | x86_64-linux and aarch64-linux, nixos-unstable |
| 7 | CI | `nix flake check` on `ubuntu-latest` with KVM, VM test included |

**Change against the approved answer to question 3.** Approval took the recommendation of
`Super+Alt+…` defaults with Home Manager's Hyprland option. Checking this machine
(`omarchy menu keybindings --print`) showed:

- `Super+Alt+P`, `N`, `O`, `[` and `]` are all taken (GitLab Pipelines, nixarchy packages,
  Podman, webcam overlay).
- nixarchy does not read `hyprland.conf`: its session uses Omarchy's `hyprland.lua`, and
  keys are bound in Lua with `o.bind(...)` in `~/.config/hypr/bindings.lua`. Other tools
  ship `~/.config/hypr/<name>-binds.lua` from Home Manager and `bindings.lua` loads each
  one with `pcall(require, "hypr.<name>-binds")` (e.g. `ai-mirror-binds.lua`).

So the spec uses `Super+Ctrl+Shift` (free here for K, O, N, comma, period) and a Lua bind
file for nixarchy, with Home Manager's Hyprland option as a second backend for plain
Hyprland. Approving this spec approves that change.

## Design

### Files

```text
flake.nix              inputs, outputs, checks
flake.lock
nix/package.nix        the omapod package
nix/nixos.nix          NixOS module: programs.omapod
nix/home.nix           Home Manager module: programs.omapod
nix/merge-settings.py  three-way settings merge run at Home Manager activation
nix/test.nix           NixOS VM test (both modules)
.github/workflows/nix.yml
README.md              new "NixOS" section
```

All new files sit under `nix/`, `.github/` and the repo root, so merges from upstream
`arikisonfire/omapod` touch none of them except the README section.

### flake.nix

- Inputs: `nixpkgs` (`nixos-unstable`), `home-manager` (follows nixpkgs; used by the VM
  test only, never by consumers' modules).
- Systems: `x86_64-linux`, `aarch64-linux`.
- Outputs:
  - `packages.<system>.{default,omapod}`, `apps.<system>.default` (`nix run`).
  - `overlays.default` adds `pkgs.omapod`.
  - `nixosModules.default` (`nix/nixos.nix`), `homeManagerModules.default` (`nix/home.nix`).
    Both default `package` to `self.packages.${pkgs.system}.omapod`, so no overlay is needed.
  - `checks.<system>.package` = the package (its build runs the test suite);
    `checks.x86_64-linux.vm` = `nix/test.nix`.
- No devShell, formatter or Cachix: not asked for.

### nix/package.nix

`stdenv.mkDerivation`, `pname = "omapod"`, `version` read from `omapod/__init__.py`
(`VERSION = "0.1.5"`) so it never drifts.

- `python = python3.withPackages (ps: [ ps.pygobject3 ])` (the app needs ≥ 3.11 for
  `tomllib`; unstable has 3.12+).
- `nativeBuildInputs = [ wrapGAppsHook4 gobject-introspection makeWrapper ]`,
  `buildInputs = [ gtk4 libadwaita gdk-pixbuf pango graphene glib ]`. That covers every
  `gi.repository` import: Adw Gdk GdkPixbuf Gio GLib GObject Graphene Gsk Gtk Pango.
- Install layout:
  - `$out/share/omapod/omapod/` the Python package, with `locale/de.json`, `data/style.css`
    and the symbolic icons (they live inside the package already).
  - `$out/share/omapod/widget/{manifest.json,plugin/BarWidget.qml,LICENSE}` the bar widget
    **without** the app source beside it, so the widget's "bundled" check
    (`plugin/BarWidget.qml:231-239`) fails and it runs `uwsm-app -- omapod` from `PATH`
    instead of bare `python3`.
  - `$out/share/applications/io.github.arikisonfire.OmaPod.desktop` from
    `data/*.desktop.in`, `@BIN@` → `$out/bin/omapod`. It keeps the URL scheme and OPML
    `MimeType` line.
  - `$out/share/icons/hicolor/scalable/apps/io.github.arikisonfire.OmaPod.svg`.
- Wrapper: `dontWrapGApps = true`, then in `postFixup`
  `makeWrapper ${python}/bin/python3 $out/bin/omapod --add-flags "-P -m omapod"
  --prefix PYTHONPATH : $out/share/omapod --suffix PATH : ${mpv}/bin:${xdg-utils}/bin
  "''${gappsWrapperArgs[@]}"`. `-P` matches `install.sh`. mpv and xdg-utils go on the
  `--suffix` so a user's own mpv wins; `hyprctl` comes from the session.
- Re-exec after a database import (`omapod/__main__.py:194-209`) runs `sys.executable`
  (the wrapped Python env) with the inherited environment, which still has `PYTHONPATH`,
  `GI_TYPELIB_PATH`, `XDG_DATA_DIRS` and `PATH` from the wrapper, so it works unchanged.
- `checkPhase` (`doCheck = true`): `HOME=$TMPDIR OMAPOD_MPV_AO=null xvfb-run -a
  dbus-run-session -- python -B -m unittest discover -v -s tests -t .`.
  `nativeCheckInputs = [ mpv openssl xvfb-run dbus ]` plus the GTK inputs. Running under
  Xvfb lets `test_dock` and `test_tiling` run instead of skip. `-v` prints every skip
  with its reason.
  - `tests/test_install.py` stays skipped by design: it tests `install.sh`, which Nix
    does not use, and needs `git` plus `/usr/bin`. `git` is left out of the check inputs
    so its skip guard (`tests/test_install.py:18-25`) holds.
- `meta`: `license = lib.licenses.gpl3Plus`, `mainProgram = "omapod"`,
  `platforms = lib.platforms.linux`, homepage upstream.

### nix/nixos.nix — `programs.omapod`

| Option | Type, default | Effect |
|---|---|---|
| `enable` | bool, false | `environment.systemPackages = [ package ]` (command, desktop entry, icon, widget files) |
| `package` | package, this flake's | |
| `defaultHandler` | bool, true | `xdg.mime.defaultApplications` for the four URL schemes and both OPML types → `/etc/xdg/mimeapps.list`. A user's own `~/.config/mimeapps.list` still wins, so a chosen app is never overridden |

Per-user things (timer, keys, widget, settings) are Home Manager's: a system-wide user
timer would start for every account, which `install.sh` never did.

### nix/home.nix — `programs.omapod`

| Option | Type, default | Effect |
|---|---|---|
| `enable` | bool, false | `home.packages = [ package ]` |
| `package` | package | |
| `refreshTimer.enable` | bool, false | `systemd.user.{services,timers}.omapod-refresh`, same unit text as `install.sh` (`ExecStart = omapod --refresh`, oneshot) |
| `refreshTimer.onCalendar` | str, `"hourly"` | `OnCalendar`; `RandomizedDelaySec=5min`, `Persistent=true` kept |
| `keybindings.enable` | bool, true | one switch for all keys |
| `keybindings.backend` | `"nixarchy"` \| `"hyprland"`, `"nixarchy"` | see below |
| `keybindings.binds` | attrsOf (nullOr str) | key → `omapod ctl` arguments; `null` drops a default |
| `widget.enable` | bool, false | install the bar widget (below) |
| `settings` | attrsOf JSON, `{}` | app preferences, merged into `settings.json` (below) |
| `defaultHandler` | bool, true | if the user already has `xdg.mimeApps.enable`, adds the URL/OPML defaults with `mkDefault`; never turns `xdg.mimeApps` on itself (that would replace their `mimeapps.list` with a store link) |

**Default binds** (`omapod ctl` actions from `omapod/__main__.py`):

| Key | Action |
|---|---|
| `SUPER + CTRL + SHIFT + K` | `toggle` |
| `SUPER + CTRL + SHIFT + COMMA` | `rewind` |
| `SUPER + CTRL + SHIFT + PERIOD` | `forward` |
| `SUPER + CTRL + SHIFT + N` | `skip` |
| `SUPER + CTRL + SHIFT + O` | `show` |

Speed and sleep have no default key; examples show `"SUPER + CTRL + SHIFT + 1" = "speed 1.5"`
and `"… + 0" = "sleep 30"`. Play/pause/next on media keys already work through MPRIS
(Omarchy binds `XF86AudioPlay` etc. to playerctl), so those keys are not rebound.

Keys and arguments are typed `strMatching "^[A-Za-z0-9 +_.,-]+$"`, so nothing needs
quoting in Lua or Hyprland syntax and nothing can inject code.

- `backend = "nixarchy"`: `xdg.configFile."hypr/omapod-binds.lua"` with one line per bind:
  `o.bind("SUPER + CTRL + SHIFT + K", "omaPOD: toggle", "<package>/bin/omapod ctl toggle")`,
  headed "Generated by programs.omapod; edits are overwritten on rebuild." The user adds
  `pcall(require, "hypr.omapod-binds")` to their own `bindings.lua` once (the README says
  so). The module never edits `bindings.lua`: it is user-owned and outlives generations.
- `backend = "hyprland"`: appends `"SUPER CTRL SHIFT, K, exec, omapod ctl toggle"` style
  entries to `wayland.windowManager.hyprland.settings.bind` (`+` → `, ` conversion of the
  modifiers).

**Widget** (`widget.enable`): a `home.activation` step after `writeBoundary`, mirroring
`install.sh --plugin`:

- target `~/.config/omarchy/plugins/io.github.arikisonfire.pod`;
- if it has `.git` (marketplace clone): print the same notice as `install.sh` and leave it;
- else if every file already matches (`cmp`): do nothing, so the shell does not reload;
- else copy the three files into a staging dir, swap it in, and write `.nix-managed`.
- With `widget.enable = false`, a target that has `.nix-managed` is removed; any other is
  left alone.

Copies, not store symlinks: the Omarchy shell watches that folder and it is not known
whether it follows symlinks out of it. Enabling the widget in the bar stays with the user
(`omarchy plugin enable io.github.arikisonfire.pod`).

**Settings** (`settings`): applied at activation by `nix/merge-settings.py` (run with the
package's Python) as a three-way merge, so Nix sets defaults and the UI can still change
them:

- It keeps `~/.config/omapod/.nix-settings.json`, holding what Nix applied last time.
- For each key in the new Nix settings: if `settings.json` lacks it, or still has the
  value Nix applied last time, it gets the new value; if the user changed it in the UI,
  the user's value stays.
- A key dropped from Nix whose file value is still the last-applied value is removed, so
  the app default applies again.
- Written like the app writes it: atomic replace, mode 0600, sorted JSON
  (`omapod/config.py:238-251`). A running app keeps these keys on its next save
  (`config.py:335-349`) and picks up new values on restart.
- An unreadable or non-object `settings.json` is left untouched and activation prints a
  warning: user data is never overwritten.
- `OMAPOD_HOME` is ignored, since activation targets the normal XDG paths only.

Refused at evaluation (assertion naming the key): `podcastindex_key`,
`podcastindex_secret`, `proxy.password`, `parental_password_hash`, `local_folders`
(grants read and delete), and app state: `last_page`, `window_*`, `sync_last_*`,
`history_repair`, `remote_downloads_*`, `mirror_downloads_ready`, `queue_sync_*`,
`favorites_sync_*`, `auto_db_export_last`, `stats_reset_ts`. Unknown keys are allowed:
the app ignores them, and new upstream keys work without a module change.

### nix/test.nix — VM test (x86_64-linux)

One `pkgs.testers.runNixOSTest` node: the NixOS module and Home Manager's NixOS module,
user `alice` with `linger = true`, Home Manager for alice with `refreshTimer`,
`widget`, `keybindings` (with one default removed and one added) and
`settings = { speed = 1.5; }`. Before Home Manager activates, alice's `settings.json` is
seeded with `{ "rewind_secs": 5 }` (activation ordering uses a oneshot unit before
`home-manager-alice.service`).

Assertions:

1. `/run/current-system/sw/share/applications/io.github.arikisonfire.OmaPod.desktop`
   exists and has the four schemes; `/etc/xdg/mimeapps.list` names it.
2. `omapod-binds.lua` has the four expected lines, lacks the removed one, contains no
   unquoted text.
3. `settings.json` has `speed = 1.5` and still `rewind_secs = 5`; mode 0600.
4. Change `speed` to 2.0 in the file, re-run activation: still 2.0 (UI value wins).
5. The widget dir has `manifest.json`, `plugin/BarWidget.qml`, `.nix-managed`, and no
   `omapod/`.
6. `systemctl --user is-enabled omapod-refresh.timer` for alice.
7. As alice: `OMAPOD_MPV_AO=null xvfb-run -a dbus-run-session -- omapod &`, then
   `wait_until_succeeds("omapod ctl state")` returns JSON, then `omapod ctl quit`. That
   proves GTK, libadwaita, the typelibs and the control socket work from the store.

### .github/workflows/nix.yml

- Triggers: `push`, `pull_request`, `workflow_dispatch`. `permissions: contents: read`.
  Actions pinned to commit SHAs.
- Job `check` on `ubuntu-latest`: checkout, enable KVM (udev rule giving
  `/dev/kvm` mode 0666), `cachix/install-nix-action`, `nix flake check -L`.
- Job `aarch64` on `ubuntu-24.04-arm` (the repo is public, so it is free): `nix build -L
  .#packages.aarch64-linux.default`, which runs the test suite there too.
- No binary cache of our own: dependencies come from cache.nixos.org; only omapod builds.

### README.md

New `## NixOS` section after `## Install`, linking out of the Arch section:

- flake input and `nix run`;
- NixOS module import and `programs.omapod.enable`;
- Home Manager import, a full example with every option, and the one `pcall(require, …)`
  line for `bindings.lua`;
- how settings precedence works, which keys are refused and why;
- update (`nix flake update omapod` and rebuild), remove (drop the import; the library in
  `~/.local/share/omapod` and `~/.config/omapod` stays);
- known limit: after an update the running app does not show "a newer version waits for a
  restart", because it reads its own store path (`omapod/ui/app.py:59-66`).

Also the `## Development` section gains `nix build` / `nix flake check`.

## Alternatives rejected

- **`buildPythonApplication`**: the repo has no `pyproject.toml`/`setup.py`; adding one
  changes upstream's layout. A plain derivation plus `makeWrapper` is smaller.
- **Running `install.sh` from Nix**: it writes `$HOME` imperatively and probes with
  `pacman` hints; nothing would be declarative or roll back.
- **Home Manager's Hyprland option only**: nixarchy's session never reads it.
- **Editing `bindings.lua`**: it is user-owned; every other tool here asks for one
  `pcall(require, …)` line instead.
- **`xdg.configFile` symlinks for `settings.json`**: makes it read-only; the app writes it
  constantly.
- **Nix values re-applied on every activation**: overwrites UI changes; rejected in the
  intent approval.
- **Typed option per app setting**: ~90 keys that drift from upstream.
- **Store symlink for the widget folder**: unknown whether the Omarchy shell follows it;
  a copy is what `install.sh` does and is known to work.
- **Writing the widget into `shell.json`**: decided against in the intent approval.

## Risks

- **Xvfb tests flaky in the Nix sandbox** (`test_tiling`, `test_dock`): if they are, the
  plan step falls back to running them in the VM test only, and the README and PR say so.
- **Activation and a running app writing `settings.json` at the same moment**: both do
  atomic replaces; the later one wins for the whole file, and the app's merge keeps other
  keys. Worst case, one Nix default is applied on the next activation instead. No data loss.
- **Key clashes on other machines**: `Super+Ctrl+Shift+K/O/N/,/.` are free here and in
  Omarchy's defaults as printed; other users' own binds can clash. Each key can be changed
  or set to `null`.
- **`uwsm-app` missing outside Omarchy**: the widget only exists inside the Omarchy shell,
  which has it.
- **aarch64 runner**: if `ubuntu-24.04-arm` is unavailable, that job fails visibly; the
  x86_64 job is unaffected.
- **Hosts**: nothing is built or switched on p510 or any machine; all builds run locally
  under `nix build` or in GitHub Actions.

## Verification

- `nix flake check -L` locally on x86_64: the package builds, the suite passes
  (skips listed with reasons, only `test_install` expected), and the VM test passes.
- `nix build .#packages.aarch64-linux.default` in CI.
- `nix run . -- --version` prints `omaPOD 0.1.5`.
- The GitHub Actions run on the PR is green for both jobs.
- README example evaluated: the full Home Manager example is the one the VM test uses.
