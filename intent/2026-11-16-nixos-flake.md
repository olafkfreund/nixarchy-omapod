---
status: approved
issue: none (issues are disabled on olafkfreund/nixarchy-omapod; see open question 1)
author: olafkfreund
---

# Intent: Install omaPOD on NixOS with a flake

## Problem

omaPOD installs only the Arch/Omarchy way: `omarchy plugin add`, or `install.sh`, which
probes for the Python GI modules and `mpv` (suggesting `pacman` names when they are
missing), copies or symlinks the code into `~/.local/share/omapod-app`, writes a launcher
script, a desktop entry (URL schemes and OPML files), an icon, `x-scheme-handler` defaults
in `mimeapps.list`, an optional `omapod-refresh` systemd user timer (`--refresh` refreshes,
auto-downloads and syncs, or asks a running app to), and an optional copy of the bar widget
in `~/.config/omarchy/plugins/io.github.arikisonfire.pod`.

On NixOS (and nixarchy, Omarchy on NixOS) none of that is declarative:

- There is no package. The app needs Python with PyGObject and the GTK 4, libadwaita,
  GdkPixbuf, Pango and Graphene typelibs, plus `mpv` on `PATH`; on NixOS that has to be
  wrapped, or it fails at `gi.require_version`.
- The installer writes into `$HOME` imperatively, so a rebuild does not reproduce it and a
  rollback does not undo it.
- Nothing binds global keys to the existing `omapod ctl …` commands (toggle, rewind,
  forward, skip, speed, sleep, show), so playback control from Hyprland is manual.
- The bar widget's settings (`showTitle`, `maxTitleWidth`, `hideWhenStopped`,
  `launchCommand`, `socketPath`) and the app's ~90 settings in `settings.json` cannot be
  set from Nix.
- The bar widget assumes an Arch layout: by default it runs `uwsm-app -- omapod`, and if
  it finds `omapod/__main__.py` beside itself it runs bare `python3 -m omapod`
  (`plugin/BarWidget.qml:139-143`, `:231-239`). On NixOS bare `python3` has no `gi`, so a
  widget shipped next to the source would fail to start the app.
- The app re-executes itself after a database import with `sys.executable -P -m omapod`
  (`omapod/__main__.py:194-209`), bypassing any launcher; a Nix wrapper must survive that.
- App, widget, CLI and timer must agree on the runtime dir and control socket
  (`XDG_RUNTIME_DIR`, `OMAPOD_HOME`, `OMAPOD_RUNTIME_DIR`; `omapod/config.py:27-100`), or
  the timer and widget talk to a different library or no app at all.
- There is no CI (no `.github/` in the repo): the unit tests
  (`python3 -B -m unittest discover -s tests -t .`) run only when someone remembers to.
  `tests/test_install.py:38` replaces `PATH` with `/usr/bin:/bin`, so it does not run as-is
  inside a Nix build, and test classes skip silently when prerequisites are missing.
- The README documents only the Arch path.

## Proposed outcome

- `nix run github:olafkfreund/nixarchy-omapod` starts omaPOD on a NixOS desktop with no
  other setup.
- A NixOS user adds the flake as an input, imports a module, sets one `enable = true`, and
  after a rebuild has: the `omapod` command, a launcher entry with the icon, OPML files and
  `podcast://`, `itpc://`, `pcast://` and `antennapod-subscribe://` links opening omaPOD
  (unless the user chose another app for them), media keys via MPRIS, and optionally the
  hourly refresh timer and a bar widget that starts the packaged app.
- Every user-facing knob is an option: the refresh timer, the bar widget and its five
  settings, the URL handlers, Hyprland keybindings for each `omapod ctl` action (with
  sensible defaults that can be changed or turned off), and the app's preferences. App
  state (sync cursors, window size, last page) and anything secret stay app-owned.
- A GitHub Actions workflow proves on every push and pull request that the package
  builds, the unit tests pass inside the Nix build, and a NixOS VM with the module enabled
  can start the GUI on a headless display with D-Bus and null audio, answer
  `omapod ctl state`, and has the timer and desktop entry in place. (`--version` alone
  proves nothing: it returns before GTK is imported.) Skipped tests are reported, not
  hidden.
