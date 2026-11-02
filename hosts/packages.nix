{
  pkgs,
  inputs,
  ...
}:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-all;
  };

  documentation.man.cache.enable = true;

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

  environment.systemPackages = with pkgs; [
    # Development & Nix tooling
    nixd
    nixfmt
    inputs.nix-alien.packages.${pkgs.stdenv.hostPlatform.system}.nix-alien
    neovim
    git
    meld
    distrobox
    python3

    # System & CLI utilities
    fastfetch
    file
    jq
    pciutils
    ethtool
    sbctl
    _7zz
    unrar
    zip
    unzip
    sshfs
    wget
    curl
    tree
    ripgrep
    fd
    btrfs-progs
    libsecret
    seahorse

    # Network utilities
    dnsmasq
    sshuttle
    waypipe
    iptables
    iproute2
  ];
}
