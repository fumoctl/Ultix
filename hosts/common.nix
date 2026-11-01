{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.noctalia.nixosModules.default
  ];

  # --- Nix & System Basics ---
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
    auto-optimise-store = lib.mkDefault true;
    substituters = [
      "https://cache.nixos.org"
      "https://noctalia.cachix.org"
      "https://nyx-cache.chaotic.cx"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
    ];
  };

  nixpkgs.config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
  };
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        system = prev.stdenv.hostPlatform.system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
    })
    inputs.lsfg-vk.overlays.default
    inputs.antigravity-nix.overlays.default
  ];

  boot = {
    loader = {
      limine.enable = lib.mkDefault true;
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };

    kernelModules = [ "ntsync" ];

    kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 8192;
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };

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
    ];
    files = [
      "/etc/machine-id"
      "/etc/ly/save.txt"
    ];
    users.fumoctl = {
      directories = [
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
        ".config/BraveSoftware"
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
        ".local/share/Steam"
        ".local/share/containers"
        ".local/share/direnv"
        ".local/share/flatpak"
        ".local/share/keyrings"
        ".local/share/Trash"
        ".local/share/uv"
        ".local/state/noctalia"
        ".local/bin"
        ".cache/bun"
        ".cache/uv"
        ".cache/ms-playwright"
        ".var/app"
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
      ];
    };
  };

  fileSystems = {
    "/persist".neededForBoot = true;
    "/nix".neededForBoot = true;
    "/var/log".neededForBoot = true;
  };

  # System Limits & Systemd Tweaks
  systemd.settings.Manager.DefaultLimitNOFILE = "1048576";
  systemd.user.extraConfig = ''
    DefaultLimitNOFILE=1048576
    DefaultDelegate=yes
  '';
  systemd.package = pkgs.systemd.override { withUserDb = false; };
  services.userdbd.enable = lib.mkForce false;

  security = {
    rtkit.enable = true;
    polkit.enable = true;
    sudo.extraConfig = "Defaults lecture=never";
    pam.loginLimits = [
      {
        domain = "*";
        type = "-";
        item = "nofile";
        value = "1048576";
      }
    ];
  };

  # GNOME Keyring: secret service (libsecret) + PKCS#11, DBus-activated and
  # started per-user by Home Manager. The NixOS module auto-unlocks via the
  # `login` PAM service; SDDM is the actual entry point here, so it needs its
  # own PAM hook. SSH component is intentionally NOT enabled (HM side):
  # gpg-agent already provides the SSH agent via programs.gnupg.agent.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.ly.enableGnomeKeyring = true;

  services.tzupdate.enable = true;
  time.timeZone = lib.mkDefault "America/Argentina/Buenos_Aires";

  i18n = {
    defaultLocale = lib.mkDefault "en_US.UTF-8";
    extraLocales = [
      "ja_JP.UTF-8/UTF-8"
      "es_AR.UTF-8/UTF-8"
      "es_ES.UTF-8/UTF-8"
    ];
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "altgr-intl";
  };

  fonts = {
    fontDir.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      nerd-fonts.ubuntu-mono
      nerd-fonts.ubuntu
      nerd-fonts.hack
      nerd-fonts.fira-code
      nerd-fonts.inconsolata
      inconsolata
      inconsolata-lgc
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      ipafont
      kochi-substitute
      noto-fonts-color-emoji
      liberation_ttf
    ];

    fontconfig.defaultFonts = {
      monospace = [
        "JetBrainsMono Nerd Font"
        "Noto Sans Mono CJK JP"
      ];
      sansSerif = [
        "Noto Sans CJK JP"
        "Liberation Sans"
      ];
      serif = [
        "Noto Serif CJK JP"
        "Liberation Serif"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  # --- Desktop Subsystem (Hyprland & Noctalia) ---
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  xdg.portal = {
    enable = true;
    wlr.enable = false;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common = {
        default = [ "gtk" ];
      };
      # NOTE: this per-DE section overrides `common` for ALL interfaces when
      # XDG_CURRENT_DESKTOP=Hyprland. The hyprland backend only implements
      # Screenshot/ScreenCast/GlobalShortcuts, so "gtk" must stay in the list
      # or org.freedesktop.portal.Settings disappears from the portal broker
      # and libadwaita apps (Ptyxis etc.) always see light mode.
      hyprland = {
        default = [
          "hyprland"
          "gtk"
        ];
      };
    };
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    GDK_BACKEND = "wayland,x11,*";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
    DICPATH = "/run/current-system/sw/share/hunspell";
  };

  services.displayManager = {
    ly = {
      enable = true;
    };
    defaultSession = "hyprland-uwsm";
  };

  # --- Hardware & Input Integrations ---
  networking = {
    nftables.enable = true;

    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      settings = {
        main = {
          dns = "systemd-resolved";
        };
        connection = {
          "ipv4.ignore-auto-dns" = true;
          "ipv6.ignore-auto-dns" = true;

          "wifi.cloned-mac-address" = "stable-temporary";
          "ethernet.cloned-mac-address" = "stable-temporary";

          "ipv6.ip6-privacy" = 2;
        };
        device = {
          "wifi.scan-rand-mac-address" = "yes";
        };
      };
    };

    firewall = {
      enable = true;
      checkReversePath = "loose";
      trustedInterfaces = [
        "tun0"
        "tun2"
        "amn0"
      ];
    };
  };

  services.unbound.enable = false;

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSSEC = "true";
        DNSOverTLS = "true";
        DNS = [
          "94.140.14.14#dns.adguard-dns.com"
          "94.140.15.15#dns.adguard-dns.com"
          "2a10:50c0::ad1:ff#dns.adguard-dns.com"
          "2a10:50c0::ad2:ff#dns.adguard-dns.com"
        ];
        FallbackDNS = [
          "9.9.9.9#dns.quad9.net"
          "149.112.112.112#dns.quad9.net"
          "2620:fe::fe#dns.quad9.net"
          "2620:fe::9#dns.quad9.net"

          "194.242.2.4#base.dns.mullvad.net"
          "2a07:e340::4#base.dns.mullvad.net"
        ];
        Domains = [ "~." ];
      };
    };
  };

  programs.amnezia-vpn = {
    enable = true;
    package = pkgs.unstable.amnezia-vpn;
  };

  hardware.bluetooth = {
    enable = lib.mkDefault true;
    powerOnBoot = true;
  };
  services.upower.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkDefault true;
  services.lact.enable = true;
  services.libinput = {
    enable = true;
    mouse = {
      accelProfile = "flat";
    };
  };

  # --- Graphics & Gaming Subsystem ---
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = [

    ];
  };
  services.xserver.enable = true;

  programs.gamemode.enable = true;
  programs.gamescope.enable = true;
  programs.steam = {
    enable = true;
    extest.enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [
      proton-cachyos
      proton-ge-custom
    ];
  };
  hardware.steam-hardware.enable = true;

  # --- Virtualisation & Flatpak (containers live in containers.nix) ---
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        vhostUserPackages = with pkgs; [
          virtiofsd
        ];
      };
    };
  };

  programs.virt-manager.enable = true;
  services.spice-vdagentd.enable = true;

  services.flatpak = {
    enable = true;
    uninstallUnmanaged = false;
  };

  # --- File Management, Integration & Thumbnailers ---
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };
  programs.xfconf.enable = true;

  # --- System Utilities & Developer Tooling ---
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-all;
  };

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Core C/C++ runtimes & compilers
      stdenv.cc.cc.lib
      gcc.cc.lib
      glibc
      zlib
      systemd
      ncurses5

      # Compression, system, and network utilities
      bzip2
      curl
      expat
      libxml2
      openssl
      util-linux
      e2fsprogs

      # Graphics & hardware rendering (host GPU / Vulkan / Direct Rendering)
      libGL
      libglvnd
      vulkan-loader
      mesa
      libdrm
      libva
      pciutils
      libepoxy

      # Image codecs (prevents emulator QEMU crashes)
      libpng
      libjpeg
      libwebp

      # BSD compatibility
      libbsd

      # Audio output (needed for emulator guest sound)
      alsa-lib
      pulseaudio
      libpulseaudio

      # X11 Session Management & Core X11 client libraries
      libsm
      libice
      libx11
      libxcb
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxinerama
      libxrandr
      libxrender
      libxtst
      libxshmfence

      # Qt 6.5+ XCB utility plugins (resolves GUI startup aborts)
      libxcb-cursor
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-wm

      # Keyboard & Wayland handling (needed by Qt and Flutter)
      libxkbcommon
      libxkbfile
      wayland

      # Desktop integration, GTK3 & font rendering (required for Flutter engine)
      gtk3
      glib
      cairo
      pango
      atk
      gdk-pixbuf
      harfbuzz
      fontconfig
      freetype
      nspr
      nss
      dbus
      cups
    ];
  };

  documentation.man.cache.enable = true;

  environment.systemPackages = with pkgs; [
    # Development & Editors
    nixd
    nixfmt
    inputs.nix-alien.packages.${pkgs.stdenv.hostPlatform.system}.nix-alien
    neovim
    git
    meld
    distrobox
    python3
    google-antigravity
    google-antigravity-cli

    # File Management & Media Openers
    xarchiver
    icoextract
    kdePackages.gwenview
    lollypop
    kdePackages.okular
    zip
    unzip
    kdePackages.ark

    # System & CLI Utilities
    fastfetch
    file
    jq
    pciutils
    ethtool
    sbctl
    _7zz
    unrar
    sshfs
    wget
    curl
    tree
    ripgrep
    fd
    btrfs-progs
    libsecret
    seahorse

    # Wayland & Desktop Integration
    wl-clipboard
    wl-mirror
    grim
    slurp
    brightnessctl
    playerctl
    wireplumber
    libnotify
    bibata-cursors

    # Gaming & Performance
    lact
    mangohud
    goverlay
    mesa-demos
    lsfg-vk

    # Productivity & Daily Applications
    unstable.equibop
    thunderbird
    hunspell
    hunspellDicts.en_US
    hunspellDicts.es_AR
    unstable.onlyoffice-desktopeditors
    unstable.mullvad-browser
    mpv
    appimage-run

    # Network Utilities
    dnsmasq
    sshuttle
    waypipe
    iptables
    iproute2

    # Fun & Miscellaneous
    unstable.renpy
    unstable.cowsay
    unstable.lolcat
    unstable.haskellPackages.misfortune
  ];

  # --- User Declaration & Home Manager Integration ---
  programs.zsh.enable = true;

  users.mutableUsers = false;
  users.groups.fumoctl = { };
  users.users.fumoctl = {
    isNormalUser = true;
    hashedPasswordFile = "/persist/passwords/fumoctl";
    description = "JuanU";
    group = "fumoctl";
    extraGroups = [
      "wheel"
      "users"
      "networkmanager"
      "video"
      "audio"
      "input"
      "kvm"
      "adbusers"
      "libvirtd"
      "adm"
      "docker"
      "podman"
    ];
    shell = pkgs.zsh;
    linger = true;
    autoSubUidGidRange = true;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.fumoctl = import ../home;
    backupFileExtension = "backup";
  };

  system.stateVersion = "26.05";
}
