# AGENTS.md — Ultix

Architecture reference, invariants, and workflow rules for AI coding agents and contributors working in this repository.

Ultix is a modular, declarative **NixOS (`nixos-26.05`) flake** for two `x86_64-linux` machines (`ultix-desktop` and `ultix-laptop`). Individual user packages, keybinds, widgets, MIME mappings, and themes evolve frequently — read the relevant `.nix` module directly rather than assuming leaf values. This guide focuses on **structural wiring, non-obvious invariants, and operational traps**.

---

## 1. Repository Layout & Module Graph

```text
Ultix/
├── flake.nix                       # Inputs, binary caches, `mkHost` → nixosConfigurations.<host>
├── flake.lock                      # Locked input revisions (commit alongside flake.nix changes)
├── .sops.yaml                      # Post-quantum Age recipient rules for SOPS
├── secrets/secrets.yaml            # SOPS-encrypted user/API/SSH/PGP secrets
├── hosts/
│   ├── common.nix                  # Shared hub: Nix/nh, overlays, boot/sysctl, limits, locale, user + HM wiring
│   ├── impermanence.nix            # Initrd Btrfs `@` wipe service + `/persist` state declarations
│   ├── networking.nix              # nftables, NetworkManager, systemd-resolved (DoT/DNSSEC), VPN module
│   ├── desktop-env.nix             # Umbriel, Noctalia, Noctalia Greeter + PAM, PipeWire, portals, fonts, KF6/KIO glue
│   ├── gaming.nix                  # Graphics, Steam/Proton activation, `gs-run` & `bottles-winetricks` wrappers
│   ├── containers.nix              # Rootful Docker, rootless Podman, shared OCI containers, libvirt/KVM
│   ├── packages.nix                # Shared system CLI/admin tools, `direnv`, `gnupg` SSH agent, `nix-ld`
│   ├── desktop/                    # Host `ultix-desktop`: default.nix, hardware-configuration.nix, disko.nix, containers.nix
│   └── laptop/                     # Host `ultix-laptop`:  default.nix, hardware-configuration.nix, disko.nix, containers.nix
├── home/
│   ├── default.nix                 # Home Manager entry point, identity, gnome-keyring user service
│   ├── secrets.nix                 # `sops-nix` HM module, secret declarations, shell env template, PGP import unit
│   ├── noctalia.nix                # Pure-Nix `programs.{noctalia,umbriel}.settings`, GTK/Qt/cursor integration
│   ├── shell.nix                   # Interactive shell, Git signing, `0600` SSH config copy, terminal profile
│   ├── apps.nix                    # User GUI/dev packages & mutable JSON config merge hooks
│   ├── flatpak.nix                 # Declarative `nix-flatpak` remotes/apps, update timer, sandbox `overrides`
│   └── mime.nix                    # `xdg.mimeApps` associations + KSycoca cache rebuild hook
└── dotfiles/                       # Static assets (avatar, wallpapers, fastfetch config, agent skills)
```

### How a Host Evaluates

1. **`flake.nix` (`mkHost`)** instantiates `nixpkgs.lib.nixosSystem` for `x86_64-linux` with `specialArgs = { inherit inputs; }` and loads `disko`, `home-manager`, `chaotic.nixosModules.{nyx-cache,nyx-overlay,nyx-registry}`, plus `./hosts/desktop` or `./hosts/laptop`.
2. **`hosts/{desktop,laptop}/default.nix`** imports `[ ../common.nix ../containers.nix ./containers.nix ./hardware-configuration.nix ./disko.nix ]` and sets machine-specific hardware, kernel, bootloader, and `networking.hostName`.
3. **`hosts/common.nix`** imports `[ ./impermanence.nix ./networking.nix ./desktop-env.nix ./gaming.nix ./packages.nix ]` and wires Home Manager (`useGlobalPkgs = true`, `useUserPackages = true`, `extraSpecialArgs = { inherit inputs; }`, `backupFileExtension = "backup"`, `users.fumoctl = import ../home`).
4. **Third-party flake modules** (`impermanence`, `noctalia`, `noctalia-greeter`, `umbriel`, `windscribe-nixos`, `sops-nix`, `nix-flatpak`) are imported inside the specific domain file that configures them rather than in `flake.nix`.

