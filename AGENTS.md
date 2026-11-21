# AGENTS.md — Ultix

Architecture reference and invariants for Ultix — a modular **NixOS (`nixos-26.05`) flake** for `ultix-desktop` and `ultix-laptop` (`x86_64-linux`). Leaf values (packages, keybinds, widgets, MIME, themes) change often; read `.nix` files directly. Keep `AGENTS.md` `< 16000` B (`<user_rules>` cap: 16 KiB).

## Default Agent Mode: Ponytail (Mandatory)

Agents here **MUST always activate and follow `ponytail` (`full` default)** unless the user asks for `lite`, `ultra`, or opts out (`"stop ponytail"` / `"normal mode"`):

- **Before coding**: Read `~/.gemini/config/plugins/ponytail/skills/ponytail/SKILL.md`; if absent locally (e.g. another machine/setup), fetch/read `https://raw.githubusercontent.com/DietrichGebert/ponytail/main/skills/ponytail/SKILL.md`, falling back to these inline rules if offline.
- **Smallest complete change**: Solve the whole task with the shortest clear diff. Reuse repo/NixOS patterns; zero unrequested abstractions, wrappers, options, or "for later" code; update affected callers, checks, and docs; never cut security, validation, or data-loss guards.
- **Mandatory runtime/script tests**: **Any new or modified runtime/procedural code that has even a remote chance of not being caught by Nix evaluation or rebuilds (Bash/Python scripts, `jq`/`sed`/`awk` pipelines, activation hooks, systemd script blocks, CLI wrappers) MUST include an automated test in `checks.x86_64-linux.scripts` (`flake.nix`)** and pass `nix build --no-link .#checks.x86_64-linux.scripts` before completion.
- **Shortcuts & closeout**: Mark known-limit shortcuts `# shortcut: <limit>, <when to upgrade>`, and **end replies with 1–2 lines naming what was skipped/not checked and any risk**.

## 1. Repository Layout & Module Graph

```text
Ultix/
├── flake.nix           # Inputs, caches, mkHost, checks.x86_64-linux.scripts
├── flake.lock          # Locked inputs (commit with flake.nix)
├── npins/              # sources.json + default.nix: pinned plugin repos
├── .sops.yaml          # Post-quantum Age recipient rules
├── secrets/secrets.yaml # SOPS-encrypted user/API/SSH/PGP secrets
├── hosts/
│   ├── common.nix      # Nix/nh, overlays, boot/sysctl, limits, locale/tz, user+HM
│   ├── impermanence.nix # Initrd Btrfs @ wipe + /persist paths
│   ├── networking.nix  # nftables, NetworkManager, resolved (DoT/DNSSEC), VPN
│   ├── desktop-env.nix # Umbriel, Noctalia, Greeter+PAM, PipeWire, portals, KF6/KIO
│   ├── gaming.nix      # Graphics, Proton sync, gs-run, bottles-winetricks
│   ├── containers.nix  # Docker, rootless Podman, shared OCI, libvirt/KVM
│   ├── packages.nix    # CLI tools, direnv, gnupg SSH agent, nix-ld
│   └── {desktop,laptop}/ # {default,hardware-configuration,disko,containers}.nix
├── home/
│   ├── default.nix     # HM entry, identity, gnome-keyring
│   ├── secrets.nix     # sops-nix secrets, shell env, PGP import
│   ├── noctalia.nix    # {noctalia,umbriel}.settings, GTK/Qt/cursor
│   ├── shell.nix       # Zsh, Git signing, 0600 ~/.ssh/config, Konsole
│   ├── apps.nix        # Apps, Antigravity MCP merge & npins plugins
│   ├── flatpak.nix     # nix-flatpak remotes/apps, timer, overrides
│   └── mime.nix        # xdg.mimeApps + KSycoca rebuild hook
└── dotfiles/           # Avatar, wallpapers, fastfetch, local skills/
```

