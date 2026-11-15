# Fumoctl's NixOS Config (Ultix)

A modular, flake-based NixOS Stable configuration featuring an ephemeral root filesystem (`impermanence`), declarative disk partitioning (`disko`), pure-Nix Wayland desktop customization (**Umbriel** + **Noctalia**), post-quantum encrypted secrets (`sops-nix`), hardened networking, and gaming/virtualization optimizations.

---

## 💻 Hosts

| Host | Description | CPU / Kernel | GPU | Boot |
| :--- | :--- | :--- | :--- | :--- |
| **`ultix-desktop`** | Main Workstation | AMD Ryzen 7600X (Zen 4) · CachyOS Zen 4 LTO | AMD Radeon | Limine |
| **`ultix-laptop`** | TUXEDO Laptop | AMD Ryzen · XanMod | AMD Radeon + NVIDIA RTX (PRIME Offload) | Limine |

---

## 🌟 Features

### 🎨 Theming & Styling
- **Pure-Nix Desktop Customization**: Entirely declarative configuration in [`home/noctalia.nix`](home/noctalia.nix) for **Noctalia** and **Umbriel**, dynamically rendering synchronized palettes across Umbriel, GTK3/GTK4 (`adw-gtk3-dark`), Qt/KDE (`KColorScheme`), and Konsole.
- **Display Manager**: **Noctalia Greeter** (`greetd`) configured in [`hosts/desktop-env.nix`](hosts/desktop-env.nix) with passwordless Noctalia appearance/wallpaper/monitor sync and AccountsService portrait integration.
- **Bootloader**: Fast, lightweight **Limine** EFI bootloader (`sbctl` Secure Boot capable on both hosts).
- **Typography & Cursors**: JetBrainsMono Nerd Font, Noto Sans/Serif CJK JP, IPA/Kochi Japanese fonts, Noto Color Emoji, and `Bibata-Modern-Ice` cursors.
- **Integrated Toolkits**: Cohesive dark-mode theming across native Wayland apps, GTK/libadwaita, Qt5/Qt6 (`kde` platform theme), and Flatpak sandboxes.

### 🖥️ Desktop & Ergonomics
- **Wayland Compositor & Shell**: **Umbriel** compositor paired with **Noctalia** bar, launcher, clipboard history, control center, OSDs, lockscreen, and automated wallpaper cycling.
- **Window Management**: Dynamic `dwindle` and `scrolling` layouts with per-workspace toggling, persistent workspaces `1–9`, sloppy focus-follows-mouse, Kawase blur, and direct-scanout rules for fullscreen and `gamescope` games.
- **Portals & File Management**: Hybrid XDG Desktop Portal routing (`umbriel` + `gtk` + `kde`) pairing Umbriel screencasting with **Dolphin** (`kio-extras`, `kio-fuse`, `kio-admin`, thumbnailers) and standalone KDE XDG menus without pulling Plasma into the system closure.
- **Input Tuning**: `us` (`altgr-intl`) keyboard layout, flat mouse acceleration profile (1:1 tracking), and natural touchpad scrolling.

### ⚡ Kernel & Hardware Performance
- **Optimized Kernels**: Zen 4 LTO CachyOS kernel (`linuxPackages_cachyos-lto-znver4` from **Chaotic-Nyx**) on `ultix-desktop` and **XanMod** (`linuxPackages_xanmod`) on `ultix-laptop`.
- **Wine Synchronization**: `ntsync` kernel module enabled for low-overhead Wine/Proton thread synchronization.
- **System Tuning**: `vm.max_map_count = 2147483642` (SteamOS default), raised `inotify` watch/instance limits, and `1048576` `nofile` limits across PAM and systemd.
- **Laptop & Hybrid Graphics**: TUXEDO hardware support (`tuxedo-drivers`, `tuxedo-rs`, `tailor-gui`) and open NVIDIA kernel modules with fine-grained power management and PRIME offload (`nvidia-offload`) on `ultix-laptop`.

