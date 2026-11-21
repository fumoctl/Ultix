{
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  services.flatpak = {
    enable = true;
    packages = [
      "com.github.tchx84.Flatseal"
      "com.obsproject.Studio"
      "com.github.Matoking.protontricks"
      "com.ranfdev.DistroShelf"
      "it.mijorus.gearlever"
      "org.qbittorrent.qBittorrent"
    ];
    update.auto = {
      enable = true;
      onCalendar = "daily";
    };
    uninstallUnmanaged = false;

    # Declarative Flatpak overrides (replaces imperative `flatpak override` hooks)
    overrides = {
      global = {
        Context.filesystems = [
          "/nix/store:ro"
          "xdg-config/gtk-3.0:ro"
          "xdg-config/gtk-4.0:ro"
          "xdg-data/icons:ro"
          "xdg-data/themes:ro"
        ];
      };
      "com.obsproject.Studio" = {
        Context.unset-environment = [
          "QT_PLUGIN_PATH"
          "LD_LIBRARY_PATH"
          "QT_QPA_PLATFORM_PLUGIN_PATH"
        ];
      };
      "org.qbittorrent.qBittorrent" = {
        Context.unset-environment = [
          "QT_PLUGIN_PATH"
          "LD_LIBRARY_PATH"
          "QT_QPA_PLATFORM_PLUGIN_PATH"
        ];
      };
    };
  };

  # Flatpak repo language filter lives in ~/.local/share/flatpak/repo/config
  # (not covered by overrides INI files).
  home.activation.configureFlatpakLanguages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${lib.getExe pkgs.flatpak} config --user --set languages "en;ja;es"
  '';

  # Gear Lever has no dconf D-Bus permission in its Flathub manifest, so GLib
  # stores GSettings in a mutable 0600 keyfile that the app rewrites at runtime.
  home.activation.configureGearLeverDir =
    let
      configureGearLever = pkgs.writeText "configure-gearlever-dir.py" ''
        import configparser
        import os
        import pathlib
        import sys
        import tempfile

        path = (
            pathlib.Path(os.environ["HOME"])
            / ".var/app/it.mijorus.gearlever/config/glib-2.0/settings/keyfile"
        )
        if path.is_symlink() or (path.exists() and not path.is_file()):
            print(
                f"configureGearLeverDir: refusing to modify non-regular file {path}",
                file=sys.stderr,
            )
            raise SystemExit(1)

        cfg = configparser.ConfigParser(interpolation=None)
        cfg.optionxform = str
        if path.is_file():
            try:
                with path.open("r", encoding="utf-8") as f:
                    cfg.read_file(f)
            except (configparser.Error, OSError, UnicodeDecodeError) as e:
                print(
                    f"configureGearLeverDir: failed to parse {path}: {e}",
                    file=sys.stderr,
                )
                raise SystemExit(1)

        section = "it/mijorus/gearlever"
        key = "appimages-default-folder"
        target = "'~/Applications'"
        if cfg.get(section, key, fallback=None) == target:
            raise SystemExit(0)

        if not cfg.has_section(section):
            cfg.add_section(section)
        cfg.set(section, key, target)

        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=".keyfile.tmp.")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                os.fchmod(f.fileno(), 0o600)
                cfg.write(f, space_around_delimiters=False)
            os.replace(tmp_name, path)
        except BaseException:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
            raise
      '';
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.getExe pkgs.python3} ${configureGearLever}
    '';
}
