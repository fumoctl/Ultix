{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../common.nix
    ../containers.nix
    ./containers.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "ultix-laptop";

  programs.captive-browser = {
    enable = true;
    interface = "wlp98s0";
    browser = ''env XDG_CONFIG_HOME="$PREV_CONFIG_HOME" ${lib.getExe pkgs.brave} --user-data-dir=''${XDG_DATA_HOME:-$HOME/.local/share}/brave-captive --proxy-server="socks5://$PROXY" --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE localhost" --no-first-run --new-window --incognito --no-default-browser-check http://cache.nixos.org/'';
  };

  boot.loader.limine.secureBoot.enable = lib.mkDefault true;

  boot.kernelPackages = pkgs.linuxPackages_xanmod;

  # NVIDIA PRIME hybrid graphics
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [
    "modesetting"
    "nvidia"
  ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    powerManagement = {
      enable = true;
      finegrained = true;
    };
    nvidiaSettings = true;
    prime = {
      offload = {
        enable = true;
        # Custom wrapper below also clears session VK_DRIVER_FILES so Vulkan
        # games offloaded to the RTX 5070 discover nvidia_icd.json.
        enableOffloadCmd = false;
      };
      amdgpuBusId = "PCI:66:0:0";
      nvidiaBusId = "PCI:64:0:0";
    };
  };

  # Default desktop apps to the AMD Radeon 890M iGPU so Vulkan initialization
  # (browsers, Electron, editors, Bottles UI, etc.) does not load nvidia_icd.json
  # and stall ~2.8s waking the suspended RTX 5070 out of D3cold.
  environment.sessionVariables.VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json:/run/opengl-driver-32/share/vulkan/icd.d/radeon_icd.i686.json";

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nvidia-offload" ''
      unset VK_DRIVER_FILES
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only
      exec "$@"
    '')
  ];

  # Skip per-key RGB USB HID driver (exposes 126 `kbd_backlight*` sysfs LEDs
  # that stall UPower, KDE Solid, and Noctalia for ~60s at login).
  boot.blacklistedKernelModules = [ "ite_8291" ];

  hardware.tuxedo-drivers.enable = true;

  hardware.tuxedo-rs = {
    enable = true;
    tailor-gui.enable = true;
  };

  environment.persistence."/persist".directories = [ "/etc/tailord" ];
  # Upstream tailord terminates via `std::process::abort()` on SIGTERM, and
  # resets the ODM profile on startup when `performance_profile` is unset —
  # ensure power-profiles-daemon starts after tailord so saved `state.ini` wins.
  systemd.services.tailord.serviceConfig = {
    SuccessExitStatus = "SIGABRT";
    LimitCORE = 0;
  };
  systemd.services.power-profiles-daemon.after = [ "tailord.service" ];
}
