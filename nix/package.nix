{
  lib,
  stdenv,
  python3,
  wrapGAppsHook4,
  gobject-introspection,
  makeWrapper,
  gtk4,
  libadwaita,
  gdk-pixbuf,
  pango,
  graphene,
  glib,
  mpv,
  xdg-utils,
  openssl,
  xvfb-run,
  dbus,
}:

let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
  appId = "io.github.arikisonfire.OmaPod";
in
stdenv.mkDerivation {
  pname = "omapod";
  version = builtins.head (
    builtins.match ''.*VERSION = "([^"]+)".*'' (builtins.readFile ../omapod/__init__.py)
  );

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../omapod
      ../tests
      ../nix/run-tests.py
      ../plugin
      ../data
      ../manifest.json
      ../README.md
      ../install.sh
      ../LICENSE
    ];
  };

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
    makeWrapper
  ];
  buildInputs = [
    gtk4
    libadwaita
    gdk-pixbuf
    pango
    graphene
    glib
  ];

  dontBuild = true;
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/omapod/widget/plugin $out/share/applications \
      $out/share/icons/hicolor/scalable/apps
    cp -r omapod $out/share/omapod/omapod
    find $out/share/omapod -name __pycache__ -type d -prune -exec rm -rf {} +
    cp manifest.json LICENSE $out/share/omapod/widget/
    cp plugin/BarWidget.qml $out/share/omapod/widget/plugin/
    substitute data/${appId}.desktop.in $out/share/applications/${appId}.desktop \
      --replace-fail @BIN@ $out/bin/omapod
    cp data/${appId}.svg $out/share/icons/hicolor/scalable/apps/
    runHook postInstall
  '';

  postFixup = ''
    makeWrapper ${python}/bin/python3 $out/bin/omapod \
      --add-flags "-P -m omapod" \
      --prefix PYTHONPATH : $out/share/omapod \
      --suffix PATH : ${
        lib.makeBinPath [
          mpv
          xdg-utils
        ]
      } \
      "''${gappsWrapperArgs[@]}"
    mkdir -p $out/libexec
    makeWrapper ${python}/bin/python3 $out/libexec/omapod-python \
      --suffix PATH : ${
        lib.makeBinPath [
          mpv
          xdg-utils
        ]
      } \
      "''${gappsWrapperArgs[@]}"
  '';

  doCheck = true;
  nativeCheckInputs = [
    python
    mpv
    openssl
    xvfb-run
    dbus
  ];
  checkPhase = ''
    runHook preCheck
    export HOME=$TMPDIR OMAPOD_MPV_AO=null
    # the sandbox has no /etc/dbus-1/session.conf; tests/test_tiling.py starts its own dbus-run-session
    mkdir -p $TMPDIR/bin
    printf '#!/bin/sh\nexec ${dbus}/bin/dbus-run-session --config-file=${dbus}/share/dbus-1/session.conf "$@"\n' > $TMPDIR/bin/dbus-run-session
    chmod +x $TMPDIR/bin/dbus-run-session
    export PATH=$TMPDIR/bin:$PATH
    xvfb-run -a dbus-run-session -- ${python.interpreter} -B nix/run-tests.py
    runHook postCheck
  '';

  meta = {
    description = "Podcast player for Omarchy, in sync with AntennaPod";
    license = lib.licenses.gpl3Plus;
    mainProgram = "omapod";
    platforms = lib.platforms.linux;
    homepage = "https://github.com/arikisonfire/omapod";
  };
}
