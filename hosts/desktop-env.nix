{
  lib,
  pkgs,
  inputs,
  ...
}:

let
  # Standalone KDE/Dolphin XDG menu spec without pulling plasma-workspace into
  # the runtime closure. Covers empty, plasma-, and umbriel- prefixes, plus
  # Plasma's .directory category metadata for Dolphin's "Open With" dialog.
  kdeXdgMenus =
    pkgs.runCommandLocal "kde-xdg-menus"
      {
        disallowedReferences = [ pkgs.kdePackages.plasma-workspace ];
      }
      ''
        install -Dm644 \
          "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu" \
          "$out/etc/xdg/menus/applications.menu"
        ln -s applications.menu "$out/etc/xdg/menus/plasma-applications.menu"
        ln -s applications.menu "$out/etc/xdg/menus/umbriel-applications.menu"
        mkdir -p "$out/share"
        cp -r "${pkgs.kdePackages.plasma-workspace}/share/desktop-directories" \
          "$out/share/desktop-directories"
      '';
in
{
  imports = [
    inputs.noctalia.nixosModules.default
    inputs.noctalia-greeter.nixosModules.default
    inputs.umbriel.nixosModules.default
  ];

  # --- Session & Login Manager ---
  programs.umbriel.enable = true;

  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
  };

  services.displayManager.noctalia-greeter = {
    enable = true;
    passwordless-sync-users = [ "fumoctl" ];
    settings = {
      session.default = "Umbriel";
      user.default = "fumoctl";
      appearance = {
        theme_mode = "dark";
        font_family = "JetBrainsMono Nerd Font";
      };
      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
        path = "${pkgs.bibata-cursors}/share/icons";
      };
      keyboard = {
        layout = "us";
        variant = "altgr-intl";
        options = "lv3:ralt_switch";
        numlock = true;
      };
    };
  };

  # Seed AccountsService portrait for `fumoctl` so `noctalia-greeter` displays
  # it on the login screen (`greeter` cannot traverse `0700` /home/fumoctl).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/AccountsService/icons/fumoctl - - - - ${../dotfiles/.fumoctl.jpg}"
    "f /var/lib/AccountsService/users/fumoctl 0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/fumoctl\\n"
  ];

  # GNOME Keyring: secret service (libsecret) + PKCS#11, DBus-activated and
  # started per-user by Home Manager. `noctalia-greeter` logs in through
  # `greetd`, so its PAM stack unlocks the login keyring automatically. SSH
  # component is intentionally NOT enabled (HM side): gpg-agent already provides
  # the SSH agent via programs.gnupg.agent.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # --- Input, Audio & Power ---
  services.xserver = {
    enable = true;
    xkb = {
      layout = "us";
      variant = "altgr-intl";
    };
  };

  services.libinput = {
    enable = true;
    mouse.accelProfile = "flat";
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  hardware.bluetooth = {
    enable = lib.mkDefault true;
    powerOnBoot = true;
  };
  services.upower.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkDefault true;

  # --- Portals & Session Environment ---
  # `programs.umbriel.enable` registers `xdg-desktop-portal-umbriel` automatically.
  xdg.portal = {
    enable = true;
    wlr.enable = false;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
    config = {
      common = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
        "org.freedesktop.impl.portal.AppChooser" = [ "kde" ];
      };
      # NOTE: this per-DE section overrides `common` for ALL interfaces when
      # XDG_CURRENT_DESKTOP=Umbriel. The umbriel backend only implements
      # Screenshot/ScreenCast/InputCapture, so "gtk" must stay in the list or
      # org.freedesktop.portal.Settings disappears from the portal broker and
      # libadwaita/GTK4 apps always see light mode. FileChooser and
      # AppChooser are explicitly routed to "kde" for the Dolphin picker.
      umbriel = {
        default = [
          "umbriel"
          "gtk"
        ];
        "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
        "org.freedesktop.impl.portal.AppChooser" = [ "kde" ];
      };
    };
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "Umbriel";
    XDG_SESSION_DESKTOP = "Umbriel";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    GDK_BACKEND = "wayland,x11,*";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
    DICPATH = "/run/current-system/sw/share/hunspell";
  };

  # --- Fonts ---
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

  # --- Flatpak Daemon ---
  services.flatpak.enable = true;

  # --- File Management & KDE Integration (Dolphin / KIO) ---
  qt = {
    enable = true;
    platformTheme = "kde";
  };

  xdg.menus.enable = true;
  xdg.mime.enable = true;

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.udev.packages = [ pkgs.media-player-info ];

  services.dbus.packages = with pkgs.kdePackages; [
    dolphin
    kio
    kio-extras
    kio-fuse
    kio-admin
  ];

  systemd.packages = with pkgs.kdePackages; [
    dolphin
    kio
    kio-extras
    kio-fuse
    kio-admin
  ];

  # System-level KDE defaults merged underneath ~/.config/{kdeglobals,konsolerc}
  # via KConfig cascading, leaving the user files mutable for Noctalia & GUI edits.
  environment.etc."xdg/kdeglobals".text = ''
    [General]
    TerminalApplication=konsole
  '';

  environment.etc."xdg/konsolerc".text = ''
    [Desktop Entry]
    DefaultProfile=Ultix.profile
  '';

  # Expose Konsole profiles installed in user/system packages (e.g. Ultix.profile)
  # via XDG_DATA_DIRS while keeping ~/.local/share/konsole mutable.
  environment.pathsToLink = [ "/share/konsole" ];

  # Clear stale KSycoca caches before graphical session start (Nix store mtimes are 1970-01-01).
  systemd.user.services.nixos-rebuild-sycoca = {
    description = "Clear stale KDE system configuration cache";
    wantedBy = [ "graphical-session-pre.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      rm -fv "''${XDG_CACHE_HOME:-$HOME/.cache}/ksycoca"*
    '';
  };

  environment.systemPackages = with pkgs; [
    # KDE / Dolphin integration & thumbnailers (system-wide for KF6 plugin discovery)
    kdeXdgMenus
    kdePackages.konsole
    kdePackages.dolphin
    kdePackages.dolphin-plugins
    kdePackages.kio
    kdePackages.kio-extras
    kdePackages.kio-fuse
    kdePackages.kio-admin
    kdePackages.kservice
    kdePackages.solid
    kdePackages.kfilemetadata
    kdePackages.baloo-widgets
    kdePackages.kdegraphics-thumbnailers
    kdePackages.ffmpegthumbs
    kdePackages.kimageformats
    kdePackages.qtimageformats
    kdePackages.qtsvg
    kdePackages.kiconthemes
    kdePackages.qtwayland
    kdePackages.breeze
    kdePackages.breeze-icons
    kdePackages.gwenview
    kdePackages.okular
    kdePackages.ark
    hicolor-icon-theme
    icoutils

    # Spellcheck dictionaries (referenced via system-wide DICPATH)
    hunspell
    hunspellDicts.en_US
    hunspellDicts.es_AR

    # Wayland & session helpers
    wl-clipboard
    wl-mirror
    grim
    slurp
    brightnessctl
    playerctl
    wireplumber
    libnotify
  ];
}
