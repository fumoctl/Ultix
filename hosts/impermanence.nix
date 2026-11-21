{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  # Recreate the root subvolume from scratch before the normal root mount.
  boot.initrd.systemd.initrdBin = with pkgs; [
    btrfs-progs
    coreutils
    util-linux
  ];

  boot.initrd.systemd.services.impermanence-clean-root = {
    description = "Recreate the ephemeral Btrfs root subvolume";
    wantedBy = [ "initrd.target" ];
    requires = [ "dev-mapper-crypted.device" ];
    after = [ "dev-mapper-crypted.device" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      set -e
      mkdir -p /btrfs_tmp
      trap 'if mountpoint -q /btrfs_tmp; then umount /btrfs_tmp; fi' EXIT
      mountpoint -q /btrfs_tmp || mount -t btrfs -o subvolid=5 /dev/mapper/crypted /btrfs_tmp

      if [ -e /btrfs_tmp/@ ]; then
        btrfs subvolume list -r /btrfs_tmp | while IFS= read -r line; do
          subvol="''${line#* path }"
          case "$subvol" in
            @ | @/*) btrfs property set -ts "/btrfs_tmp/$subvol" ro false ;;
          esac
        done
        btrfs subvolume delete -R /btrfs_tmp/@
      fi

      btrfs subvolume create /btrfs_tmp/@
      umount /btrfs_tmp
    '';
  };

  fileSystems = {
    "/persist".neededForBoot = true;
    "/nix".neededForBoot = true;
    "/var/log".neededForBoot = true;
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    allowTrash = true;

    directories = [
      "/etc/NetworkManager/system-connections"
      "/etc/lact"
      "/var/lib/AccountsService"
      "/var/lib/NetworkManager"
      "/var/lib/bluetooth"
      "/var/lib/containers"
      "/var/lib/docker"
      "/var/lib/flatpak"
      "/var/lib/libvirt"
      "/var/lib/nixos"
      "/var/lib/power-profiles-daemon"
      "/var/lib/systemd"
      "/var/lib/sbctl"
      "/var/lib/upower"
      {
        directory = "/var/lib/noctalia-greeter";
        user = "greeter";
        group = "greeter";
        mode = "0750";
      }
    ];

    files = [
      "/etc/machine-id"
    ];

    users.root.directories = [
      ".local/share/nix"
    ];

    users.fumoctl = {
      directories = [
        # XDG & user directories
        "Desktop"
        "Applications"
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Public"
        "Templates"
        "Videos"
        "Projects"
        "Games"

        # Application config (~/.config)
        ".config/BraveSoftware"
        ".config/VSCodium"
        ".config/discord"
        ".config/dconf"
        ".config/gh"
        ".config/gcloud"
        ".config/containers"
        ".config/Antigravity"
        ".config/antigravity"
        ".config/MangoHud"
        ".config/AmneziaVPN.ORG"
        ".config/Podman Desktop"
        ".config/.android"
        ".config/Windscribe"
        ".config/onlyoffice"
        ".config/betterstremio"

        # Application data & state (~/.local)
        ".local/share/Steam"
        ".local/share/bottles"
        ".local/share/umu"
        ".local/share/containers"
        ".local/share/direnv"
        ".local/share/flatpak"
        ".local/share/applications"
        ".local/share/betterstremio"
        ".local/share/keyrings"
        ".local/share/Trash"
        ".local/share/dolphin"
        ".local/share/elisa"
        ".local/share/konsole"
        ".local/share/kxmlgui5"
        ".local/share/onlyoffice"
        ".local/share/Windscribe"
        ".local/share/nix"
        ".local/share/uv"
        ".local/state/noctalia"
        ".local/state/portal-screen-mirror"
        ".local/state/wireplumber"
        ".local/state/zsh"
        ".local/bin"

        # Caches & Flatpak user state
        ".cache/bun"
        ".cache/uv"
        ".cache/ms-playwright"
        ".cache/winetricks"
        ".var/app"

        # Editors, agents, mail, gaming & toolchains
        ".vscode-oss"
        ".duckdb"
        ".agents"
        ".steam"
        ".stremio-server"
        ".gemini"
        ".m2"
        ".gradle"
        ".android"
        ".bun"
        ".npm"
        ".cargo"
        ".rustup"

        # Credential directories
        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
      ];

      files = [
        {
          file = ".config/dolphinrc";
          method = "symlink";
        }
        {
          file = ".local/state/dolphinstaterc";
          method = "symlink";
        }
        {
          file = ".config/elisarc";
          method = "symlink";
        }
        {
          file = ".local/state/elisastaterc";
          method = "symlink";
        }
        {
          file = ".config/konsolerc";
          method = "symlink";
        }
        {
          file = ".local/state/konsolestaterc";
          method = "symlink";
        }
        {
          file = ".config/xdg-desktop-portal-kderc";
          method = "symlink";
        }
        {
          file = ".local/state/xdg-desktop-portal-kdestaterc";
          method = "symlink";
        }
      ];
    };
  };

  # Qt's QSaveFile (used by KConfig) refuses to follow dangling symlinks;
  # pre-creating empty target files in /persist lets KDE apps save cleanly.
  systemd.tmpfiles.rules = [
    "f /persist/home/fumoctl/.config/dolphinrc 0600 fumoctl fumoctl -"
    "f /persist/home/fumoctl/.local/state/dolphinstaterc 0600 fumoctl fumoctl -"
    "f /persist/home/fumoctl/.config/elisarc 0600 fumoctl fumoctl -"
    "f /persist/home/fumoctl/.local/state/elisastaterc 0600 fumoctl fumoctl -"
    "f /persist/home/fumoctl/.config/konsolerc 0600 fumoctl fumoctl -"
    "f /persist/home/fumoctl/.local/state/konsolestaterc 0600 fumoctl fumoctl -"
    "f /persist/home/fumoctl/.config/xdg-desktop-portal-kderc 0600 fumoctl fumoctl -"
    "f /persist/home/fumoctl/.local/state/xdg-desktop-portal-kdestaterc 0600 fumoctl fumoctl -"
  ];
}