- The README has a NixOS section: flake input, module import, an example with every
  option, and how to update and remove.

## Affected users and systems

- NixOS and nixarchy users of omaPOD (new path); Arch/Omarchy users are unaffected.
- New files: `flake.nix`, `flake.lock`, a Nix package expression, NixOS and/or
  Home Manager module(s), a VM test, `.github/workflows/*.yml`.
- Changed: `README.md`. Possibly `omapod` or `tests/` only if packaging needs it.
- Upstream is `arikisonfire/omapod`; this repo is a fork. The flake should not make
  upstream merges painful.
- No host deploys: nothing here is built on p510 or switched on any machine.

## Constraints

- Must not change app behaviour or the Arch install path (`install.sh`, `manifest.json`,
  marketplace layout). Narrow fixes the Nix package strictly needs (e.g. making a test
  portable) are allowed and named in the spec.
- Must not make `~/.config/omapod/settings.json` read-only: the app writes it at runtime
  (window size, last page, sync state). Nix-managed settings must be merged in, not
  symlinked over.
- Must not write `credentials.json` or any secret into the Nix store; secrets stay in the
  app (or a file path option pointing outside the store). Settings that once held secrets
  (proxy password, Podcast Index key; `omapod/config.py:397-411`) and `local_folders`,
  which grants read and delete access to folders, are not plain preferences.
- Must not lose data on activation, removal or rollback: the library, database and
  user-edited settings survive all three.
- Must not overwrite a user's own choice of app for the podcast URL schemes, matching
  `install.sh`.
- Writing into `~/.config/omarchy/plugins/` makes the Omarchy shell reload every plugin;
  the widget must be installed only when asked for. If a marketplace clone of the widget
  already exists (it has `.git`), Nix must not replace it, as `install.sh:168-172` does not.
- Keybindings must not silently clash with Omarchy/nixarchy defaults; they must be
  overridable and disable-able.
- The tiling test needs `xvfb-run` and `dbus-run-session`; CI either provides them or the
  test stays skipped, said so plainly.
- License stays GPL-3.0-or-later; package meta says so.

## Not verified yet

GitHub runner KVM availability, nixarchy's keybinding format and existing default binds,
and the complete typelib list (locale files and `version_on_disk` update detection still
need checking under a store path).

## Open questions

1. **Issue number.** Issues are disabled on `olafkfreund/nixarchy-omapod`, so this slug
   has no issue. Enable issues and open one, or proceed without?
2. **Module shape.** Per-user things (keybindings, widget, settings, user timer, MIME
   defaults) fit Home Manager best; a NixOS module can add the package, desktop entry,
   icon and a `systemd.user` timer system-wide. Ship both (NixOS module for install,
   Home Manager module for per-user config), or NixOS only?
3. **Keybindings target.** Bind through Home Manager's
   `wayland.windowManager.hyprland.settings.bind`, or write a nixarchy/Omarchy
   `bindings.lua` snippet (nixarchy shares `~/.config/hypr/bindings.lua` between
   sessions)? And which default keys — e.g. Super+Alt+P toggle, Super+Alt+[ / ] rewind and
   forward, Super+Alt+N skip, Super+Alt+O show — or no defaults, off until set?
4. **App settings scope and precedence.** Expose a free-form `settings` attrset merged into
   `settings.json` (covers every key, stays in sync with upstream, but can carry state or
   secrets), or typed options for the preferences only (better docs, drifts from
   upstream)? And what wins: Nix values as first-run defaults the UI may change, or
   re-applied on every activation (overwriting UI edits)?
5. **Widget registration.** Should enabling the Nix widget also add it to the bar in
   `~/.config/omarchy/shell.json`, or only install it and leave
   `omarchy plugin enable` to the user, as `install.sh` does?
6. **Support scope.** x86_64-linux only, or aarch64-linux too? Which NixOS release(s):
   unstable, 25.11, both?
7. **CI runner.** NixOS VM tests need KVM; GitHub-hosted `ubuntu-latest` has it. Use
   `nix flake check` there with a binary cache, or only build and unit-test in CI and keep
   the VM test local?
