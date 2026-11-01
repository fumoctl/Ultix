{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  # --- SOPS Secrets ---
  sops = {
    age.keyFile = "/persist/sops/fumosops.key";
    defaultSopsFile = ../secrets/secrets.yaml;
    validateSopsFiles = false;

    secrets = {
      "fumossh.key" = {
        path = "${config.home.homeDirectory}/.ssh/fumossh.key";
        mode = "0600";
      };
      "fumopgp.key" = {
        mode = "0600";
      };
      abacusai_api_key = {
        mode = "0600";
      };
    };

    templates."shell-secrets.sh".content = ''
      export ABACUSAI_API_KEY="${config.sops.placeholder.abacusai_api_key}"
    '';
  };
  systemd.user.services.sops-nix = {
    Unit.ConditionPathExists = "/persist/sops/fumosops.key";
  };
  home.sessionVariables.SOPS_AGE_KEY_FILE = "/persist/sops/fumosops.key";

  home.packages = with pkgs; [
    sops
    age
    ssh-to-age
    ptyxis
    resources
    fastfetch
    btop
    eza
    bat
    fzf
    ripgrep
    fd
    bibata-cursors
    kdePackages.breeze-icons
  ];

  # SSH client configuration with non-symlink permission safety
  home.file.".ssh/config_source" = {
    text = ''
      Host github.com
          HostName github.com
          User git
          IdentityFile ~/.ssh/fumossh.key

      Host *
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
    '';
    onChange = ''
      cp ~/.ssh/config_source ~/.ssh/config
      chmod 600 ~/.ssh/config
    '';
  };

  # Git with commit signing
  programs.git = {
    enable = true;
    signing = {
      key = "35FAC098F119E8FA";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "JuanU";
        email = "juanu@fumoctl.com";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = ''
      [ -f "${config.sops.templates."shell-secrets.sh".path}" ] && source "${
        config.sops.templates."shell-secrets.sh".path
      }"
      if [ -f "${
        config.sops.secrets."fumopgp.key".path
      }" ] && ! gpg -K 35FAC098F119E8FA >/dev/null 2>&1; then
        gpg --batch --import "${config.sops.secrets."fumopgp.key".path}" >/dev/null 2>&1
        echo "5F3C25D755D3A4321D03FF7135FAC098F119E8FA:6:" | gpg --batch --import-ownertrust >/dev/null 2>&1
      fi
    '';
    oh-my-zsh = {
      enable = true;
      theme = "dpoggi";
      plugins = [
        "git"
        "sudo"
      ];
    };
  };

  # VSCodium
  programs.vscodium = {
    enable = true;
    mutableExtensionsDir = true;
  };

  # Antigravity MCP Config
  home.file.".gemini/config/mcp_config.json".source =
    (pkgs.formats.json { }).generate "antigravity-mcp.json"
      {
        mcpServers = {
          context7 = {
            command = "${pkgs.unstable.context7-mcp}/bin/context7-mcp";
          };
          dbcode = {
            command = "${pkgs.bash}/bin/bash";
            args = [
              "-c"
              ''exec ${pkgs.nodejs}/bin/node "$(ls -d "$HOME"/.vscode-oss/extensions/dbcode.dbcode-*/out/cli/dbcode | sort -V | tail -n1)" mcp''
            ];
          };
          playwright = {
            command = "${pkgs.unstable.playwright-mcp}/bin/playwright-mcp";
            args = [
              "--browser"
              "chromium"
            ];
          };
          rivalsearch = {
            serverUrl = "https://RivalSearchMCP.fastmcp.app/mcp";
          };
        };
      };

  # Brave Browser with privacy and utility extensions
  programs.brave = {
    enable = true;
    extensions = [
      { id = "ghmbeldphafepmbegfdlkpapadhbakde"; } # Proton Pass (Password manager)
      { id = "ldpochfccmkkmhdbclfhpagapcfdljkj"; } # Decentraleyes (Local CDN emulation)
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; } # Privacy Badger (Heuristic tracker blocker)
      { id = "ghbmnnjooekpmoecnnnilnnbdlolhkhi"; } # Google Docs Offline
      { id = "gbkeegbaiigmenfmjfclcdgdpimamgkj"; } # Google Docs MS Office
      { id = "donbcfbmhbcapadipfkeojnmajbakjdc"; } # Ruffle - Flash Emulator
    ];
  };

  # Flatpak Integration & Management
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
  };

  home.activation = {
    configureFlatpakLanguages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.flatpak}/bin/flatpak config --user --set languages "en;ja;es"
    '';

    fixobsqt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.flatpak}/bin/flatpak override --user --unset-env=QT_PLUGIN_PATH --unset-env=LD_LIBRARY_PATH --unset-env=QT_QPA_PLATFORM_PLUGIN_PATH com.obsproject.Studio
    '';

    overrideBottlesFsHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.flatpak}/bin/flatpak override --user --filesystem=home com.usebottles.bottles
    '';

    flatpakThemeOverrides = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.flatpak}/bin/flatpak override --user \
        --filesystem=/nix/store:ro \
        --filesystem=xdg-data/themes:ro \
        --filesystem=xdg-data/icons:ro \
        --filesystem=xdg-config/gtk-3.0:ro \
        --filesystem=xdg-config/gtk-4.0:ro
    '';
  };

  # Terminal Emulator (Ptyxis) settings
  dconf.settings = {
    "org/gnome/Ptyxis" = {
      restore-session = false;
    };
  };

  xdg.configFile."Thunar/uca.xml" = {
    force = true;
    text = ''
      <?xml version="1.0" encoding="UTF-8" ?>
      <actions>
        <action>
          <name>Open Terminal Here</name>
          <command>ptyxis --new-window -d %f</command>
          <description>Open Ptyxis in the current folder</description>
          <patterns>*</patterns>
          <directories/>
        </action>
      </actions>
    '';
  };

  # XDG MIME associations
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/mailto" = "thunderbird.desktop";

      "text/plain" = "codium.desktop";
      "text/markdown" = "codium.desktop";
      "text/x-markdown" = "codium.desktop";

      "application/json" = "codium.desktop";
      "application/x-yaml" = "codium.desktop";
      "text/yaml" = "codium.desktop";
      "text/x-yaml" = "codium.desktop";
      "application/toml" = "codium.desktop";
      "text/x-toml" = "codium.desktop";
      "application/xml" = "codium.desktop";
      "text/xml" = "codium.desktop";
      "text/x-ini" = "codium.desktop";
      "text/x-properties" = "codium.desktop";

      "application/x-shellscript" = "codium.desktop";
      "text/x-shellscript" = "codium.desktop";
      "application/x-bash" = "codium.desktop";
      "text/x-python" = "codium.desktop";
      "application/x-python-code" = "codium.desktop";
      "text/x-lua" = "codium.desktop";

      "text/x-c" = "codium.desktop";
      "text/x-csrc" = "codium.desktop";
      "text/x-chdr" = "codium.desktop";
      "text/x-c++" = "codium.desktop";
      "text/x-c++src" = "codium.desktop";
      "text/x-c++hdr" = "codium.desktop";
      "text/x-rust" = "codium.desktop";
      "text/rust" = "codium.desktop";
      "text/x-go" = "codium.desktop";
      "text/javascript" = "codium.desktop";
      "application/javascript" = "codium.desktop";
      "text/typescript" = "codium.desktop";
      "application/typescript" = "codium.desktop";
      "text/css" = "codium.desktop";
      "text/x-scss" = "codium.desktop";
      "text/x-sql" = "codium.desktop";

      "text/x-diff" = "codium.desktop";
      "text/x-patch" = "codium.desktop";
      "text/x-dockerfile" = "codium.desktop";
      "text/x-makefile" = "codium.desktop";
      "text/x-cmake" = "codium.desktop";

      "inode/directory" = "Thunar.desktop";

      # Photos & Images (Gwenview)
      "image/jpeg" = "org.kde.gwenview.desktop";
      "image/png" = "org.kde.gwenview.desktop";
      "image/gif" = "org.kde.gwenview.desktop";
      "image/webp" = "org.kde.gwenview.desktop";
      "image/svg+xml" = "org.kde.gwenview.desktop";
      "image/bmp" = "org.kde.gwenview.desktop";
      "image/tiff" = "org.kde.gwenview.desktop";
      "image/avif" = "org.kde.gwenview.desktop";
      "image/heic" = "org.kde.gwenview.desktop";
      "image/x-icon" = "org.kde.gwenview.desktop";

      # Music & Audio
      "audio/mpeg" = "org.gnome.Lollypop.desktop";
      "audio/flac" = "org.gnome.Lollypop.desktop";
      "audio/x-vorbis+ogg" = "org.gnome.Lollypop.desktop";
      "audio/ogg" = "org.gnome.Lollypop.desktop";
      "audio/mp4" = "org.gnome.Lollypop.desktop";
      "audio/aac" = "org.gnome.Lollypop.desktop";
      "audio/x-wav" = "org.gnome.Lollypop.desktop";

      # Compressed Archives
      "application/zip" = "xarchiver.desktop";
      "application/x-tar" = "xarchiver.desktop";
      "application/x-compressed-tar" = "xarchiver.desktop";
      "application/x-bzip-compressed-tar" = "xarchiver.desktop";
      "application/x-xz-compressed-tar" = "xarchiver.desktop";
      "application/x-zstd-compressed-tar" = "xarchiver.desktop";
      "application/x-7z-compressed" = "xarchiver.desktop";
      "application/vnd.rar" = "xarchiver.desktop";
      "application/x-rar" = "xarchiver.desktop";
      "application/gzip" = "xarchiver.desktop";
      "application/x-bzip2" = "xarchiver.desktop";
      "application/x-xz" = "xarchiver.desktop";

      # Documents & PDF (Okular)
      "application/pdf" = "org.kde.okular.desktop";

      # Video Players
      "video/mp4" = "mpv.desktop";
      "video/mkv" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";

      # Windows executables (Bottles)
      "application/x-ms-dos-executable" = "com.usebottles.bottles.desktop";
      "application/x-msdownload" = "com.usebottles.bottles.desktop";
      "application/x-msi" = "com.usebottles.bottles.desktop";
      "application/vnd.microsoft.portable-executable" = "com.usebottles.bottles.desktop";
    };
  };
}