---

## 2. Hosts & Target Constraints

| Flake Output / Hostname | Directory | Hardware Profile | Kernel & Boot |
| :--- | :--- | :--- | :--- |
| **`ultix-desktop`** | `hosts/desktop/` | AMD Zen 4 desktop, discrete AMD GPU (`amdgpu`, `amdgpu.runpm=0`) | `linuxPackages_cachyos-lto-znver4` (fallback `linuxPackages_latest`), Limine |
| **`ultix-laptop`** | `hosts/laptop/` | TUXEDO laptop, AMD iGPU + NVIDIA open PRIME offload, `tuxedo-drivers` + `tuxedo-rs`, `captive-browser` | `linuxPackages_xanmod`, Limine |

- **Single architecture (`x86_64-linux`)**: Both hosts share one system string. Do not introduce `flake-utils.eachSystem` or `aarch64` conditionals unless explicitly requested.
- **Single primary user (`fumoctl`)**: UID `1000`, primary group `fumoctl`, `linger = true`, `autoSubUidGidRange = true`. Both machines share the same Home Manager profile and `/persist` layout; gate machine differences in `hosts/{desktop,laptop}/*.nix`.

---

## 3. Inputs, Overlays & Nix Daemon Mechanics

- **Unstable packages**: `hosts/common.nix` overlays `inputs.nixpkgs-unstable` onto `pkgs.unstable` (with `allowUnfree = true` and `android_sdk.accept_license = true`). Always reference unstable packages as `pkgs.unstable.<pkg>` (or `unstable.<pkg>` inside `with pkgs;`); never re-import `inputs.nixpkgs-unstable` in modules.
- **Global `pkgs` in Home Manager**: Because `home-manager.useGlobalPkgs = true` is active, overlays defined in `hosts/common.nix` are automatically available across `home/*.nix`, and `home/*.nix` must not set `nixpkgs.*` options.
- **`inputs.*.follows` discipline**: Only `home-manager` sets `inputs.nixpkgs.follows = "nixpkgs"`. Other flake inputs intentionally retain their own locked `nixpkgs` revisions so upstream binary caches (`noctalia.cachix.org`, `umbriel.cachix.org`, `nyx-cache.chaotic.cx`) hit cleanly without compiling compositors or kernels locally, and Chaotic's overlay/kernel pairing stays intact. Do not add `follows` overrides unless asked.
- **Substituter duplication**: Binary caches are declared in both `flake.nix` (`nixConfig`) and `hosts/common.nix` (`nix.settings`). NixOS merges `substituters` additively with defaults, producing harmless duplicates in `/etc/nix/nix.conf` — do not `mkForce` them away.
- **Store pruning via `nh`**: `programs.nh` (`flake = "/home/fumoctl/Projects/Ultix"`) manages rebuilds and weekly store/generation cleanup (`programs.nh.clean.enable = true`). Do **not** enable `nix.gc.automatic` alongside `nh.clean` (triggers a NixOS module conflict warning). Boot entries on `/boot` are bounded separately by `boot.loader.limine.maxGenerations`.

---

## 4. Storage, Impermanence & Credential Invariants

### Disko & `hardware-configuration.nix`
- Each host defines its full GPT → LUKS2 (`crypted`) → Btrfs layout (`@`, `@persist`, `@nix`, `@log`, `@snapshots`, `@swap` with 32G swapfile at `/.swapvol/swapfile`) in `hosts/<dir>/disko.nix`.
- Disko mounts partitions by GPT partlabel (`/dev/disk/by-partlabel/disk-main-*`). `hardware-configuration.nix` intentionally contains **only kernel module declarations and zero `fileSystems` / `swapDevices`**. Never add filesystem mounts there.

