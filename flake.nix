{
  description = "Ultix: Modular host-separated NixOS Stable configuration with Umbriel, Noctalia, and Impermanence";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    impermanence.url = "github:nix-community/impermanence";
    disko.url = "github:nix-community/disko";
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    umbriel.url = "github:noctalia-dev/umbriel/cachix";
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";
    lsfg-vk.url = "github:Daaboulex/lsfg-vk-nix";
    nix-alien.url = "github:thiagokokada/nix-alien";
    windscribe-nixos.url = "github:fumoctl/windscribe-nixos";
    portal-screen-mirror.url = "github:fumoctl/portal-screen-mirror";
    betterstremio.url = "github:fumoctl/BetterStremio/v1.2.2";
    antigravity-nix.url = "github:jacopone/antigravity-nix";
    idea-nixos.url = "github:fumoctl/IDEA-nixos";
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://noctalia.cachix.org"
      "https://umbriel.cachix.org"
      "https://nyx-cache.chaotic.cx"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "umbriel.cachix.org-1:JfNq/2yg2S6D6z4Z2dVSZrZlDPQTKtexB6GAVLD98nw="
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      disko,
      chaotic,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            chaotic.nixosModules.nyx-cache
            chaotic.nixosModules.nyx-overlay
            chaotic.nixosModules.nyx-registry
            hostModule
          ];
        };
    in
    {
      nixosConfigurations = {
        ultix-desktop = mkHost ./hosts/desktop;
        ultix-laptop = mkHost ./hosts/laptop;
      };

      checks.${system}.scripts =
        let
          desktop = self.nixosConfigurations.ultix-desktop;
          inherit (desktop) pkgs;
          inherit (pkgs) lib;
          hmCfg = desktop.config.home-manager.users.fumoctl;
          pluginSources = lib.mapAttrsToList (_: v: v.source) (
            lib.filterAttrs (k: _: lib.hasPrefix ".gemini/config/plugins/" k) hmCfg.home.file
          );
          pluginBuilder = (builtins.head pluginSources).builder;
          skillsSource = hmCfg.home.file.".gemini/config/skills".source;
          gsRun = lib.findFirst (
            p: (p.pname or p.name or "") == "gs-run"
          ) null desktop.config.environment.systemPackages;
          bwInner =
            (lib.findFirst (
              p: (p.pname or p.name or "") == "bottles-winetricks"
            ) null desktop.config.environment.systemPackages).inner;
          scrollBin = builtins.elemAt (lib.splitString " "
            hmCfg.programs.umbriel.settings.keybinds."Mod+WheelDown"
          ) 1;
          tzGuard = desktop.config.systemd.services.tzupdate.serviceConfig.ExecCondition;
          tzDispatcher = (builtins.head desktop.config.networking.networkmanager.dispatcherScripts).source;
          mcpAct = pkgs.writeShellScript "antigravity-mcp-act" ''
            set -euo pipefail
            ${hmCfg.home.activation.antigravityMcpConfig.data}
          '';
          steamAct = pkgs.writeShellScript "steam-compat-act" ''
            set -euo pipefail
            ${hmCfg.home.activation.syncSteamCompatTools.data}
          '';
          steamActBroken = pkgs.writeShellScript "steam-compat-broken-act" ''
            set -euo pipefail
            ${builtins.replaceStrings
              [ "${pkgs.proton-cachyos-bin_edge.steamcompattool}" ]
              [ "$TMP/missing-proton" ]
              hmCfg.home.activation.syncSteamCompatTools.data
            }
          '';
          zshMigrateAct = pkgs.writeShellScript "zsh-migrate-act" ''
            set -euo pipefail
            ${hmCfg.home.activation.migrateZshHistory.data}
          '';
          gearleverAct = pkgs.writeShellScript "gearlever-dir-act" ''
            set -euo pipefail
            ${hmCfg.home.activation.configureGearLeverDir.data}
          '';
          flutterSdkAct = pkgs.writeShellScript "intellij-flutter-sdk-act" (
            "set -euo pipefail\n"
            + builtins.unsafeDiscardStringContext (
              builtins.replaceStrings
                [
                  "${hmCfg.programs.intellij.flutter.package}"
                  hmCfg.programs.intellij.flutter.sdkPath
                ]
                [
                  "$FAKE_FLUTTER_PKG"
                  "$FLUTTER_SDK_OUT"
                ]
                hmCfg.home.activation.intellij-flutter-sdk.data
            )
          );
          ideaWrapperCmd = builtins.unsafeDiscardStringContext hmCfg.programs.intellij.finalPackage.buildCommand;
          ideaXtoolkitAct = pkgs.writeShellScript "idea-xtoolkit-act" (
            builtins.unsafeDiscardStringContext (
              builtins.replaceStrings
                [ "${lib.getExe hmCfg.programs.intellij.finalPackage}" ]
                [ "$FAKE_IDEA_BIN" ]
                (lib.findFirst (p: (p.name or "") == "idea") null hmCfg.home.packages).text
            )
          );
          cleanRootAct = pkgs.writeShellScript "impermanence-clean-root-act" (
            builtins.replaceStrings [ "/btrfs_tmp" ] [ "$BTRFS_TMP" ]
              desktop.config.boot.initrd.systemd.services.impermanence-clean-root.script
          );
        in
        pkgs.runCommandLocal "ultix-checks"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.python3
            ];
          }
          ''
            set -euo pipefail
            unset WAYLAND_DISPLAY UMBRIEL_SOCKET XDG_DATA_HOME XDG_STATE_HOME
            TMP="$(mktemp -d)"

            # 1. Antigravity plugins (npins), builder edge cases, and local skills layout
            for p in ${lib.escapeShellArgs pluginSources}; do
              test -f "$p/plugin.json"
              found=0
              for s in "$p"/skills/*/SKILL.md; do
                if [ -f "$s" ]; then found=1; fi
              done
              test "$found" -eq 1
            done
            for d in "${skillsSource}"/* "${skillsSource}"/.[!.]* "${skillsSource}"/..?*; do
              [ -d "$d" ] || continue
              test -f "$d/SKILL.md"
            done

            syn1="$TMP/syn1"
            mkdir -p "$syn1/skills/alpha/scripts" "$syn1/commands"
            printf -- '---\nname: alpha\ndescription: Alpha skill\n---\nBody\n' > "$syn1/skills/alpha/SKILL.md"
            printf '#!/bin/sh\necho ok\n' > "$syn1/skills/alpha/scripts/run.sh"
            chmod 555 "$syn1/skills/alpha/scripts/run.sh"
            chmod 444 "$syn1/skills/alpha/SKILL.md"
            printf -- '---\n---\nEmpty frontmatter body\n' > "$syn1/commands/empty-fm.md"
            printf 'Plain command body\n' > "$syn1/commands/plain.md"
            printf 'description = "TOML command"\nprompt = "Run TOML"\n' > "$syn1/commands/toml-cmd.toml"
            python3 ${pluginBuilder} syn1 "$syn1" "$TMP/out-syn1" v1.2.0
            test -x "$TMP/out-syn1/skills/alpha/scripts/run.sh"
            test ! -x "$TMP/out-syn1/skills/alpha/SKILL.md"
            test "$(grep -c '^---$' "$TMP/out-syn1/skills/empty-fm/SKILL.md")" -eq 2
            test -f "$TMP/out-syn1/skills/plain/SKILL.md"
            test -f "$TMP/out-syn1/skills/toml-cmd/SKILL.md"
            HOME="$TMP/agy-home" ${lib.getExe pkgs.google-antigravity-cli} plugin validate --strict "$TMP/out-syn1"

            syn2="$TMP/syn2"
            mkdir -p "$syn2/scripts"
            printf -- '---\nname: syn2\ndescription: Root skill\n---\nBody\n' > "$syn2/SKILL.md"
            printf '#!/bin/sh\necho root\n' > "$syn2/scripts/helper.sh"
            chmod 555 "$syn2/scripts/helper.sh"
            python3 ${pluginBuilder} syn2 "$syn2" "$TMP/out-syn2" ""
            test -x "$TMP/out-syn2/skills/syn2/scripts/helper.sh"
            HOME="$TMP/agy-home" ${lib.getExe pkgs.google-antigravity-cli} plugin validate --strict "$TMP/out-syn2"

            # 2. gs-run flags, WINEPREFIX forwarding, and Umbriel IPC (outputs --json & scroll)
            gsOut="$(${lib.getExe gsRun} --dry-run --16:9 --fsr --scale 0.75 -- fake-game)"
            [[ "$gsOut" == *"-w 1440 -h 810"* && "$gsOut" == *"-F fsr"* ]]

            mkdir -p "$TMP/bin"
            printf '#!${pkgs.runtimeShell}\nexit 0\n' > "$TMP/bin/wine"
            printf '#!${pkgs.runtimeShell}\necho "$1=''${WINEPREFIX:-}" >> "$TMP/ws.log"\n' > "$TMP/bin/wineserver"
            printf '#!${pkgs.runtimeShell}\nexec "$@"\n' > "$TMP/bin/mangohud"
            chmod +x "$TMP/bin/wine" "$TMP/bin/wineserver" "$TMP/bin/mangohud"
            wineOut="$(${lib.getExe gsRun} --dry-run mangohud env WINEPREFIX=/tmp/custom-pfx "$TMP/bin/wine" game.exe)"
            [[ "$wineOut" == *gs-wine-wait* && "''${wineOut%% mangohud *}" == *"/tmp/custom-pfx"* ]]
            TMP="$TMP" PATH="$TMP/bin:$PATH" eval "''${wineOut#* -- }"
            grep -Fxq -- "-w=/tmp/custom-pfx" "$TMP/ws.log"

            cat > "$TMP/umbriel-state.json" <<'EOF'
            {
              "outputs": [{
                "name": "DP-2",
                "enabled": true,
                "focused": true,
                "hdr_active": true,
                "adaptive_sync": true,
                "transform": "90",
                "logical_size": { "width": 1440, "height": 3440 },
                "modes": [{ "current": true, "preferred": true, "width": 3440, "height": 1440, "refresh_mhz": 164995 }]
              }],
              "workspaces": [{
                "active": true,
                "focused": true,
                "focused_window": "",
                "id": "DP-2:1",
                "index": 1,
                "layout": "scrolling",
                "layout_override": false,
                "name": "1",
                "named": true,
                "occupied": true,
                "output": "DP-2",
                "previous": false,
                "urgent": false,
                "window_count": 1
              }]
            }
            EOF
            python3 - "$TMP/umbriel.sock" "$TMP/umbriel-state.json" "$TMP/umbriel.log" <<'PY' &
            import json, socket, sys
            sock_path, state_file, log_file = sys.argv[1], sys.argv[2], sys.argv[3]
            srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            srv.bind(sock_path)
            srv.listen(16)
            while True:
                conn, _ = srv.accept()
                req = json.loads(conn.makefile().readline())
                with open(log_file, "a") as lf:
                    lf.write(json.dumps(req, sort_keys=True) + "\n")
                with open(state_file) as sf:
                    state = json.load(sf)
                cmd = req.get("cmd")
                resp = {"ok": state["outputs"] if cmd == "outputs" else state["workspaces"] if cmd == "workspaces" else None}
                conn.sendall((json.dumps(resp) + "\n").encode())
                conn.close()
            PY
            umbPid=$!
            trap 'kill "$umbPid" 2>/dev/null || true' EXIT
            while [ ! -S "$TMP/umbriel.sock" ]; do sleep 0.02; done

            gsIpcOut="$(UMBRIEL_SOCKET="$TMP/umbriel.sock" ${lib.getExe gsRun} --dry-run -- true)"
            [[ "$gsIpcOut" == *"-W 1440 -H 3440 -w 1440 -h 3440 -r 165"* && "$gsIpcOut" == *"--hdr-enabled"* && "$gsIpcOut" == *"--adaptive-sync"* ]]

            : > "$TMP/umbriel.log"
            UMBRIEL_SOCKET="$TMP/umbriel.sock" ${scrollBin} previous
            UMBRIEL_SOCKET="$TMP/umbriel.sock" ${scrollBin} next
            jq '.workspaces[0].layout = "dwindle"' "$TMP/umbriel-state.json" > "$TMP/umbriel-state.next"
            mv "$TMP/umbriel-state.next" "$TMP/umbriel-state.json"
            UMBRIEL_SOCKET="$TMP/umbriel.sock" ${scrollBin} previous
            UMBRIEL_SOCKET="$TMP/umbriel.sock" ${scrollBin} next
            grep -Fxq '{"action": "window-focus-left", "cmd": "action"}' "$TMP/umbriel.log"
            grep -Fxq '{"action": "window-focus-right", "cmd": "action"}' "$TMP/umbriel.log"
            grep -Fxq '{"action": "workspace-previous", "cmd": "action"}' "$TMP/umbriel.log"
            grep -Fxq '{"action": "workspace-next", "cmd": "action"}' "$TMP/umbriel.log"
            kill "$umbPid" 2>/dev/null || true
            trap - EXIT

            # 3. bottles-winetricks-inner bottle lookup, vkd3d seeding, and wine shim scoping
            bwData="$TMP/bw-data"
            bottleDir="$bwData/bottles/bottles/SodaDir"
            runnerDir="$bwData/Steam/compatibilitytools.d/Proton-Test/files"
            mkdir -p "$bottleDir/drive_c/windows/system32" "$bottleDir/drive_c/windows/syswow64" \
              "$runnerDir/bin" "$runnerDir/lib64/vkd3d" "$runnerDir/lib/vkd3d" \
              "$runnerDir/lib64/wine" "$runnerDir/lib64/gstreamer-1.0" "$TMP/bw-bin"
            printf 'Name: "Soda Visual"\nRunner: Proton-Test\nRunnerPath: ""\n' > "$bottleDir/bottle.yml"
            printf 'dll64' > "$runnerDir/lib64/vkd3d/libvkd3d-1.dll"
            printf 'dll32' > "$runnerDir/lib/vkd3d/libvkd3d-1.dll"
            cat > "$runnerDir/bin/wine" <<'EOF'
            #!${pkgs.runtimeShell}
            printf 'LD=%s\nDLL=%s\nGST=%s\nLOADER=%s\n' "''${LD_LIBRARY_PATH:-}" "''${WINEDLLPATH:-}" "''${GST_PLUGIN_SYSTEM_PATH_1_0:-}" "''${WINELOADER:-}" > "$SHIM_ENV_OUT"
            EOF
            printf '%s\n' '#!${pkgs.runtimeShell}' 'exit 0' > "$runnerDir/bin/wineserver"
            cat > "$TMP/bw-bin/winetricks" <<'EOF'
            #!${pkgs.runtimeShell}
            set -euo pipefail
            test "$1" = "cjkfonts"
            test "$WINEPREFIX" = "$EXPECTED_PREFIX"
            [[ "''${LD_LIBRARY_PATH:-}" != *"$RUNNER_DIR"* ]]
            "$WINE" --probe
            EOF
            chmod +x "$runnerDir/bin/wine" "$runnerDir/bin/wineserver" "$TMP/bw-bin/winetricks"
            bwList="$(XDG_DATA_HOME="$bwData" PATH="$TMP/bw-bin:$PATH" ${lib.getExe bwInner} --list)"
            [[ "$bwList" == *"Soda Visual (dir: SodaDir, runner: Proton-Test)"* ]]
            SHIM_ENV_OUT="$TMP/wine-shim.env" EXPECTED_PREFIX="$bottleDir" RUNNER_DIR="$runnerDir" \
              XDG_DATA_HOME="$bwData" PATH="$TMP/bw-bin:$PATH" ${lib.getExe bwInner} "Soda Visual" cjkfonts 2>/dev/null
            test -f "$bottleDir/drive_c/windows/system32/libvkd3d-1.dll"
            test -f "$bottleDir/drive_c/windows/syswow64/libvkd3d-1.dll"
            grep -Fq "LD=$runnerDir/lib64" "$TMP/wine-shim.env"
            grep -Fq "DLL=$runnerDir/lib64/wine" "$TMP/wine-shim.env"
            grep -Fq "GST=$runnerDir/lib64/gstreamer-1.0" "$TMP/wine-shim.env"
            grep -Fxq "LOADER=$runnerDir/bin/wine" "$TMP/wine-shim.env"

            # 4. antigravityMcpConfig fresh creation, merge/prune/shape-replace, and corrupt-file guard
            mcpHome="$TMP/mcp-home"
            mcpCfg="$mcpHome/.gemini/config/mcp_config.json"
            mcpState="$mcpHome/.gemini/config/.nix-managed-mcp.json"
            HOME="$mcpHome" ${mcpAct}
            test "$(stat -c '%a' "$mcpCfg")" = "600"
            test -f "$mcpState"

            printf '%s\n' '["staleNix","rivalsearch"]' > "$mcpState"
            cat > "$mcpCfg" <<'EOF'
            {
              "mcpServers": {
                "customUser": { "command": "/bin/custom" },
                "staleNix": { "command": "/bin/stale" },
                "rivalsearch": { "command": "/bin/old-rival", "args": ["--old"] }
              }
            }
            EOF
            HOME="$mcpHome" ${mcpAct}
            test "$(stat -c '%a' "$mcpCfg")" = "600"
            jq -e '
              .mcpServers.customUser.command == "/bin/custom"
              and (.mcpServers | has("staleNix") | not)
              and (.mcpServers.rivalsearch.serverUrl | type == "string" and length > 0)
              and (.mcpServers.rivalsearch | has("command") | not)
              and (.mcpServers.rivalsearch | has("args") | not)
            ' "$mcpCfg" >/dev/null

            printf '{malformed\n' > "$mcpCfg"
            cp "$mcpCfg" "$TMP/malformed.orig"
            if HOME="$mcpHome" ${mcpAct} 2>/dev/null; then
              exit 1
            fi
            cmp -s "$mcpCfg" "$TMP/malformed.orig"

            # 5. syncSteamCompatTools stale cleanup, unmanaged preservation, and pre-delete validation
            steamHome="$TMP/steam-home"
            compatDir="$steamHome/.local/share/Steam/compatibilitytools.d"
            mkdir -p "$compatDir/Stale-Proton" "$compatDir/Custom-Proton"
            touch "$compatDir/Stale-Proton/.nix-managed" "$compatDir/Custom-Proton/marker"
            HOME="$steamHome" ${steamAct}
            test ! -e "$compatDir/Stale-Proton"
            test -f "$compatDir/Custom-Proton/marker"
            for r in Proton-CachyOS Proton-GE GE-Proton9-12; do
              test -d "$compatDir/$r" && test ! -L "$compatDir/$r"
              test -f "$compatDir/$r/.nix-managed"
              test -f "$compatDir/$r/compatibilitytool.vdf"
              test -x "$compatDir/$r/proton"
            done
            if TMP="$TMP" HOME="$steamHome" ${steamActBroken} 2>/dev/null; then
              exit 1
            fi
            test -x "$compatDir/Proton-CachyOS/proton"

            # 6. tzupdate VPN guard/dispatcher, Zsh history migration, and impermanence-clean-root
            mkdir -p "$TMP/tz-bin"
            printf '#!${pkgs.runtimeShell}\nprintf "%%s\\n" "''${FAKE_ROUTE:-}"\n' > "$TMP/tz-bin/ip"
            printf '#!${pkgs.runtimeShell}\necho "$*" >> "$TMP/systemctl.log"\n' > "$TMP/tz-bin/systemctl"
            chmod +x "$TMP/tz-bin/ip" "$TMP/tz-bin/systemctl"
            if FAKE_ROUTE="9.9.9.9 dev utun420 table 51820 src 100.64.0.1" PATH="$TMP/tz-bin:$PATH" ${tzGuard}; then
              exit 1
            fi
            if FAKE_ROUTE="" PATH="$TMP/tz-bin:$PATH" ${tzGuard}; then
              exit 1
            fi
            FAKE_ROUTE="9.9.9.9 via 192.168.1.1 dev enp9s0 src 192.168.1.10" PATH="$TMP/tz-bin:$PATH" ${tzGuard}

            sed 's|/.*/bin/systemctl|systemctl|' ${tzDispatcher} > "$TMP/tz-disp"
            chmod +x "$TMP/tz-disp"
            : > "$TMP/systemctl.log"
            PATH="$TMP/tz-bin:$PATH" "$TMP/tz-disp" utun420 up
            PATH="$TMP/tz-bin:$PATH" "$TMP/tz-disp" lo up
            CONNECTION_EXTERNAL=1 PATH="$TMP/tz-bin:$PATH" "$TMP/tz-disp" enp9s0 up
            test ! -s "$TMP/systemctl.log"
            PATH="$TMP/tz-bin:$PATH" "$TMP/tz-disp" enp9s0 up
            grep -Fxq "start --no-block tzupdate.service" "$TMP/systemctl.log"

            zshHome="$TMP/zsh-home"
            mkdir -p "$zshHome/.config/zsh"
            printf 'echo legacy\n' > "$zshHome/.config/zsh/.zsh_history"
            HOME="$zshHome" ${zshMigrateAct}
            test "$(stat -c '%a' "$zshHome/.local/state/zsh/history")" = "600"
            grep -Fxq "echo legacy" "$zshHome/.local/state/zsh/history"
            printf 'echo newer\n' > "$zshHome/.local/state/zsh/history"
            HOME="$zshHome" ${zshMigrateAct}
            grep -Fxq "echo newer" "$zshHome/.local/state/zsh/history"

            mkdir -p "$TMP/initrd-bin"
            cat > "$TMP/initrd-bin/mountpoint" <<'EOF'
            #!${pkgs.runtimeShell}
            [ -f "$2/.mounted" ]
            EOF
            cat > "$TMP/initrd-bin/mount" <<'EOF'
            #!${pkgs.runtimeShell}
            eval "last=\$$#"
            touch "$last/.mounted"
            mkdir -p "$last/@"
            echo "mount" >> "$BTRFS_LOG"
            EOF
            cat > "$TMP/initrd-bin/umount" <<'EOF'
            #!${pkgs.runtimeShell}
            rm -f "$1/.mounted"
            echo "umount" >> "$BTRFS_LOG"
            EOF
            cat > "$TMP/initrd-bin/btrfs" <<'EOF'
            #!${pkgs.runtimeShell}
            if [ "$1" = "subvolume" ] && [ "$2" = "list" ]; then
              printf 'ID 256 gen 10 top level 5 path @\nID 257 gen 11 top level 256 path @/var/lib/machines\nID 258 gen 12 top level 5 path @persist\n'
            elif [ "$1" = "subvolume" ] && [ "$2" = "delete" ] && [ "''${FAIL_DELETE:-0}" = "1" ]; then
              exit 1
            else
              echo "btrfs $*" >> "$BTRFS_LOG"
            fi
            EOF
            chmod +x "$TMP/initrd-bin"/*
            BTRFS_TMP="$TMP/btrfs_tmp" BTRFS_LOG="$TMP/btrfs.log" PATH="$TMP/initrd-bin:$PATH" ${cleanRootAct}
            grep -Fxq "btrfs property set -ts $TMP/btrfs_tmp/@ ro false" "$TMP/btrfs.log"
            grep -Fxq "btrfs property set -ts $TMP/btrfs_tmp/@/var/lib/machines ro false" "$TMP/btrfs.log"
            ! grep -Fq "@persist" "$TMP/btrfs.log"
            grep -Fxq "btrfs subvolume delete -R $TMP/btrfs_tmp/@" "$TMP/btrfs.log"
            grep -Fxq "btrfs subvolume create $TMP/btrfs_tmp/@" "$TMP/btrfs.log"
            test ! -f "$TMP/btrfs_tmp/.mounted"

            if FAIL_DELETE=1 BTRFS_TMP="$TMP/btrfs_tmp" BTRFS_LOG="$TMP/btrfs-fail.log" PATH="$TMP/initrd-bin:$PATH" ${cleanRootAct} 2>/dev/null; then
              exit 1
            fi
            test ! -f "$TMP/btrfs_tmp/.mounted"

            # 7. configureGearLeverDir fresh creation, keyfile merge/update, idempotency, and corrupt-file guard
            glHome="$TMP/gl-home"
            glKeyfile="$glHome/.var/app/it.mijorus.gearlever/config/glib-2.0/settings/keyfile"
            HOME="$glHome" ${gearleverAct}
            test "$(stat -c '%a' "$glKeyfile")" = "600"
            grep -Fxq "[it/mijorus/gearlever]" "$glKeyfile"
            grep -Fxq "appimages-default-folder='~/Applications'" "$glKeyfile"

            cat > "$glKeyfile" <<'EOF'
            [it/mijorus/gearlever]
            first-run=false
            appimages-default-folder='~/AppImages'

            [other/section]
            flag=true
            EOF
            HOME="$glHome" ${gearleverAct}
            test "$(stat -c '%a' "$glKeyfile")" = "600"
            grep -Fxq "appimages-default-folder='~/Applications'" "$glKeyfile"
            grep -Fxq "first-run=false" "$glKeyfile"
            grep -Fxq "[other/section]" "$glKeyfile"
            grep -Fxq "flag=true" "$glKeyfile"
            ! grep -Fq "AppImages" "$glKeyfile"
            HOME="$glHome" ${gearleverAct}

            printf 'not-valid-ini\n' > "$glKeyfile"
            cp "$glKeyfile" "$TMP/gl-malformed.orig"
            if HOME="$glHome" ${gearleverAct} 2>/dev/null; then
              exit 1
            fi
            cmp -s "$glKeyfile" "$TMP/gl-malformed.orig"

            # 8. IntelliJ wrapper script syntax/env, XToolkit shim, and non-Nix-store Flutter SDK link hook
            printf '%s\n' ${lib.escapeShellArg ideaWrapperCmd} | ${pkgs.bash}/bin/bash -n
            for marker in SSL_CERT_FILE NIX_SSL_CERT_FILE JAVA_HOME ANDROID_JAVA_HOME rustup bun nodejs FLUTTER_ROOT GOROOT NIX_LD_LIBRARY_PATH QT_XKB_CONFIG_ROOT; do
              grep -Fq "$marker" <<<${lib.escapeShellArg ideaWrapperCmd}
            done
            printf '#!${pkgs.runtimeShell}\nprintf "NR=%%s\\nIJ=%%s\\nARGS=%%s\\n" "$_JAVA_AWT_WM_NONREPARENTING" "$IJ_JAVA_OPTIONS" "$*"\n' > "$TMP/fake-idea"
            chmod +x "$TMP/fake-idea"
            ideaOut="$(unset _JAVA_AWT_WM_NONREPARENTING IJ_JAVA_OPTIONS; FAKE_IDEA_BIN="$TMP/fake-idea" ${ideaXtoolkitAct} --line 42 foo.nix)"
            grep -Fxq "NR=1" <<<"$ideaOut"
            grep -Fxq "IJ=-Dawt.toolkit.name=XToolkit" <<<"$ideaOut"
            grep -Fxq "ARGS=--line 42 foo.nix" <<<"$ideaOut"
            ideaOverride="$(IJ_JAVA_OPTIONS="-Dawt.toolkit.name=WLToolkit" FAKE_IDEA_BIN="$TMP/fake-idea" ${ideaXtoolkitAct})"
            grep -Fxq "IJ=-Dawt.toolkit.name=WLToolkit" <<<"$ideaOverride"
            fakeFlutter="$TMP/fake-flutter"
            sdkOut="$TMP/flutter-sdk"
            mkdir -p "$fakeFlutter/bin" "$fakeFlutter/packages" "$fakeFlutter/.git" "$sdkOut"
            touch "$fakeFlutter/bin/flutter" "$fakeFlutter/version" "$fakeFlutter/.git/HEAD"
            ln -s "$TMP/nonexistent" "$sdkOut/stale-entry"
            FAKE_FLUTTER_PKG="$fakeFlutter" FLUTTER_SDK_OUT="$sdkOut" ${flutterSdkAct}
            test -d "$sdkOut" && test ! -L "$sdkOut"
            test ! -L "$sdkOut/stale-entry"
            test -L "$sdkOut/bin" && test -f "$sdkOut/bin/flutter"
            test -L "$sdkOut/version"
            test -L "$sdkOut/.git" && test -f "$sdkOut/.git/HEAD"
            FAKE_FLUTTER_PKG="$fakeFlutter" FLUTTER_SDK_OUT="$sdkOut" ${flutterSdkAct}
            test ! -L "$sdkOut/.git/.git"

            touch "$out"
          '';
    };
}