### 🎮 Gaming
- **Steam & Proton**: Configured with 32-bit graphics, Steam Remote Play & dedicated server firewall rules, Gamescope session support, and declaratively materialized Proton runners (`Proton-CachyOS`, `Proton-GE`).
- **Umbriel-Aware Gamescope (`gs-run`)**: Custom launcher in [`hosts/gaming.nix`](hosts/gaming.nix) that auto-detects the focused Umbriel monitor's native resolution, refresh rate, HDR, and VRR state, with aspect clamping (`16:9`, `21:9`, `4:3`), FSR/pixel upscaling, Steam runtime isolation, and `wineserver` lifecycle tracking.
- **Bottles & Winetricks**: Custom multi-arch FHS `bottles-winetricks` helper alongside Bottles pre-wired with `gs-run` and `lsfg-vk`.
- **Monitoring, GPU Control & Frame Generation**: MangoHud, Goverlay, GameMode, LACT daemon/GUI for AMDGPU tuning, and Lossless Scaling Vulkan layer (`lsfg-vk`).

### 🔒 Security, Secrets & Hardened Networking
- **Post-Quantum Secrets (`sops-nix`)**: SOPS-encrypted SSH, PGP, and API secrets unlocked via a persistent post-quantum hybrid Age master key (`mlkem768x25519`), with automatic GnuPG keyring import and enforced Git commit signing.
- **DNS-over-TLS & DNSSEC**: Native **`systemd-resolved`** configuration enforcing DNS-over-TLS and DNSSEC with AdGuard DNS (`dns.adguard-dns.com`), backed by Quad9 (`dns.quad9.net`) and Mullvad (`base.dns.mullvad.net`) encrypted fallbacks.
- **Network Privacy & Firewall**: NetworkManager configured with MAC address randomization (`stable-temporary` for Wi-Fi/Ethernet and random Wi-Fi scan MACs), IPv6 privacy extensions (`ip6-privacy = 2`), `nftables` firewall, **Windscribe** VPN integration, and `captive-browser` on `ultix-laptop`.

### 💾 Ephemeral Storage & Virtualization
- **Declarative Partitioning & Impermanence**: Automated GPT partitioning, LUKS2 encryption, and Btrfs subvolumes (`@`, `@persist`, `@nix`, `@log`, `@snapshots`, `@swap` with a 32G swapfile) via **Disko**. An initrd systemd service wipes and recreates `@` (`/`) on every boot while system and user state are selectively persisted under `/persist`.
- **Containers**: Coexisting rootful **Docker** and rootless **Podman** (with declarative `oci-containers`, including an `io_uring`-enabled PostgreSQL 18 service bounded via systemd cgroups) plus local Kubernetes tooling.
- **Virtualization & Package Management**: QEMU/KVM via `libvirtd` (`virt-manager`, `swtpm` TPM emulation, `virtiofsd`, SPICE), Nix Flakes + `nh` automatic generation cleanup, Home Manager, declarative Flatpaks via `nix-flatpak` with daily auto-updates, and `nix-ld` + `nix-alien` for running unpatched dynamic binaries.

---

## 🚀 Installation Guide

### Option A: Installing an Existing Host

`<hostname>` below is either `ultix-desktop` or `ultix-laptop`.

1. **Boot into the NixOS Live USB**.
2. **Verify target disk ID**:
   Ensure the disk ID in [`hosts/desktop/disko.nix`](hosts/desktop/disko.nix) or [`hosts/laptop/disko.nix`](hosts/laptop/disko.nix) matches your target drive:
   ```bash
   ls -l /dev/disk/by-id/
   ```
3. **Partition, format, and mount with Disko**:
   ```bash
   sudo nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode disko --flake github:fumoctl/Ultix#<hostname>
   ```
   _(Or clone the repo locally and use `--flake .#<hostname>`)_

