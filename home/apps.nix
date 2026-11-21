{
  lib,
  pkgs,
  inputs,
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
    kdePackages.elisa
    inputs.betterstremio.packages.${pkgs.stdenv.hostPlatform.system}.default

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

  xdg.configFile."mpv/shaders".source = pkgs.anime4k;

  programs.mpv =
    let
      shaderChain = names: lib.concatMapStringsSep ":" (n: "~~/shaders/Anime4K_${n}.glsl") names;
      modeA = shaderChain [
        "Clamp_Highlights"
        "Restore_CNN_VL"
        "Upscale_CNN_x2_VL"
        "AutoDownscalePre_x2"
        "AutoDownscalePre_x4"
        "Upscale_CNN_x2_M"
      ];
      bindMode =
        names: label:
        ''no-osd change-list glsl-shaders set "${shaderChain names}"; show-text "Anime4K: ${label}"'';
    in
    {
      enable = true;
      config.glsl-shaders = modeA;
      bindings = {
        "CTRL+1" = ''no-osd change-list glsl-shaders set "${modeA}"; show-text "Anime4K: Mode A (HQ)"'';
        "CTRL+2" = bindMode [
          "Clamp_Highlights"
          "Restore_CNN_Soft_VL"
          "Upscale_CNN_x2_VL"
          "AutoDownscalePre_x2"
          "AutoDownscalePre_x4"
          "Upscale_CNN_x2_M"
        ] "Mode B (HQ)";
        "CTRL+3" = bindMode [
          "Clamp_Highlights"
          "Upscale_Denoise_CNN_x2_VL"
          "AutoDownscalePre_x2"
          "AutoDownscalePre_x4"
          "Upscale_CNN_x2_M"
        ] "Mode C (HQ)";
        "CTRL+4" = bindMode [
          "Clamp_Highlights"
          "Restore_CNN_VL"
          "Upscale_CNN_x2_VL"
          "Restore_CNN_M"
          "AutoDownscalePre_x2"
          "AutoDownscalePre_x4"
          "Upscale_CNN_x2_M"
        ] "Mode A+A (HQ)";
        "CTRL+5" = bindMode [
          "Clamp_Highlights"
          "Restore_CNN_Soft_VL"
          "Upscale_CNN_x2_VL"
          "AutoDownscalePre_x2"
          "AutoDownscalePre_x4"
          "Restore_CNN_Soft_M"
          "Upscale_CNN_x2_M"
        ] "Mode B+B (HQ)";
        "CTRL+6" = bindMode [
          "Clamp_Highlights"
          "Upscale_Denoise_CNN_x2_VL"
          "AutoDownscalePre_x2"
          "AutoDownscalePre_x4"
          "Restore_CNN_M"
          "Upscale_CNN_x2_M"
        ] "Mode C+A (HQ)";
        "CTRL+0" = ''no-osd change-list glsl-shaders clr ""; show-text "GLSL shaders cleared"'';
      };
    };

  # Antigravity global skills & portable npins-backed plugins.
  # - Drop hand-written skill folders (with SKILL.md) into `dotfiles/skills/`.
  # - Add/update/remove external GitHub skill or plugin repos with `npins`:
  #     `npins add github <owner> <repo>` | `npins update` | `npins remove <name>`
  #   Each pin in `npins/sources.json` is converted automatically into a validated
  #   Antigravity plugin (`skills/*/SKILL.md`, root `SKILL.md`, or `commands/*.{md,toml}`)
  #   under `~/.gemini/config/plugins/<name>/` while leaving `plugins/` writable.
  home.file =
    let
      antigravityPlugins = (import ../npins) { };
      buildAntigravityPlugin = pkgs.writeText "build-antigravity-plugin.py" ''
        import json
        import os
        import re
        import shutil
        import sys
        import tomllib
        from pathlib import Path

        plugin_name = sys.argv[1]
        src = Path(sys.argv[2])
        out = Path(sys.argv[3])
        pin_version = sys.argv[4]

        out_skills = out / "skills"
        out_skills.mkdir(parents=True, exist_ok=True)

        def copy_writable(src_file, dst_file):
            shutil.copyfile(src_file, dst_file)
            os.chmod(dst_file, 0o755 if os.access(src_file, os.X_OK) else 0o644)

        # 1. Standard skills directories (skills/ takes precedence over .agents/skills/)
        for base in (src / "skills", src / ".agents" / "skills"):
            if not base.is_dir():
                continue
            for entry in sorted(base.iterdir()):
                if entry.is_dir() and (entry / "SKILL.md").is_file():
                    dst = out_skills / entry.name
                    if not dst.exists():
                        shutil.copytree(entry, dst, copy_function=copy_writable)

        # 2. Single-skill repository (root SKILL.md)
        if (src / "SKILL.md").is_file() and not (out_skills / plugin_name).exists():
            dst = out_skills / plugin_name
            dst.mkdir(parents=True, exist_ok=True)
            copy_writable(src / "SKILL.md", dst / "SKILL.md")
            for sub in ("scripts", "examples", "resources", "references"):
                if (src / sub).is_dir():
                    shutil.copytree(src / sub, dst / sub, copy_function=copy_writable)

        # 3. Fallback: convert commands/*.md and commands/*.toml into skills/<cmd>/SKILL.md
        commands_dir = src / "commands"
        if commands_dir.is_dir():
            for path in sorted(commands_dir.iterdir()):
                if not path.is_file() or path.suffix not in (".md", ".toml"):
                    continue
                cmd = path.stem.lower()
                dst = out_skills / cmd
                if dst.exists():
                    continue
                default_desc = f"Slash command /{cmd} from {plugin_name}"
                text = path.read_text(encoding="utf-8-sig")
                if path.suffix == ".md":
                    m = re.match(r"^---\r?\n(?:(.*?)\r?\n)?---[ \t]*(?:\r?\n(.*))?$", text, re.DOTALL)
                    if m:
                        fm, body = m.group(1) or "", m.group(2) or ""
                        lines = [fm.rstrip()] if fm.strip() else []
                        if not re.search(r"(?m)^name\s*:", fm):
                            lines.append(f"name: {json.dumps(cmd)}")
                        if not re.search(r"(?m)^description\s*:", fm):
                            lines.append(f"description: {json.dumps(default_desc)}")
                        skill_md = "---\n" + "\n".join(lines) + "\n---\n" + body.lstrip("\r\n")
                    else:
                        skill_md = (
                            f"---\nname: {json.dumps(cmd)}\ndescription: {json.dumps(default_desc)}\n---\n\n"
                            + text.lstrip()
                        )
                else:
                    data = tomllib.loads(text)
                    prompt = data.get("prompt")
                    if not isinstance(prompt, str) or not prompt.strip():
                        continue
                    raw_desc = data.get("description")
                    desc = raw_desc.strip() if isinstance(raw_desc, str) and raw_desc.strip() else default_desc
                    skill_md = (
                        f"---\nname: {json.dumps(cmd)}\ndescription: {json.dumps(desc)}\n---\n\n"
                        + prompt.lstrip()
                    )
                dst.mkdir(parents=True, exist_ok=True)
                (dst / "SKILL.md").write_text(skill_md, encoding="utf-8")

        if not list(out_skills.glob("*/SKILL.md")):
            raise SystemExit(f"antigravity plugin '{plugin_name}' produced no skills")

        # 4. Synthesize clean plugin.json metadata from upstream manifests
        meta = {"name": plugin_name}
        manifest_paths = (
            src / "plugin.json",
            src / ".antigravity-plugin" / "plugin.json",
            src / ".gemini-plugin" / "plugin.json",
            src / ".claude-plugin" / "plugin.json",
            src / "gemini-extension.json",
            src / "package.json",
        )
        parsed = []
        for p in manifest_paths:
            if p.is_file():
                try:
                    obj = json.loads(p.read_text(encoding="utf-8"))
                    if isinstance(obj, dict):
                        parsed.append(obj)
                except Exception:
                    pass

        for key in ("description", "displayName"):
            for obj in parsed:
                val = obj.get(key)
                if isinstance(val, str) and val.strip():
                    meta[key] = val.strip()
                    break

        for obj in parsed:
            hp = obj.get("homepage")
            if isinstance(hp, str) and hp.strip().startswith("https://"):
                meta["homepage"] = hp.strip()
                break

        version = ""
        for obj in parsed:
            ver = obj.get("version")
            if isinstance(ver, str) and ver.strip():
                version = ver.strip().lstrip("v")
                break
        if not version and pin_version.strip():
            version = pin_version.strip().lstrip("v")
        meta["version"] = version or "0.0.0"

        (out / "plugin.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
      '';
      mkAntigravityPlugin =
        name: pin:
        let
          src = (pin { inherit pkgs; }).outPath;
          pinVersion = pin.version or "";
        in
        pkgs.runCommandLocal "antigravity-plugin-${name}"
          {
            passthru.builder = buildAntigravityPlugin;
          }
          ''
            ${lib.getExe pkgs.python3} ${buildAntigravityPlugin} ${lib.escapeShellArg name} ${src} "$out" ${lib.escapeShellArg pinVersion}
            HOME="$(mktemp -d)" ${lib.getExe pkgs.google-antigravity-cli} plugin validate --strict "$out"
          '';
    in
    {
      ".gemini/config/skills" = {
        source = ../dotfiles/skills;
        recursive = true;
      };
    }
    // lib.mapAttrs' (
      name: pin:
      lib.nameValuePair ".gemini/config/plugins/${name}" {
        source = mkAntigravityPlugin name pin;
        recursive = true;
      }
    ) antigravityPlugins;

  # Merge declarative Nix-backed MCP servers into `~/.gemini/config/mcp_config.json`
  # as a regular 0600 file rather than a read-only HM symlink: `.gemini` is persisted
  # and Antigravity rewrites `mcp_config.json` in place when UI/OAuth MCP servers are
  # added, which otherwise breaks `home-manager-fumoctl.service` on reboot once
  # `mcp_config.json.backup` already exists.
  home.activation.antigravityMcpConfig =
    let
      # Run npm MCP servers via Bun's `bunx` with a 7-day release cooldown (604800s)
      # to guard against newly published supply-chain compromises.
      # and `pkgs.nodejs` on PATH so `#!/usr/bin/env node` bins execute on Node.
      bunxMcp = pkgs.writeShellApplication {
        name = "bunx-mcp";
        runtimeInputs = [
          pkgs.unstable.bun
          pkgs.nodejs
        ];
        text = ''
          exec bunx --silent --ignore-scripts --minimum-release-age 604800 "$@"
        '';
      };
      declarativeMcp = (pkgs.formats.json { }).generate "antigravity-mcp.json" {
        mcpServers = {
          context7 = {
            command = lib.getExe bunxMcp;
            args = [ "@upstash/context7-mcp@latest" ];
          };
          dbcode = {
            command = lib.getExe pkgs.bash;
            args = [
              "-c"
              ''shopt -s nullglob; bins=("$HOME"/.vscode-oss/extensions/dbcode.dbcode-*/out/cli/dbcode); if [ "''${#bins[@]}" -eq 0 ]; then echo "dbcode VSCodium extension not installed" >&2; exit 1; fi; exec ${lib.getExe pkgs.nodejs} "$(printf '%s\n' "''${bins[@]}" | ${pkgs.coreutils}/bin/sort -V | ${pkgs.coreutils}/bin/tail -n1)" mcp''
            ];
          };
          playwright = {
            command = lib.getExe bunxMcp;
            args = [
              "@playwright/mcp@latest"
              "--browser"
              "chromium"
            ];
          };
          rea = {
            command = lib.getExe bunxMcp;
            args = [
              "rea-agents@latest"
              "--mcp"
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
      (
        set -euo pipefail
        mcpCfg="$HOME/.gemini/config/mcp_config.json"
        mkdir -p "$(dirname "$mcpCfg")"
        if [ -e "$mcpCfg" ] && [ ! -L "$mcpCfg" ]; then
          if [ ! -f "$mcpCfg" ] || ! ${jqBin} -e 'type == "object"' "$mcpCfg" >/dev/null 2>&1; then
            echo "antigravityMcpConfig: $mcpCfg is not a valid JSON object; refusing to overwrite" >&2
            exit 1
          fi
        fi
        # Names of servers this block managed last time; any no longer declared get pruned.
        stateFile="$HOME/.gemini/config/.nix-managed-mcp.json"
        oldNames='[]'
        if [ -f "$stateFile" ] && ${jqBin} -e 'type == "array"' "$stateFile" >/dev/null 2>&1; then
          oldNames="$(cat "$stateFile")"
        fi
        newNames="$(${jqBin} -c '.mcpServers | keys' "${declarativeMcp}")"
        tmpCfg="$(mktemp "''${mcpCfg}.tmp.XXXXXX")"
        trap 'rm -f "$tmpCfg"' EXIT
        chmod 600 "$tmpCfg"
        if [ -f "$mcpCfg" ] && [ ! -L "$mcpCfg" ]; then
          ${jqBin} -s --argjson old "$oldNames" '
            (.[0] + .[1]) + { mcpServers: (((.[0].mcpServers // {}) | with_entries(select(.key as $k | ($old | index($k)) | not))) + .[1].mcpServers) }
          ' "$mcpCfg" "${declarativeMcp}" > "$tmpCfg"
        else
          cat "${declarativeMcp}" > "$tmpCfg"
        fi
        mv -f "$tmpCfg" "$mcpCfg"
        rm -f "$mcpCfg.backup"
        printf '%s\n' "$newNames" > "$stateFile"
      )
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