### Ephemeral `/` Wipe & `/persist` (`hosts/impermanence.nix`)
- `/persist`, `/nix`, and `/var/log` set `neededForBoot = true`.
- During initrd (`after = [ "dev-mapper-crypted.device" ]`, `before = [ "sysroot.mount" ]`), `boot.initrd.systemd.services.impermanence-clean-root` mounts `subvolid=5` of `/dev/mapper/crypted`, recursively deletes any nested subvolumes inside `@`, deletes `@`, and creates a blank `@`.
- **Any state in `/` or `/home/fumoctl` not listed in `environment.persistence."/persist"` (or linked from `/nix/store`) is destroyed on every reboot.** Whenever adding a stateful system service or user application, declare its state paths in `hosts/impermanence.nix`.

### Persistence & Mutable-File Patterns
1. **KDE / `QSaveFile` config files (`*rc`, `*staterc`)**: Qt's `QSaveFile` writes to a temp file and `rename()`s over the target, which fails across bind-mounted individual files and refuses to write through dangling symlinks. Persist single KConfig files with `{ file = "..."; method = "symlink"; }` **and** pre-create the backing file in `/persist/home/fumoctl/...` via `systemd.tmpfiles.rules`.
2. **Files mutated in place or requiring strict mode bits**: Home Manager symlinks point into `/nix/store` (`0444`, read-only). When a tool requires a real `0600` file (e.g. `~/.ssh/config` in `home/shell.nix`) or rewrites its own JSON config at runtime inside a persisted directory (e.g. `home.activation.antigravityMcpConfig` in `home/apps.nix`), materialize/merge the regular file via `onChange` or `home.activation` (`lib.hm.dag.entryAfter [ "writeBoundary" ... ]`) using `install -m 600` instead of linking directly.
3. **Immutable user credentials**: `users.mutableUsers = false` and `users.users.fumoctl.hashedPasswordFile = "/persist/passwords/fumoctl"`. Never point `hashedPasswordFile` outside `/persist` and never commit password hashes.
4. **`userdbd` disabled**: `hosts/common.nix` overrides `systemd` with `withUserDb = false` and sets `services.userdbd.enable = lib.mkForce false` intentionally.

---

## 5. Desktop Session, Portals & Toolkit Glue

### Pure-Nix Compositor, Shell & Greeter (`hosts/desktop-env.nix` + `home/noctalia.nix`)
- **No external `.toml` files**: Umbriel (`programs.umbriel.settings`), Noctalia (`programs.noctalia.settings`), and Noctalia Greeter (`services.displayManager.noctalia-greeter.settings`) serialize directly from Nix attrsets and run upstream config validation (`noctalia config validate` / `umbriel config validate`). If enabling custom Noctalia widget plugins, ensure the plugin ID is also listed in `plugins.enabled` so validation succeeds.
- **Systemd session startup**: `programs.umbriel.enable = true` (NixOS) installs `start-umbriel` and `umbriel.service`, which exports the Wayland environment and activates `graphical-session.target`, starting Home Manager's `noctalia.service` (`programs.noctalia.systemd.enable = true`). **Never** add `"noctalia"` to `programs.umbriel.settings.general.autostart` (spawns a duplicate bar/shell), and do not assume a system-level `noctalia.service` exists.
- **Runtime overrides win over Nix**: GUI edits in Noctalia write to `~/.local/state/noctalia/settings.toml` (persisted), overriding keys in `~/.config/noctalia/config.toml`. Noctalia Greeter similarly layers `/var/lib/noctalia-greeter/sync.toml` (populated via `passwordless-sync-users = [ "fumoctl" ]`). Check those persisted state files whenever a declarative change appears ignored.
- **Dynamic Umbriel theme include**: Keep `programs.umbriel.settings.include.optional.files = [ "noctalia.toml" ]` as that exact literal string so Noctalia's `umbriel` template hook writes `~/.config/umbriel/noctalia.toml` without attempting to mutate the read-only Home Manager symlink `~/.config/umbriel/config.toml`.
- **Login portrait**: Because `/home/fumoctl` is `0700`, `greeter` cannot read `$HOME/.fumoctl.jpg`. `hosts/desktop-env.nix` links `dotfiles/.fumoctl.jpg` into `/var/lib/AccountsService/{icons,users}/fumoctl` via `systemd.tmpfiles.rules` (keep `dotfiles/.fumoctl.jpg` 1:1 square for full-resolution avatar decoding).