### How a Host Evaluates
1. **`flake.nix` (`mkHost`)**: `nixosSystem` (`x86_64-linux`, `specialArgs = { inherit inputs; }`) with `disko`, `home-manager`, `chaotic.nixosModules.{nyx-cache,nyx-overlay,nyx-registry}`, `./hosts/{desktop,laptop}`.
2. **`hosts/{desktop,laptop}/default.nix`**: Imports `[ ../common.nix ../containers.nix ./containers.nix ./hardware-configuration.nix ./disko.nix ]` + HW, kernel, Limine, `hostName`.
3. **`hosts/common.nix`**: Imports `./{impermanence,networking,desktop-env,gaming,packages}.nix` and wires HM (`useGlobalPkgs`/`useUserPackages = true`, `extraSpecialArgs = { inherit inputs; }`, `backupFileExtension = "backup"`, `users.fumoctl = import ../home`).
4. **Third-party modules** (`impermanence`, `noctalia{,-greeter}`, `umbriel`, `windscribe-nixos`, `sops-nix`, `nix-flatpak`) import in their domain `.nix`, never `flake.nix`.

## 2. Hosts & Target Constraints

| Host | Dir | Hardware | Kernel & Boot |
| --- | --- | --- | --- |
| **`ultix-desktop`** | `hosts/desktop/` | AMD Zen 4, AMD dGPU (`amdgpu`, `amdgpu.runpm=0`) | `linuxPackages_cachyos-lto-znver4` (`_latest` fallback), Limine |
| **`ultix-laptop`** | `hosts/laptop/` | TUXEDO, AMD iGPU + NVIDIA open PRIME, `tuxedo-{drivers,rs}`, `captive-browser` (Brave) | `linuxPackages_xanmod`, Limine |

- **Single arch (`x86_64-linux`) & user (`fumoctl`)**: No `eachSystem`/`aarch64` conditionals unless asked. UID `1000`, group `fumoctl`, `linger = true`, `autoSubUidGidRange = true`; shared HM + `/persist`, host diffs gated in `hosts/{desktop,laptop}/*.nix`.

## 3. Inputs, Overlays & Nix Daemon Mechanics

- **Unstable & HM `pkgs`**: `hosts/common.nix` overlays `inputs.nixpkgs-unstable` as `pkgs.unstable` (`allowUnfree = true`, `android_sdk.accept_license = true`); never re-import it or set `nixpkgs.*` in `home/*.nix` (`useGlobalPkgs = true`).
- **`follows` & caches**: Only `home-manager` sets `nixpkgs.follows = "nixpkgs"`; others keep locked `nixpkgs` so `{noctalia,umbriel}.cachix.org`, `nyx-cache.chaotic.cx`, and Chaotic kernel/overlay pairs hit caches. Duplicate `substituters` (`flake.nix` `nixConfig` + `hosts/common.nix` `nix.settings`) are harmless — never `mkForce`.
- **Pruning (`nh`)**: `programs.nh` (`flake = "/home/fumoctl/Projects/Ultix"`, `clean.enable = true`) owns rebuilds + weekly GC; never set `nix.gc.automatic`. `limine.maxGenerations` bounds `/boot`.

## 4. Storage, Impermanence & Credential Invariants

