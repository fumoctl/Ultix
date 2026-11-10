{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Umbriel-aware gamescope wrapper (`gs-run`).
  # Opens as a tiled/windowed Umbriel client by default (`Mod+F` toggles true
  # native fullscreen); pass `-f` / `--fullscreen` to start fullscreen immediately.
  #
  # Recommended Steam launch options by genre:
  #
  # 1. Visual Novels (typically locked to 16:9 or 4:3, 720p/1080p art):
  #    - Modern 16:9 VNs:  gs-run --16:9 %command%
  #    - Classic 4:3 VNs:  gs-run --4:3 %command%
  #    Tiles cleanly beside other windows on 32:9 (or pillarboxes on `Mod+F`),
  #    and defaults to `-F linear` (no FSR) so line art isn't over-sharpened.
  #
  # 2. 2D Games:
  #    - Pixel-art / retro:      gs-run --16:9 -F pixel %command%
  #      (`pixel` / `nearest` keeps crisp pixel edges instead of bilinear blur)
  #    - Hand-drawn / HD 2D:     gs-run --16:9 %command%   (or `gs-run %command%` if 32:9-native)
  #
  # 3. 3D Games:
  #    - Aspect / input fix:     gs-run -f %command%   (or `gs-run --21:9 %command%` / `--16:9`)
  #      Useful when a game breaks on 32:9, loses cursor lock (`--force-grab-cursor`),
  #      or mishandles Wayland focus/alt-tab.
  #    - Heavy 3D + upscaling:   gs-run -f --fsr --scale 0.75 %command%
  #      Renders at 75% internal resolution and upscales to native via AMD FSR 1.0.
  #
  # 4. Frame Generation (`lsfg-vk`) + MangoHud:
  #    - Native-aspect 3D games: LSFGVK_PROFILE="performance" mangohud %command%
  #      (Preferred whenever you don't need gamescope scaling/aspect clamping:
  #      avoids nested XWM swapchain frame drops with lsfg-vk's vsync pacing.)
  #    - Inside gs-run:          gs-run --mangoapp env LSFGVK_PROFILE="performance" %command%
  #      Keep `env LSFGVK_PROFILE=...` *after* `gs-run` so `lsfg-vk` only hooks the
  #      game inside gamescope, not gamescope's own Vulkan compositor.
  gs-run = pkgs.writeShellApplication {
    name = "gs-run";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      usage() {
        cat <<'EOF'
      Usage: gs-run [options] [--] <command...>

      Auto-detects the focused Umbriel monitor's native resolution, refresh rate,
      HDR, and VRR state, then launches the game inside gamescope.

      Options:
        --16:9               Render at 16:9 inside native height (e.g. 2560x1440 on 32:9)
        --21:9               Render at 21:9 inside native height (e.g. 3440x1440 on 32:9)
        --4:3                Render at 4:3 inside native height (e.g. 1920x1440)
        --scale <factor>     Internal render scale (0.1–1.0, e.g. 0.75) upscaled to native
        --fsr                Shorthand for -F fsr (AMD FSR 1.0 upscaling)
        -F, --filter <name>  Upscaler filter: linear (default), fsr, nis, nearest, pixel
        --sharpness <0-20>   Upscaler sharpness (0 = max, 20 = min)
        -f, --fullscreen     Start fullscreen immediately (default: windowed/tiled; Mod+F toggles)
        -b, --borderless     Start as a full-monitor borderless window
        -g, --grab           Grab keyboard
        --force-grab-cursor  Always lock relative mouse cursor inside gamescope
        --mangoapp           Enable MangoHud's mangoapp inside gamescope
        --backend <name>     Gamescope backend override (wayland, sdl, auto)
        --hdr                Force --hdr-enabled
        --vrr                Force --adaptive-sync
        --dry-run            Print the resolved gamescope command without running it
        -h, --help           Show this help

      Examples:
        Visual novels (16:9 / 4:3):
          gs-run --16:9 %command%
          gs-run --4:3 %command%
        2D pixel-art / hand-drawn:
          gs-run --16:9 -F pixel %command%
          gs-run --16:9 %command%
        3D native / upscaled:
          gs-run -f %command%
          gs-run -f --fsr --scale 0.75 %command%
        Frame generation (lsfg-vk) + MangoHud:
          gs-run --mangoapp env LSFGVK_PROFILE="performance" %command%
      EOF
      }

      if [ $# -eq 0 ]; then
        usage
        exit 0
      fi

      # Save and clear Steam's LD_PRELOAD and ancient Ubuntu 12 steam-runtime
      # LD_LIBRARY_PATH immediately so Nix helper binaries (umbriel, jq, gawk)
      # and gamescope itself use their Nix store RPATHs cleanly, then restore
      # both for the game command inside gamescope.
      saved_preload="''${LD_PRELOAD:-}"
      saved_ld_library_path="''${LD_LIBRARY_PATH:-}"
      saved_disable_lsfgvk="''${DISABLE_LSFGVK:-}"
      unset LD_PRELOAD
      if [ -n "''${SYSTEM_LD_LIBRARY_PATH:-}" ]; then
        export LD_LIBRARY_PATH="$SYSTEM_LD_LIBRARY_PATH"
      else
        unset LD_LIBRARY_PATH
      fi

      aspect=""
      scale="1.0"
      filter="linear"
      window_mode=""
      backend=""
      dry_run=0
      force_hdr=0
      force_vrr=0
      extra_gs=()

      while [ $# -gt 0 ]; do
        case "$1" in
          -h | --help)
            usage
            exit 0
            ;;
          --16:9)
            aspect="16:9"
            shift
            ;;
          --21:9)
            aspect="21:9"
            shift
            ;;
          --4:3)
            aspect="4:3"
            shift
            ;;
          --scale)
            scale="''${2:?--scale requires a factor (e.g. 0.75)}"
            shift 2
            ;;
          --fsr)
            filter="fsr"
            shift
            ;;
          -F | --filter)
            filter="''${2:?--filter requires a name}"
            shift 2
            ;;
          --sharpness | --fsr-sharpness)
            extra_gs+=("--sharpness" "''${2:?--sharpness requires 0-20}")
            shift 2
            ;;
          -f | --fullscreen)
            window_mode="-f"
            shift
            ;;
          -b | --borderless)
            window_mode="-b"
            shift
            ;;
          -g | --grab)
            extra_gs+=("-g")
            shift
            ;;
          --force-grab-cursor)
            extra_gs+=("--force-grab-cursor")
            shift
            ;;
          --mangoapp)
            extra_gs+=("--mangoapp")
            shift
            ;;
          --backend)
            backend="''${2:?--backend requires sdl, wayland, or auto}"
            shift 2
            ;;
          --hdr)
            force_hdr=1
            shift
            ;;
          --vrr)
            force_vrr=1
            shift
            ;;
          --dry-run)
            dry_run=1
            shift
            ;;
          --)
            shift
            break
            ;;
          -*)
            extra_gs+=("$1")
            shift
            ;;
          *)
            break
            ;;
        esac
      done

      if [ $# -eq 0 ] && [ "$dry_run" -eq 0 ]; then
        echo "gs-run: missing command to execute" >&2
        exit 2
      fi

      out_w=1920
      out_h=1080
      out_hz=60
      out_hdr="false"
      out_vrr="false"

      if detected="$(
        ${lib.getExe config.programs.umbriel.package} outputs --json 2>/dev/null \
          | ${lib.getExe pkgs.jq} -r '
              (map(select(.enabled and .focused))[0] // map(select(.enabled))[0]) as $o
              | select($o != null)
              | ($o.modes | map(select(.current))[0] // $o.modes[0]) as $m
              | (($o.transform // "normal") | IN("90", "270", "flipped-90", "flipped-270")) as $rot
              | ($m.width // $o.logical_size.width // 1920) as $rw
              | ($m.height // $o.logical_size.height // 1080) as $rh
              | (if $rot then $rh else $rw end) as $w
              | (if $rot then $rw else $rh end) as $h
              | ((($m.refresh_mhz // 60000) + 500) / 1000 | floor) as $hz
              | "\($w) \($h) \($hz) \($o.hdr_active // false) \($o.adaptive_sync // false)"
            '
      )" && [ -n "$detected" ]; then
        read -r out_w out_h out_hz out_hdr out_vrr <<<"$detected"
      fi

      base_w="$out_w"
      base_h="$out_h"
      case "$aspect" in
        16:9)
          base_w=$(( ((out_h * 16 / 9) + 1) / 2 * 2 ))
          ;;
        21:9)
          if [ "$out_h" -eq 1440 ]; then
            base_w=3440
          elif [ "$out_h" -eq 1080 ]; then
            base_w=2560
          else
            base_w=$(( ((out_h * 21 / 9) + 1) / 2 * 2 ))
          fi
          ;;
        4:3)
          base_w=$(( ((out_h * 4 / 3) + 1) / 2 * 2 ))
          ;;
      esac

      read -r game_w game_h <<<"$(
        ${lib.getExe pkgs.gawk} -v w="$base_w" -v h="$base_h" -v s="$scale" '
          BEGIN {
            if (s <= 0) s = 1.0
            gw = int((w * s + 1) / 2) * 2
            gh = int((h * s + 1) / 2) * 2
            if (gw < 2) gw = 2
            if (gh < 2) gh = 2
            printf "%d %d\n", gw, gh
          }
        '
      )"

      gamescope_bin="gamescope"
      if ! command -v "$gamescope_bin" >/dev/null 2>&1; then
        gamescope_bin="${lib.getExe config.programs.gamescope.package}"
      fi

      # In windowed mode, size the initial outer window to the target aspect
      # (Umbriel dynamically resizes -W/-H when tiled or Mod+F fullscreened);
      # in fullscreen/borderless mode, target the full monitor directly.
      win_w="$base_w"
      win_h="$base_h"
      if [ -n "$window_mode" ]; then
        win_w="$out_w"
        win_h="$out_h"
      fi

      use_hdr=0
      if [ "$force_hdr" -eq 1 ] || [ "$out_hdr" = "true" ]; then
        use_hdr=1
      fi

      gs_cmd=(
        "$gamescope_bin"
        -W "$win_w"
        -H "$win_h"
        -w "$game_w"
        -h "$game_h"
        -r "$out_hz"
        -F "$filter"
      )

      if [ -n "$backend" ]; then
        gs_cmd+=("--backend" "$backend")
      fi

      if [ -n "$window_mode" ]; then
        gs_cmd+=("$window_mode")
      fi
      if [ "$use_hdr" -eq 1 ]; then
        gs_cmd+=("--hdr-enabled")
      fi
      if [ "$force_vrr" -eq 1 ] || [ "$out_vrr" = "true" ]; then
        gs_cmd+=("--adaptive-sync")
      fi
      if [ "''${#extra_gs[@]}" -gt 0 ]; then
        gs_cmd+=("''${extra_gs[@]}")
      fi

      inner_env=("DISABLE_LSFGVK=$saved_disable_lsfgvk")
      if [ -n "$saved_preload" ]; then
        inner_env+=("LD_PRELOAD=$saved_preload")
      fi
      if [ -n "$saved_ld_library_path" ]; then
        inner_env+=("LD_LIBRARY_PATH=$saved_ld_library_path")
      fi

      inner_cmd=(env)
      if [ -z "$saved_disable_lsfgvk" ]; then
        inner_cmd+=(-u DISABLE_LSFGVK)
        inner_env=("''${inner_env[@]:1}")
      fi
      if [ "''${#inner_env[@]}" -gt 0 ]; then
        inner_cmd+=("''${inner_env[@]}")
      fi
      inner_cmd+=("$@")

      full_cmd=("''${gs_cmd[@]}" -- "''${inner_cmd[@]}")

      if [ "$dry_run" -eq 1 ]; then
        printf '%q ' "''${full_cmd[@]}"
        printf '\n'
        exit 0
      fi

      export DISABLE_LSFGVK=1
      exec "''${full_cmd[@]}"
    '';
  };
in
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.steam-hardware.enable = true;

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

  services.lact.enable = true;

  environment.systemPackages = with pkgs; [
    lact
    mangohud
    goverlay
    mesa-demos
    lsfg-vk
    gs-run
  ];
}