### XDG Portals (`hosts/desktop-env.nix`)
- `xdg.portal.config.umbriel` overrides `config.common` for **every** portal interface when `XDG_CURRENT_DESKTOP=Umbriel`.
- `xdg-desktop-portal-umbriel` only implements Screenshot, ScreenCast, and InputCapture. **`default = [ "umbriel" "gtk" ]` must keep `"gtk"`** so `org.freedesktop.portal.Settings` stays registered (otherwise GTK4/libadwaita apps lose dark-mode detection). `FileChooser` and `AppChooser` explicitly route to `"kde"`.

### Standalone KDE / Qt Integration (No Plasma Desktop)
- **Menu spec without Plasma bloat**: `kdeXdgMenus` in `hosts/desktop-env.nix` extracts `applications.menu` (`umbriel-applications.menu`) and `.directory` metadata with `disallowedReferences = [ pkgs.kdePackages.plasma-workspace ]` so Dolphin/KService resolves application categories without pulling Plasma into the system closure.
- **Cascading KDE defaults**: System defaults live in `/etc/xdg/kdeglobals` and `/etc/xdg/konsolerc` (with `/share/konsole` in `environment.pathsToLink`), leaving `~/.config/*` and `~/.local/share/konsole` writable.
- **Qt plugin path merge**: Home Manager's `qt` module writes `QT_PLUGIN_PATH` / `QML2_IMPORT_PATH` with only the user profile, masking system packages. `home/noctalia.nix` `mkForce`-combines `${config.home.profileDirectory}` and `/run/current-system/sw` (plus `NIX_XDG_DESKTOP_PORTAL_DIR`) so KF6 apps discover system-wide KIO workers, thumbnailers, and archive plugins.
- **KSycoca cache**: Nix store `1970-01-01` timestamps stall incremental `ksycoca6` updates; `nixos-rebuild-sycoca` (pre-session user service) and `home.activation.rebuildKdeSycoca` (`home/mime.nix`, `XDG_MENU_PREFIX="umbriel-"`) force clean rebuilds.

### Keyring vs SSH Agent
- `greetd` PAM unlocks `gnome-keyring` at login, and `home/default.nix` runs `services.gnome-keyring` with `components = [ "pkcs11" "secrets" ]`.
- **Never add `"ssh"` to `gnome-keyring` components**: `programs.gnupg.agent.enableSSHSupport = true` (`hosts/packages.nix`) owns `SSH_AUTH_SOCK`.

### Flatpak Sandboxes (`home/flatpak.nix`)
- System `services.flatpak.enable = true` (`hosts/desktop-env.nix`) pairs with `nix-flatpak` in `home/flatpak.nix`.
- Global `services.flatpak.overrides` grant read-only access to `/nix/store` and XDG GTK/icon dirs so host themes/cursors work inside Flatpaks; apps bundling conflicting Qt runtimes must unset leaked `QT_PLUGIN_PATH` / `LD_LIBRARY_PATH` in per-app `overrides`.

---

## 6. Gaming, Containers & Networking Subsystems

