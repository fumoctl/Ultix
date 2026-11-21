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
    antigravity-nix.url = "github:jacopone/antigravity-nix";
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
          skillsSource = hmCfg.home.file.".gemini/config/skills".source;
          gsRun = lib.findFirst (
            p: (p.pname or p.name or "") == "gs-run"
          ) null desktop.config.environment.systemPackages;
          mcpAct = pkgs.writeShellScript "antigravity-mcp-act" ''
            set -euo pipefail
            ${hmCfg.home.activation.antigravityMcpConfig.data}
          '';
          steamAct = pkgs.writeShellScript "steam-compat-act" ''
            set -euo pipefail
            ${hmCfg.home.activation.syncSteamCompatTools.data}
          '';
        in
        pkgs.runCommandLocal "ultix-checks" { nativeBuildInputs = [ pkgs.jq ]; } ''
          set -euo pipefail
          unset WAYLAND_DISPLAY UMBRIEL_SOCKET XDG_DATA_HOME
          TMP="$(mktemp -d)"

          # 1. Antigravity plugins (npins) and local skills layout
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

          # 2. gs-run scaling/filter flags and WINEPREFIX forwarding to gs-wine-wait
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

          # 3. antigravityMcpConfig fresh creation, merge/prune/shape-replace, and corrupt-file guard
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

          # 4. syncSteamCompatTools stale cleanup, unmanaged preservation, and .nix-managed markers
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

          touch "$out"
        '';
    };
}
