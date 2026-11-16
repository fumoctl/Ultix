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

    # --- LaTeX ---
    # Full TeX Live (pdflatex/xelatex/lualatex, biber, latexmk, synctex, every package).
    # Raw `.tex` editing + PDF preview/SyncTeX is covered by VSCodium's LaTeX Workshop below.
    texliveFull
    texlab # LSP, used by the VSCodium LaTeX Workshop setup below
    tectonic # fast self-contained engine for quick one-off builds

    # Productivity & daily desktop applications
    resources
    unstable.discord
    onlyoffice-desktopeditors
    # Expose only the `soffice` CLI from LibreOffice (for headless conversions)
    # without installing its GUI `.desktop` launchers or MIME registrations.
    (runCommandLocal "soffice" { } ''
      mkdir -p "$out/bin"
      ln -s "${libreoffice-fresh}/bin/soffice" "$out/bin/soffice"
    '')
    pandoc
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
  # Drop skill folders (each with a SKILL.md) into `dotfiles/skills/` and they are
  # symlinked individually into `~/.gemini/config/skills/`.
  home.file.".gemini/config/skills" = {
    source = ../dotfiles/skills;
    recursive = true;
  };

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
      # Names of servers this block managed last time; any no longer declared get pruned.
      stateFile="$HOME/.gemini/config/.nix-managed-mcp.json"
      oldNames='[]'
      if [ -f "$stateFile" ] && ${jqBin} -e 'type == "array"' "$stateFile" >/dev/null 2>&1; then
        oldNames="$(cat "$stateFile")"
      fi
      newNames="$(${jqBin} -c '.mcpServers | keys' "${declarativeMcp}")"
      tmpCfg="$(mktemp)"
      if [ -f "$mcpCfg" ] && [ ! -L "$mcpCfg" ] && ${jqBin} -e 'type == "object"' "$mcpCfg" >/dev/null 2>&1; then
        ${jqBin} -s --argjson old "$oldNames" '
          (.[0] | .mcpServers |= ((. // {}) | with_entries(select(.key as $k | ($old | index($k)) | not)))) * .[1]
        ' "$mcpCfg" "${declarativeMcp}" > "$tmpCfg"
      else
        cat "${declarativeMcp}" > "$tmpCfg"
      fi
      rm -f "$mcpCfg"
      install -m 600 "$tmpCfg" "$mcpCfg"
      rm -f "$tmpCfg"
      printf '%s\n' "$newNames" > "$stateFile"
    '';

  # Brave Browser with privacy and utility extensions
  programs.brave = {
    enable = true;
    extensions = [
      { id = "ghmbeldphafepmbegfdlkpapadhbakde"; } # Proton Pass (Password manager)
      { id = "ldpochfccmkkmhdbclfhpagapcfdljkj"; } # Decentraleyes (Local CDN emulation)
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; } # Privacy Badger (Heuristic tracker blocker)
      { id = "jinjaccalgkegednnccohejagnlnfdag"; } # ViolentMonkey (Userscript Manager)
      { id = "ghbmnnjooekpmoecnnnilnnbdlolhkhi"; } # Google Docs Offline
      { id = "gbkeegbaiigmenfmjfclcdgdpimamgkj"; } # Google Docs MS Office
      { id = "donbcfbmhbcapadipfkeojnmajbakjdc"; } # Ruffle - Flash Emulator
    ];
  };
}
