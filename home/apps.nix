{
  lib,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    # Editors & AI coding tools
    google-antigravity
    google-antigravity-cli

    # Productivity & daily desktop applications
    resources
    unstable.equibop
    (thunderbird.override {
      extraPrefs = ''
        pref("widget.use-xdg-desktop-portal.file-picker", 1);
      '';
    })
    unstable.euro-office-desktopeditors
    (unstable.mullvad-browser.override {
      extraPrefs = ''
        pref("widget.use-xdg-desktop-portal.file-picker", 1);
      '';
    })
    mpv
    kdePackages.elisa
    appimage-run

    # Fun & miscellaneous
    unstable.renpy
    unstable.cowsay
    unstable.lolcat
  ];

  # VSCodium
  programs.vscodium = {
    enable = true;
    mutableExtensionsDir = true;
  };

  # Antigravity global skills
  home.file.".gemini/config/skills/docx".source = ../dotfiles/skills/docx;

  # Merge declarative Nix-backed MCP servers into `~/.gemini/config/mcp_config.json`
  # as a regular 0600 file rather than a read-only HM symlink: `.gemini` is persisted
  # and Antigravity rewrites `mcp_config.json` in place when UI/OAuth MCP servers are
  # added, which otherwise breaks `home-manager-fumoctl.service` on reboot once
  # `mcp_config.json.backup` already exists.
  home.activation.antigravityMcpConfig =
    let
      declarativeMcp = (pkgs.formats.json { }).generate "antigravity-mcp.json" {
        mcpServers = {
          context7 = {
            command = lib.getExe pkgs.unstable.context7-mcp;
          };
          dbcode = {
            command = lib.getExe pkgs.bash;
            args = [
              "-c"
              ''exec ${lib.getExe pkgs.nodejs} "$(ls -d "$HOME"/.vscode-oss/extensions/dbcode.dbcode-*/out/cli/dbcode | sort -V | tail -n1)" mcp''
            ];
          };
          playwright = {
            command = lib.getExe pkgs.unstable.playwright-mcp;
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
      jqBin = lib.getExe pkgs.jq;
    in
    lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
      mcpCfg="$HOME/.gemini/config/mcp_config.json"
      mkdir -p "$(dirname "$mcpCfg")"
      rm -f "$mcpCfg.backup"
      tmpCfg="$(mktemp)"
      if [ -f "$mcpCfg" ] && [ ! -L "$mcpCfg" ] && ${jqBin} -e 'type == "object"' "$mcpCfg" >/dev/null 2>&1; then
        ${jqBin} -s '.[0] * .[1]' "$mcpCfg" "${declarativeMcp}" > "$tmpCfg"
      else
        cat "${declarativeMcp}" > "$tmpCfg"
      fi
      rm -f "$mcpCfg"
      install -m 600 "$tmpCfg" "$mcpCfg"
      rm -f "$tmpCfg"
    '';

  # Vivaldi Browser with proprietary media, Widevine DRM, Wayland, and extensions
  programs.vivaldi = {
    enable = true;
    package = pkgs.unstable.vivaldi.override {
      proprietaryCodecs = true;
      enableWidevine = true;
    };
    commandLineArgs = [
      "--ozone-platform-hint=auto"
    ];
    extensions = [
      { id = "ghmbeldphafepmbegfdlkpapadhbakde"; } # Proton Pass (Password manager)
      { id = "ldpochfccmkkmhdbclfhpagapcfdljkj"; } # Decentraleyes (Local CDN emulation)
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; } # Privacy Badger (Heuristic tracker blocker)
      { id = "ghbmnnjooekpmoecnnnilnnbdlolhkhi"; } # Google Docs Offline
      { id = "gbkeegbaiigmenfmjfclcdgdpimamgkj"; } # Google Docs MS Office
      { id = "donbcfbmhbcapadipfkeojnmajbakjdc"; } # Ruffle - Flash Emulator
    ];
  };
}
