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
    unstable.onlyoffice-desktopeditors
    (unstable.mullvad-browser.override {
      extraPrefs = ''
        pref("widget.use-xdg-desktop-portal.file-picker", 1);
      '';
    })
    mpv
    lollypop
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

  # Antigravity MCP servers
  home.file.".gemini/config/mcp_config.json".source =
    (pkgs.formats.json { }).generate "antigravity-mcp.json"
      {
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
}