### Gaming Wrappers & Proton Materialization (`hosts/gaming.nix`)
- **`gs-run` & `gs-wine-wait`**: Custom Umbriel-aware `gamescope` launcher that queries `umbriel outputs --json` for focused monitor geometry/refresh/HDR/VRR, strips Steam's `LD_PRELOAD`/`LD_LIBRARY_PATH` and sets `DISABLE_LSFGVK=1` on the outer `gamescope` compositor while restoring them for the inner game process, and wraps Wine launches with `wineserver -w` + `gamescopereaper` child cleanup.
- **Compositor direct scanout**: `home/noctalia.nix` matches `app_id = "^(gamescope|steam_app_.*|)$"` (Wayland `gamescope` clears `app_id` to `""`) with `blur = false`, `shadow = false`, and `opacity = 1.0`. Preserve this rule when editing window rules so high-refresh games are not forced through blur passes.
- **`bottles-winetricks`**: Multi-arch `pkgs.unstable.buildFHSEnv` wrapper that resolves a Bottle's runner, seeds missing Proton `vkd3d` DLLs, and scopes runner `LD_LIBRARY_PATH` / `WINEDLLPATH` / `GST_PLUGIN_SYSTEM_PATH_1_0` strictly to `wine`/`wineserver` shims so Proton's bundled libraries do not break host GTK4 `zenity` dialogs.
- **`syncSteamCompatTools` activation**: Materializes Nix-built Proton runners into `~/.local/share/Steam/compatibilitytools.d/<Name>` as **real outer directories containing inner symlinks** to `/nix/store`. Making the outer directory a symlink causes `Path.resolve()` in UMU/Bottles to record transient `/nix/store/<hash>` paths that break after GC.

### Containers & Virtualisation (`hosts/containers.nix`)
- **Docker + Podman coexistence invariant**: Rootful Docker and rootless Podman are both enabled, while `virtualisation.oci-containers.backend = "podman"`. **`virtualisation.podman.dockerCompat` and `dockerSocket.enable` MUST remain `false`** so `docker` and `/var/run/docker.sock` always talk to `dockerd`.
- **Rootless `oci-containers` boot ordering**: Shared containers live in `hosts/containers.nix` and machine-specific ones in `hosts/{desktop,laptop}/containers.nix`. Any container running rootless as `fumoctl` (`podman.user = "fumoctl"`) needs its `systemd.services.podman-<name>` unit ordered `after`/`requires = [ "user@1000.service" ]` with `RequiresMountsFor` on `/run/user/1000/containers` and `/home/fumoctl/.local/share/containers` (and a `jq`-extended Podman seccomp profile if `io_uring` syscalls are used).
- **Unpatched binaries**: `programs.nix-ld` (`hosts/packages.nix`) and `nix-alien` provide dynamic linker/library support for external binaries and emulators alongside QEMU/KVM (`libvirtd`).

### Networking & Dynamic Timezone (`hosts/networking.nix` + `hosts/common.nix`)
- **DNS & Firewall**: `NetworkManager` delegates DNS to `systemd-resolved` (DNSSEC + DoT enforced, DHCP DNS ignored, `services.unbound.enable = false`) behind an `nftables` firewall (`checkReversePath = "loose"`). VPN tunnel interfaces are whitelisted via `networking.firewall.trustedInterfaces`.
- **GeoIP timezone**: `services.tzupdate.enable = true` dynamically updates the timezone and overrides `time.timeZone` (`config.time.timeZone` evaluates to `null` despite `lib.mkDefault`). Disable `tzupdate` if a static timezone is ever required.

---

## 7. Secrets (`sops-nix`) & Git Signing

- **Master key**: Post-quantum hybrid Age key (`mlkem768x25519`) stored at `/persist/sops/fumosops.key` (`0600`, owned by `fumoctl`), exported via `SOPS_AGE_KEY_FILE` (`home/secrets.nix`), with recipient rules in `.sops.yaml` and ciphertext in `secrets/secrets.yaml`.
- **Graceful keyless boot**: `systemd.user.services.sops-nix` sets `ConditionPathExists = "/persist/sops/fumosops.key"`, allowing fresh installs without the key to build and activate cleanly.
- **PGP & Git signing**: `sops-import-pgp.service` imports the decrypted PGP secret key once after `sops-nix.service`. `programs.git` (`home/shell.nix`) enforces `signByDefault = true`, so local commits require `gpg-agent` + the imported key.

### Common Secret Workflows
- **Edit interactively**: `sops secrets/secrets.yaml` (decrypts in memory, re-encrypts on save). If using `sops --decrypt --in-place` for an external editor, always run `sops --encrypt --in-place secrets/secrets.yaml` and verify `ENC[AES256_GCM,...]` in `git diff` before staging.
- **Add a secret**: Add the key in `sops secrets/secrets.yaml`, declare `sops.secrets.<name>` in `home/secrets.nix`, and either reference `config.sops.secrets.<name>.path` or export it via `sops.templates."shell-secrets.sh".content` (sourced automatically by Zsh).
- **Re-key**: Update `.sops.yaml`, then run `sops updatekeys secrets/secrets.yaml`.

