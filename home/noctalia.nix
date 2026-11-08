{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  umbrielBin = lib.getExe config.programs.umbriel.package;
  # Layout-aware Mod+Wheel helper: scrolls across windows/columns when the
  # focused workspace uses `scrolling`, and switches workspaces otherwise.
  umbrielWheelScroll = pkgs.writeShellScriptBin "scroll" ''
    case "$("${umbrielBin}" workspaces)"$'\n' in
      *" [scrolling] (focused)"$'\n'*)
        case "$1" in
          previous) exec "${umbrielBin}" msg window-focus-left ;;
          *) exec "${umbrielBin}" msg window-focus-right ;;
        esac
        ;;
      *)
        case "$1" in
          previous) exec "${umbrielBin}" msg workspace-previous ;;
          *) exec "${umbrielBin}" msg workspace-next ;;
        esac
        ;;
    esac
  '';
in
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.umbriel.homeModules.default
  ];

  # Runtime deps for Noctalia's theming hooks:
  # - adw-gtk3: the GTK theme the template's apply.sh looks up and syncs
  #   (adw-gtk3 / adw-gtk3-dark depending on light/dark mode)
  # - glib: provides `gsettings`, used by the GTK apply hook to set
  #   org.gnome.desktop.interface gtk-theme / color-scheme
  home.packages = with pkgs; [
    adw-gtk3
    glib
    kdePackages.qt6ct
  ];

  # GTK theming: use adw-gtk3-dark (matches theme.mode = "dark") so Noctalia's
  # generated CSS applies on top, and give the shell an icon theme (Noctalia
  # resolves app icons through GTK's icon-theme support).
  gtk = {
    enable = true;
    theme.name = "adw-gtk3-dark";
    iconTheme = {
      name = "breeze";
      package = pkgs.kdePackages.breeze-icons;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "kde"; # Uses native KDE theming/KColorScheme
  };

  # Home Manager's qt module writes systemd.user.sessionVariables.QT_PLUGIN_PATH
  # to ~/.config/environment.d/10-home-manager.conf with only the HM user
  # profile, overriding NixOS's profileRelativeSessionVariables in the systemd
  # user manager. Include /run/current-system/sw so Dolphin discovers
  # system-wide KF6 plugins (Ark's extract/compress/DnD plugins, kio-extras,
  # thumbnailers, Breeze, etc.).
  systemd.user.sessionVariables =
    let
      qtVersions = [
        pkgs.qt5
        pkgs.qt6
      ];
      mkQtPaths =
        attr:
        lib.concatStringsSep ":" (
          lib.concatMap (qt: [
            "${config.home.profileDirectory}/${qt.qtbase.${attr}}"
            "/run/current-system/sw/${qt.qtbase.${attr}}"
          ]) qtVersions
        );
    in
    {
      QT_PLUGIN_PATH = lib.mkForce (mkQtPaths "qtPluginPrefix");
      QML2_IMPORT_PATH = lib.mkForce (mkQtPaths "qtQmlPrefix");
      NIX_XDG_DESKTOP_PORTAL_DIR = "/run/current-system/sw/share/xdg-desktop-portal/portals";
    };

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "kde";
  };

  # Cursor theme: Bibata Modern Ice. HM's pointerCursor module installs the
  # package, links it into ~/.icons & $XDG_DATA_HOME/icons, exports
  # XCURSOR_THEME/XCURSOR_SIZE, and fills gtk.cursorTheme for GTK apps.
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
  };

  home.file."Pictures/Wallpapers/wallpaper.png".source = ../dotfiles/wallpaper.png;

  # --- Noctalia Shell ---
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      shell = {
        launch_apps_as_systemd_services = true;
        umbriel_overview_type_to_launch_enabled = true;
        umbriel_overview_close_on_launch_enabled = true;
        umbriel_audio_provider_enabled = true;
      };

      theme = {
        builtin = "Tokyo-Night";
        templates = {
          builtin_ids = [
            "gtk3"
            "gtk4"
            "kcolorscheme"
            "umbriel"
          ];
          enable_community_templates = true;
          community_ids = [ "konsole" ];
        };
      };

      wallpaper = {
        enabled = true;
        directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
        default.path = "${config.home.homeDirectory}/Pictures/Wallpapers/wallpaper.png";
      };

      plugins.enabled = [ "elijaharch/wl-screen-mirror" ];

      bar.default = {
        capsule_group = [ ];
        start = [
          "media"
          "audio_visualizer"
          "workspaces"
          "spacer_2"
          "active_window"
        ];
        center = [
          "clock"
          "date"
        ];
        end = [
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "mirror"
          "volume"
          "brightness"
          "battery"
          "control-center"
        ];
        font_family = "JetBrainsMono NF Medium";
        font_weight = 400;
        margin_edge = 5;
        margin_ends = 10;
        padding = 10;
      };

      widget = {
        active_window = {
          capsule = true;
          font_scale = 1.1;
          icon_size = 20;
          max_length = 800;
        };
        audio_visualizer = {
          scale = 1.4;
          width = 60;
        };
        "control-center" = {
          glyph = "brand-zhihu";
          scale = 1.25;
        };
        media = {
          hide_artist = true;
          hide_when_no_media = true;
          max_length = 800;
          min_length = 0;
          scale = 1.1;
        };
        network = {
          scale = 1.1;
          show_label = false;
        };
        spacer_2.type = "spacer";
        volume = {
          glyph = "volume";
          scale = 1.1;
        };
        mirror = {
          type = "elijaharch/wl-screen-mirror:mirror";
          scale = 1.05;
        };
        battery.scale = 1.1;
        brightness.scale = 1.1;
        clipboard.scale = 1.1;
        notifications.scale = 1.1;
        tray.scale = 1.1;
        workspaces = {
          font_scale = 1.1;
          scale = 1.3;
        };
        clock.scale = 1.1;
        date.scale = 1.1;
      };
    };
  };

  # --- Umbriel Compositor ---
  # `umbriel.service` (installed by `programs.umbriel.enable` in hosts/desktop-env.nix)
  # exports the Wayland session environment and activates `graphical-session.target`,
  # which starts `noctalia.service` automatically. Do NOT add `"noctalia"` to
  # `general.autostart` or a duplicate shell instance will spawn.
  programs.umbriel = {
    enable = true;
    settings = {
      # Noctalia's built-in `umbriel` template renders dynamic theme colors into
      # `~/.config/umbriel/noctalia.toml`; keeping the entry as `"noctalia.toml"`
      # matches `apply.sh` so it leaves the read-only HM symlink untouched.
      include.optional.files = [ "noctalia.toml" ];

      general = {
        mod_key = "Super";
        xwayland = true;
        show_cheatsheet = false;
        autostart = [
          "equibop -m"
          "steam -silent"
        ];
      };

      environment = {
        QT_QPA_PLATFORMTHEME = "kde";
        XCURSOR_THEME = "Bibata-Modern-Ice";
        XCURSOR_SIZE = "24";
      };

      input = {
        keyboard = {
          layout = "us";
          variant = "altgr-intl";
          options = "lv3:ralt_switch";
          numlock_toggle = true;
        };
        mouse.accel_profile = "flat";
        touchpad = {
          tap = true;
          natural_scroll = true;
        };
        cursor = {
          theme = "Bibata-Modern-Ice";
          size = 24;
        };
        focus = {
          follows_mouse = true;
          hover_raises = false;
        };
      };

      layout = {
        mode = "dwindle";
        gap = 10;
        extent_presets = [
          0.333
          0.5
          0.667
        ];
        dwindle.preserve_split = true;
        scrolling.default_extent_fraction = 0.5;
      };

      appearance = {
        prefer_no_csd = true;
        border_width = 2;
        corner_radius = 12;
        blur = {
          enabled = true;
          optimized = true;
          passes = 2;
          radius = 4;
        };
        shadow = {
          enabled = true;
          softness = 10;
        };
      };

      animation = {
        enabled = true;
        layers.enabled = false;
      };

      hot_corners.top_left = {
        enabled = true;
        delay_ms = 500;
        action = "overview-open";
      };

      window_rule = [
        { blur = true; }
        {
          match.is_focused = false;
          opacity = 0.88;
        }
        {
          match.is_focused = true;
          opacity = 0.94;
        }
        {
          match.app_id = "^dev\\.noctalia\\.Noctalia$";
          default_floating = true;
          default_floating_size_px = {
            width = 1020;
            height = 900;
          };
        }
        {
          match.app_id = "^dev\\.noctalia\\.UmbrielSharePicker$";
          default_floating = true;
          default_floating_size_px = {
            width = 800;
            height = 600;
          };
        }
        {
          match.title = "^(Picture-in-Picture|Picture in picture)$";
          default_floating = true;
          default_maximize = false;
          default_position = {
            x = 20;
            y = 20;
            anchor = "bottom_right";
          };
        }
        {
          match.title = "^notificationtoasts_.+_desktop";
          default_position = {
            x = 0;
            y = 0;
            anchor = "bottom_right";
          };
          default_focused = false;
          default_pinned = true;
        }
        {
          match.app_id = "^org\\.freedesktop\\.impl\\.portal\\.desktop\\.kde$";
          default_floating = true;
        }
        {
          match.app_id = "^[Ww]indscribe$";
          default_floating = true;
          border_width = 0;
          blur = false;
          shadow = false;
          corner_radius = 0;
          opacity = 1.0;
        }
      ];

      layer_rule = [
        {
          match.namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd|desktop-widget-[^\"]*)$";
          blur = true;
          blur_ignore_alpha = 0.5;
          blur_popups = true;
        }
        {
          match.namespace = "^noctalia-(notification|dock|panel|attached-panel|osd)$";
          blur_optimized = false;
        }
        {
          match.namespace = "^gtk-layer-shell$";
          blur = true;
        }
      ];

      keybinds = {
        # Applications & session
        "Mod+Return" = {
          action = "spawn konsole";
          repeat = false;
        };
        "Mod+E" = {
          action = "spawn dolphin";
          repeat = false;
        };
        "Mod+B" = {
          action = "spawn vivaldi --new-window";
          repeat = false;
        };
        "Mod+Q" = {
          action = "window-close";
          repeat = false;
        };
        "Mod+M" = {
          action = "session-quit";
          repeat = false;
        };
        "Mod+Slash" = {
          action = "cheatsheet-toggle";
          repeat = false;
        };
        "Mod+Shift+Escape" = {
          action = "shortcuts-inhibit-toggle";
          allow_when_inhibited = true;
          repeat = false;
        };

        # Window state & layout
        "Mod+F" = {
          action = "window-toggle-fullscreen";
          repeat = false;
        };
        "Mod+T" = {
          action = "window-toggle-floating";
          repeat = false;
        };
        "Mod+Shift+T" = {
          action = "window-focus-switch-floating";
          repeat = false;
        };
        "Mod+P" = {
          action = "window-toggle-pinned";
          repeat = false;
        };
        "Mod+J" = {
          action = "layout-toggle-split";
          repeat = false;
        };
        "Mod+Shift+Tab" = {
          action = "workspace-set-layout toggle dwindle scrolling";
          repeat = false;
        };
        "Mod+O" = {
          action = "overview-toggle";
          repeat = false;
        };

        # Noctalia Shell IPC controls
        "Mod+Space" = "spawn noctalia msg panel-toggle launcher";
        "Mod+V" = "spawn noctalia msg panel-toggle clipboard";
        "Mod+S" = "spawn noctalia msg panel-toggle control-center";
        "Mod+Comma" = "spawn noctalia msg settings-toggle";
        "Alt+Tab" = "spawn noctalia msg window-switcher hold";
        "Alt+Shift+Tab" = "spawn noctalia msg window-switcher hold reverse";

        # Screenshots via Noctalia IPC
        "Mod+Shift+S" = {
          action = "spawn noctalia msg screenshot-fullscreen";
          repeat = false;
        };
        "Mod+Shift+Ctrl+S" = {
          action = "spawn noctalia msg screenshot-region";
          repeat = false;
        };

        # Focus & directional movement
        "Mod+Left" = "window-focus-left";
        "Mod+Right" = "window-focus-right";
        "Mod+Up" = "window-focus-up";
        "Mod+Down" = "window-focus-down";
        "Mod+Shift+Left" = "window-move-left";
        "Mod+Shift+Right" = "window-move-right";
        "Mod+Shift+Up" = "window-move-up";
        "Mod+Shift+Down" = "window-move-down";

        # Layout-aware scroll: windows in `scrolling`, workspaces otherwise
        "Mod+WheelDown" = "spawn ${umbrielWheelScroll}/bin/scroll next window or workspace";
        "Mod+WheelUp" = "spawn ${umbrielWheelScroll}/bin/scroll previous window or workspace";

        # Media, audio & brightness (routed through Noctalia for OSDs)
        "XF86AudioRaiseVolume" = {
          action = "spawn noctalia msg volume-up";
          allow_when_locked = true;
        };
        "XF86AudioLowerVolume" = {
          action = "spawn noctalia msg volume-down";
          allow_when_locked = true;
        };
        "XF86AudioMute" = {
          action = "spawn noctalia msg volume-mute";
          allow_when_locked = true;
          repeat = false;
        };
        "XF86AudioMicMute" = {
          action = "spawn noctalia msg mic-mute";
          allow_when_locked = true;
          repeat = false;
        };
        "XF86AudioPlay" = {
          action = "spawn noctalia msg media toggle";
          allow_when_locked = true;
          repeat = false;
        };
        "XF86AudioNext" = {
          action = "spawn noctalia msg media next";
          allow_when_locked = true;
        };
        "XF86AudioPrev" = {
          action = "spawn noctalia msg media previous";
          allow_when_locked = true;
        };
        "XF86MonBrightnessUp" = {
          action = "spawn noctalia msg brightness-up";
          allow_when_locked = true;
        };
        "XF86MonBrightnessDown" = {
          action = "spawn noctalia msg brightness-down";
          allow_when_locked = true;
        };
      }
      // lib.mergeAttrsList (
        map (
          n:
          let
            ws = toString n;
          in
          {
            "Mod+${ws}" = "workspace-switch ${ws}";
            "Mod+Shift+${ws}" = "window-move-to-workspace ${ws}";
          }
        ) (lib.range 1 9)
      );
    };
  };
}
