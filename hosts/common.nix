{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./impermanence.nix
    ./networking.nix
    ./desktop-env.nix
    ./gaming.nix
    ./packages.nix
  ];

  # --- Nix & Overlays ---
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
      "https://umbriel.cachix.org"
      "https://nyx-cache.chaotic.cx"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "umbriel.cachix.org-1:JfNq/2yg2S6D6z4Z2dVSZrZlDPQTKtexB6GAVLD98nw="
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
    ];
  };

  programs.nh = {
    enable = true;
    flake = "/home/fumoctl/Projects/Ultix";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 15 --keep-since 14d --no-direnv";
    };
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

  # --- Bootloader & Kernel Sysctl ---
  boot = {
    loader = {
      limine = {
        enable = lib.mkDefault true;
        maxGenerations = lib.mkDefault 15;
      };
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };

    kernelModules = [ "ntsync" ];

    kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
      "kernel.split_lock_mitigate" = 0;
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 8192;
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };

  # --- System Limits, Systemd & Security ---
  systemd.settings.Manager.DefaultLimitNOFILE = "1048576";
  systemd.user.extraConfig = ''
    DefaultLimitNOFILE=1048576
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

  # --- Locale & Time ---
  services.tzupdate.enable = true;
  systemd.services.tzupdate = lib.mkIf config.services.tzupdate.enable {
    wantedBy = lib.mkForce [ ];
    after = [ "NetworkManager-wait-online.service" ];
    wants = [ "NetworkManager-wait-online.service" ];
    serviceConfig.SuccessExitStatus = 1;
    postStart = ''
      if [ -L /etc/localtime ]; then
        mkdir -p /persist/etc
        cp -Pf /etc/localtime /persist/etc/localtime
      fi
    '';
  };
  networking.networkmanager.dispatcherScripts = lib.mkIf config.services.tzupdate.enable [
    {
      source = pkgs.writeShellScript "tzupdate" ''
        if [ "$2" = "up" ] && [ "$1" != "lo" ] && [ "''${CONNECTION_EXTERNAL:-0}" != "1" ]; then
          ${config.systemd.package}/bin/systemctl start --no-block tzupdate.service
        fi
      '';
    }
  ];
  # Seed /etc/localtime on ephemeral boots without symlinking into /persist
  # (systemd-timedated unlinks /etc/localtime on timedatectl set-timezone).
  system.activationScripts.localtime = lib.stringAfter [ "etc" ] ''
    if [ ! -e /etc/localtime ]; then
      if [ -L /persist/etc/localtime ] && [ -e /persist/etc/localtime ]; then
        cp -Pf /persist/etc/localtime /etc/localtime
      else
        ln -sf /etc/zoneinfo/America/Argentina/Buenos_Aires /etc/localtime
      fi
    fi
  '';

  i18n = {
    defaultLocale = lib.mkDefault "en_US.UTF-8";
    extraLocales = [
      "ja_JP.UTF-8/UTF-8"
      "es_AR.UTF-8/UTF-8"
      "es_ES.UTF-8/UTF-8"
    ];
  };

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