4. **Initialize persistent user password**:
   Because `users.mutableUsers = false` and `hashedPasswordFile = "/persist/passwords/fumoctl"` are enforced, you must seed the password hash into `/persist` before installing, or the account will be locked on first boot:
   ```bash
   sudo mkdir -p /mnt/persist/passwords
   nix-shell -p mkpasswd --run 'mkpasswd -m sha-512' | sudo tee /mnt/persist/passwords/fumoctl
   sudo chmod 600 /mnt/persist/passwords/fumoctl
   ```

5. **(Optional) Restore SOPS Age master key**:
   Restore your Age private key into `/persist` before installing so SSH, PGP, and API secrets decrypt automatically on first boot:
   ```bash
   sudo mkdir -p /mnt/persist/sops
   sudo nano /mnt/persist/sops/fumosops.key   # paste your AGE-SECRET-KEY-1...
   sudo chown -R 1000:1000 /mnt/persist/sops
   sudo chmod 700 /mnt/persist/sops
   sudo chmod 600 /mnt/persist/sops/fumosops.key
   ```
   _Note: If installing without this key, the system still builds and boots cleanly; secret decryption is skipped automatically._

6. **Install NixOS**:
   ```bash
   sudo swapon /mnt/.swapvol/swapfile
   sudo mkdir -p /mnt/var/tmp/nix-build
   sudo TMPDIR=/mnt/var/tmp/nix-build nixos-install --flake github:fumoctl/Ultix#<hostname>
   ```
   _(Setting `TMPDIR` on the mounted disk avoids out-of-memory errors in the Live USB's RAM-backed `/tmp` when building from source.)_

7. **Reboot**:
   ```bash
   reboot
   ```

---

### Option B: Bootstrapping a Brand New Host

1. **Boot into the NixOS Live USB** on the target machine.
2. **Generate hardware configuration (without storage mounts)**:
   ```bash
   nixos-generate-config --no-filesystems --show-hardware-config
   ```
   _(The `--no-filesystems` flag avoids hardcoding mounts and UUIDs since Disko manages storage.)_
3. **Create the new host configuration**:
   - Create `hosts/<host>/`:
     - `hardware-configuration.nix` (paste the output from step 2).
     - `disko.nix` (specify the target `/dev/disk/by-id/...` and Btrfs subvolume layout, including `@persist`).
     - `containers.nix` (host-specific OCI container definitions).
     - `default.nix` (import `../common.nix`, `../containers.nix`, `./containers.nix`, `./hardware-configuration.nix`, and `./disko.nix`, and set `networking.hostName = "<hostname>";`).
   - Register `<hostname> = mkHost ./hosts/<host>;` under `nixosConfigurations` in [`flake.nix`](flake.nix).
4. **Partition, seed credentials, and install**:
   ```bash
   sudo nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode disko --flake .#<hostname>

   sudo mkdir -p /mnt/persist/passwords
   nix-shell -p mkpasswd --run 'mkpasswd -m sha-512' | sudo tee /mnt/persist/passwords/fumoctl
   sudo chmod 600 /mnt/persist/passwords/fumoctl

   sudo swapon /mnt/.swapvol/swapfile
   sudo mkdir -p /mnt/var/tmp/nix-build
   sudo TMPDIR=/mnt/var/tmp/nix-build nixos-install --flake .#<hostname>
   reboot
   ```

---

## 🛠️ Post-Install & Daily Usage

### Rebuild and Switch Configuration

```bash
nh os switch
# Or explicitly with nixos-rebuild:
sudo nixos-rebuild switch --flake .#<hostname>
```

### Stage Configuration for Next Boot

```bash
nh os boot
# Or explicitly with nixos-rebuild:
sudo nixos-rebuild boot --flake .#<hostname>
```

### Update Flake Inputs

```bash
cd ~/Projects/Ultix
nix flake update
nh os switch
```
