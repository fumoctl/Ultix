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
    gnused
    util-linux
  ];

  boot.initrd.systemd.services.impermanence-clean-root = {
    description = "Recreate the ephemeral Btrfs root subvolume";
    wantedBy = [ "initrd.target" ];
    after = [ "dev-mapper-crypted.device" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      set -e
      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvolid=5 /dev/mapper/crypted /btrfs_tmp

      if [ -e /btrfs_tmp/@ ]; then
        btrfs subvolume list -o /btrfs_tmp/@ \
          | sed -n 's/^.* path //p' \
          | sort -r \
          | while IFS= read -r subvolume; do
              btrfs subvolume delete "/btrfs_tmp/$subvolume"
            done
        btrfs subvolume delete /btrfs_tmp/@
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
      "/var/lib/AccountsService"
      "/var/lib/NetworkManager"
      "/var/lib/bluetooth"
      "/var/lib/containers"
      "/var/lib/docker"
      "/var/lib/flatpak"
      "/var/lib/libvirt"
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/lib/sbctl"
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
        ".config/vivaldi"
        ".config/Code"
        ".config/VSCodium"
        ".config/equibop"
        ".config/dconf"
        ".config/gh"
        ".config/lsfg-vk"
        ".config/containers"
        ".config/Antigravity"
        ".config/MangoHud"
        ".config/xfce4"
        ".config/AmneziaVPN.ORG"
        ".config/Podman Desktop"
        ".config/.android"
        ".config/Windscribe"

        # Application data & state (~/.local)
        ".local/share/Steam"
        ".local/share/containers"
        ".local/share/direnv"
        ".local/share/flatpak"
        ".local/share/keyrings"
        ".local/share/Trash"
        ".local/share/dolphin"
        ".local/share/elisa"
        ".local/share/konsole"
        ".local/share/kxmlgui5"
        ".local/share/Windscribe"
        ".local/share/nix"
        ".local/share/uv"
        ".local/state/noctalia"
        ".local/state/wireplumber"
        ".local/bin"

        # Caches & Flatpak user state
        ".cache/bun"
        ".cache/uv"
        ".cache/ms-playwright"
        ".var/app"

        # Editors, agents, mail, gaming & toolchains
        ".thunderbird"
        ".vscode"
        ".vscode-oss"
        ".vscode-shared"
        ".vscode-oss-shared"
        ".duckdb"
        ".agents"
        ".steam"
        ".gemini"
        ".m2"
        ".gradle"
        ".android"
        ".bun"
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
        ".config/zsh/.zsh_history"
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