- **Disko & `hardware-configuration.nix`**: `hosts/<dir>/disko.nix` defines GPT → LUKS2 (`crypted`) → Btrfs (`@`, `@persist`, `@nix`, `@log`, `@snapshots`, `@swap` + 32G `/.swapvol/swapfile`) on `/dev/disk/by-partlabel/disk-main-*`; `hardware-configuration.nix` has **only kernel modules and zero `fileSystems`/`swapDevices`**.
- **Ephemeral `/` wipe (`hosts/impermanence.nix`)**: `/{persist,nix,var/log}` set `neededForBoot = true`. Initrd `impermanence-clean-root` (`requires`/`after = [ "dev-mapper-crypted.device" ]`, `before = [ "sysroot.mount" ]`) mounts `subvolid=5`, clears `ro` on `@`/`@/*`, runs `btrfs subvolume delete -R /btrfs_tmp/@`, and recreates `@`. **Unlisted `/` or `$HOME` state wipes every reboot** — register it in `hosts/impermanence.nix`.
- **Mutable files & credentials**:
  1. **KDE `QSaveFile` (`*rc`, `*staterc`)**: Atomic renames break bind-mounts/dangling symlinks — use `{ file = "..."; method = "symlink"; }` + `tmpfiles.rules` pre-creating `/persist/home/fumoctl/...`.
  2. **`0600` / mutable JSON**: Store symlinks are `0444`; materialize/merge real `0600` files in `home.activation` (`entryAfter [ "writeBoundary" "linkGeneration" ]`), e.g. `sshConfig` (`~/.ssh/config`, `home/shell.nix`) and `antigravityMcpConfig` (`home/apps.nix`).
  3. **Passwords & `userdbd`**: `mutableUsers = false`, `hashedPasswordFile = "/persist/passwords/fumoctl"` (never outside `/persist` or committed); `systemd.override { withUserDb = false; }` + `services.userdbd.enable = mkForce false`.

## 5. Desktop Session, Portals & Toolkit Glue

- **`{umbriel,noctalia}` & Greeter**: `programs.{umbriel,noctalia}.settings` + `noctalia-greeter.settings` serialize from Nix and run `{noctalia,umbriel} config validate` (custom Noctalia widgets also need `plugins.enabled`). `programs.umbriel.enable = true` wires `start-umbriel` → `umbriel.service` → `graphical-session.target` → HM `noctalia.service` (`noctalia.systemd.enable = true`); **never** put `"noctalia"` in `umbriel.settings.general.autostart` (no system unit). GUI edits write `~/.local/state/noctalia/settings.toml` (overrides `config.toml`); Greeter layers `/var/lib/noctalia-greeter/sync.toml` (`passwordless-sync-users = [ "fumoctl" ]`).
- **Theme & avatar**: Keep `umbriel.settings.include.optional.files = [ "noctalia.toml" ]` exact so Noctalia writes `~/.config/umbriel/noctalia.toml` (not read-only `config.toml`). `$HOME` is `0700`, so `tmpfiles.rules` links 1:1 `dotfiles/.fumoctl.jpg` → `/var/lib/AccountsService/{icons,users}/fumoctl`.
- **Portals (`hosts/desktop-env.nix`)**: `xdg.portal.config.umbriel` overrides `config.common` (`XDG_CURRENT_DESKTOP=Umbriel`). `portal-umbriel` only covers Screenshot/ScreenCast/InputCapture; **`default = [ "umbriel" "gtk" ]` must keep `"gtk"`** for `Settings` (GTK4 dark mode), with `{File,App}Chooser = "kde"`.
- **KDE/Qt (no Plasma)**: `kdeXdgMenus` builds `umbriel-applications.menu` (`disallowedReferences = [ plasma-workspace ]`); `/etc/xdg/{kdeglobals,konsolerc}` (`/share/konsole` linked) sets defaults. `home/noctalia.nix` `mkForce`-merges `${config.home.profileDirectory}` + `/run/current-system/sw` in `QT_PLUGIN_PATH`/`QML2_IMPORT_PATH` (+ `NIX_XDG_DESKTOP_PORTAL_DIR`) for KF6 KIO/thumbnail/archive plugins; `nixos-rebuild-sycoca` + `rebuildKdeSycoca` (`home/mime.nix`, `XDG_MENU_PREFIX="umbriel-"`) bypass `1970-01-01` mtimes.
- **Keyring & Flatpaks**: `greetd` PAM unlocks `gnome-keyring` (`components = [ "pkcs11" "secrets" ]`, `home/default.nix`); **never add `"ssh"`** (`gnupg.agent.enableSSHSupport = true` owns `SSH_AUTH_SOCK`). `nix-flatpak` (`home/flatpak.nix`) exposes `/nix/store` + GTK/icon dirs ro; Qt Flatpaks unset `QT_PLUGIN_PATH`, `LD_LIBRARY_PATH`, `QT_QPA_PLATFORM_PLUGIN_PATH`.