---

## 8. Conventions & Placement Guide

### Where Changes Go

| Change Type | Target File |
| :--- | :--- |
| Shared NixOS / kernel / boot / user / `nh` setting | `hosts/common.nix` (or domain module in `hosts/*.nix`) |
| Host-specific hardware, kernel, GPU, Secure Boot | `hosts/desktop/default.nix` or `hosts/laptop/default.nix` |
| Persisted system or `$HOME` state | `hosts/impermanence.nix` |
| Compositor, bar, lockscreen, GTK/Qt/cursor theming | `hosts/desktop-env.nix` (system/greeter/portals) & `home/noctalia.nix` (HM) |
| System CLI / admin / `nix-ld` libraries | `hosts/packages.nix` |
| User GUI/dev apps, shell/Git/SSH, Flatpaks, MIME | `home/apps.nix`, `home/shell.nix`, `home/flatpak.nix`, `home/mime.nix` |
| OCI containers | `hosts/containers.nix` (shared) or `hosts/{desktop,laptop}/containers.nix` |
| SOPS secrets & env templates | `secrets/secrets.yaml` + `home/secrets.nix` |

### Coding & Git Rules
- **Formatting**: Format all Nix code with RFC-style `nixfmt` (`nixfmt $(git ls-files '*.nix')`).
- **Module headers & paths**: Keep module argument sets minimal (`inputs` is always passed via `specialArgs` / `extraSpecialArgs`). Use `lib.mkDefault` for options hosts may override, `${pkgs.foo}/bin/foo` or `lib.getExe` in scripts/hooks (never hardcode `/run/current-system/sw/bin/...`), and `lib.hm.dag.entryAfter [ "writeBoundary" ]` for HM activation scripts.
- **Preserve "why" comments**: Keep architectural inline comments (portal fallback, keyring SSH exclusion, Umbriel session startup, Docker/Podman socket split, KConfig symlinks, Proton directory materialization) intact when editing nearby code.
- **State versions**: Keep `system.stateVersion = "26.05"` and `home.stateVersion = "26.05"` untouched.
- **Untracked files in flakes**: Always run `git add -N <path>` on newly created files before evaluating or building the flake, or Nix will ignore them.
- **Commits**: Keep commit messages short, lowercase, and informal (matching `git log`); do not use Conventional Commit prefixes or add AI/co-author trailers unless asked. Commit `flake.lock` whenever `flake.nix` inputs change.

---

## 9. Verification Checklist

Never claim a configuration change works without evaluating both hosts:

```bash
# 1. Stage intent for any new files & verify no plaintext secrets
git status --short && git diff secrets/

# 2. Check Nix formatting across the repository
nixfmt --check $(git ls-files '*.nix')

# 3. Evaluate BOTH host system derivations
nix eval --raw .#nixosConfigurations.ultix-desktop.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.ultix-laptop.config.system.build.toplevel.drvPath

# 4. Spot-check specific NixOS or Home Manager options as needed
nix eval --json .#nixosConfigurations.ultix-desktop.config.<option.path>
nix eval --json .#nixosConfigurations.ultix-desktop.config.home-manager.users.fumoctl.<option.path>

# 5. Build / apply (use `boot` instead of `switch` for initrd, disko, impermanence, or bootloader edits)
nh os switch                         # auto-selects nixosConfigurations.$(hostname)
sudo nixos-rebuild switch --flake .#ultix-desktop
sudo nixos-rebuild switch --flake .#ultix-laptop
```

> **Sandboxed environments**: If `nix eval` fails with `attempt to write a readonly database (... fetcher-cache-v4.sqlite)`, run with `XDG_CACHE_HOME=$(mktemp -d) nix --offline eval ...`.
