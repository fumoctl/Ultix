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
      "com.usebottles.bottles"
      "com.vysp3r.ProtonPlus"
      "com.github.Matoking.protontricks"
      "com.ranfdev.DistroShelf"
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
      "com.usebottles.bottles" = {
        Context.filesystems = [ "home" ];
      };
      "com.obsproject.Studio" = {
        Context.unset-environment = [
          "QT_PLUGIN_PATH"
          "LD_LIBRARY_PATH"
          "QT_QPA_PLATFORM_PLUGIN_PATH"
        ];
        Environment = {
          QT_PLUGIN_PATH = "";
          LD_LIBRARY_PATH = "";
          QT_QPA_PLATFORM_PLUGIN_PATH = "";
        };
      };
    };
  };

  # Flatpak repo language filter lives in ~/.local/share/flatpak/repo/config
  # (not covered by overrides INI files).
  home.activation.configureFlatpakLanguages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${lib.getExe pkgs.flatpak} config --user --set languages "en;ja;es"
  '';
}