## 6. Gaming, Containers & Networking Subsystems

- **Gaming (`hosts/gaming.nix`)**: `gs-run` reads `umbriel outputs --json` (geometry/refresh/HDR/VRR), strips Steam `LD_PRELOAD`/`LD_LIBRARY_PATH` + sets `DISABLE_LSFGVK=1` on outer `gamescope` (restored inside), forwards `WINEPREFIX`, and wraps Wine in `gs-wine-wait` (`wineserver -w` + `gamescopereaper`); `home/noctalia.nix` sets `blur`/`shadow = false`, `opacity = 1.0` on `^(gamescope|steam_app_.*|)$`. `bottles-winetricks` (`unstable.buildFHSEnv`) seeds Proton `vkd3d` DLLs and scopes runner `LD_LIBRARY_PATH`/`WINEDLLPATH`/`GST_PLUGIN_SYSTEM_PATH_1_0` to `wine`/`wineserver` shims so host GTK4 `zenity` works. `syncSteamCompatTools` writes `~/.local/share/Steam/compatibilitytools.d/<Name>` as **real outer dirs (`.nix-managed`) of `/nix/store` symlinks** (outer symlinks pin GC-transient paths in UMU/Bottles; custom dirs stay intact).
- **Containers (`hosts/containers.nix`)**: Rootful Docker + rootless Podman (`oci-containers.backend = "podman"`); **`podman.{dockerCompat,dockerSocket.enable}` MUST stay `false`**. `podman.user = "fumoctl"` units (`hosts/{,desktop/,laptop/}containers.nix`) need `after`/`requires = [ "user@1000.service" ]` + `RequiresMountsFor` on `{/run/user/1000,/home/fumoctl/.local/share}/containers` (+ `jq` seccomp for `io_uring`). `nix-ld`, `nix-alien`, `libvirtd` back external binaries/VMs.
- **Networking & TZ (`hosts/{networking,common}.nix`)**: `NetworkManager` → `systemd-resolved` (DNSSEC + DoT, DHCP DNS ignored, `unbound` off) behind `nftables` (`checkReversePath = "loose"`). `tzupdate` (`timeZone = null`, `timer.enable = false`, VPN egress guard, `postStart`) + `activationScripts.localtime` copy `/etc/localtime` ↔ `/persist/etc/localtime` (`America/Argentina/Buenos_Aires` fallback), never symlinking into `/persist` (`systemd-timedated` `unlink()`s `/etc/localtime`).

## 7. Secrets (`sops-nix`) & Git Signing

- **Age, keyless boot & PGP**: Post-quantum `mlkem768x25519` key at `/persist/sops/fumosops.key` (`0600`, `SOPS_AGE_KEY_FILE` in `home/secrets.nix`), `.sops.yaml`, `secrets/secrets.yaml`. `sops-nix` user unit sets `ConditionPathExists` on that key for keyless installs; `sops-import-pgp.service` imports PGP; `programs.git` (`home/shell.nix`) sets `signByDefault = true`.
- **Workflows**: Edit with `sops secrets/secrets.yaml` (if `--decrypt -i`, re-encrypt and check `ENC[AES256_GCM,...]` in `git diff`); wire `sops.secrets.<name>` + `shell-secrets.sh`; re-key via `sops updatekeys secrets/secrets.yaml`.

## 8. Antigravity MCP Servers & Skills (`home/apps.nix` + `npins/`)

- **MCP (`antigravityMcpConfig`)**: Merges `declarativeMcp.mcpServers` into `0600` `~/.gemini/config/mcp_config.json` using `.nix-managed-mcp.json` (preserves UI/OAuth keys, prunes stale Nix keys, aborts on invalid JSON).
- **`bunxMcp`**: `bunx --silent --ignore-scripts --minimum-release-age 604800 "$@"` on `pkgs.unstable.bun` (`>= 1.4.4`; `1.3.13` ignores cooldown) + `nodejs` (`#!/usr/bin/env node`); keep `--silent` (JSON-RPC stdout) and no `--` before `"$@"`. `@playwright/mcp` uses persisted `~/.cache/ms-playwright` + `libgbm` in `nix-ld`; `dbcode` runs `~/.vscode-oss/extensions/dbcode.dbcode-*`; `rivalsearch` uses Streamable HTTP.
- **Skills & `npins`**: Local `<name>/SKILL.md` dirs live in `dotfiles/skills/` (`git add -N`, `.gemini/config/skills` `recursive = true`; non-skill subdirs fail checks). `npins/sources.json` (`npins {add github <owner> <repo>,update [name],remove <name>}`) loads via `(import ../npins) { }` / `pin { inherit pkgs; }`; `mkAntigravityPlugin` maps `{,.agents/}skills/*/SKILL.md`, root `SKILL.md`, or `commands/*.{md,toml}` to `~/.gemini/config/plugins/<name>/`, synthesizes `plugin.json`, fails on 0 skills, and runs `agy plugin validate --strict "$out"`.

## 9. Conventions & Placement Guide

- **Placement**: Shared OS/boot/`nh`/tz: `hosts/common.nix` (`hosts/*.nix`); host HW/kernel/GPU/SB: `hosts/{desktop,laptop}/default.nix`; state: `hosts/impermanence.nix`; WM/bar/greeter/portals/Qt/GTK: `hosts/desktop-env.nix` + `home/noctalia.nix`; CLI/`nix-ld`/GPG: `hosts/packages.nix`; MCP/skills/plugins: `home/apps.nix`, `dotfiles/skills/`, `npins/`; apps/shell/Flatpaks/MIME: `home/{apps,shell,flatpak,mime}.nix`; OCI: `hosts/{,desktop/,laptop/}containers.nix`; secrets: `secrets/secrets.yaml` + `home/secrets.nix`; script tests: `flake.nix` (`checks.x86_64-linux.scripts`).
- **Code, Tests & Git**: Run `nixfmt $(git ls-files '*.nix')`. Keep module args minimal (`inputs` via `{,extra}SpecialArgs`), use `lib.mkDefault`, `${pkgs.foo}/bin/foo` or `lib.getExe` (never `/run/current-system/sw/bin/...`), and `entryAfter [ "writeBoundary" ]` in `home.activation`. Add/update a test in `checks.x86_64-linux.scripts` for any new/modified script, `jq`/`sed`/`awk` pipeline, wrapper, or activation/systemd hook Nix eval/rebuilds could miss. Keep inline "why" comments, `stateVersion = "26.05"`, `git add -N` new files before eval, and short lowercase commits (no Conventional Commits/AI trailers; commit `flake.lock`/`npins/sources.json` with updates).

## 10. Verification Checklist

Evaluate both hosts and build `checks.x86_64-linux.scripts` (mandatory for any runtime/script/hook logic) before completion:

```bash
git status --short && git diff secrets/ && test "$(wc -c < AGENTS.md)" -lt 16000
nixfmt --check $(git ls-files '*.nix')
nix eval --raw .#nixosConfigurations.ultix-desktop.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.ultix-laptop.config.system.build.toplevel.drvPath
nix build --no-link .#checks.x86_64-linux.scripts # mandatory for scripts/hooks; or `nix flake check`
nh os switch                                      # `boot` for initrd/disko/impermanence/bootloader
```

> **Sandboxes**: Use `XDG_CACHE_HOME=$(mktemp -d) nix --offline ...` if `fetcher-cache-v4.sqlite` is read-only.
