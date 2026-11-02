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

  networking.hostName = "fumonix-laptop";

  programs.captive-browser = {
    enable = true;
    interface = "wlp98s0";
  };

  boot.loader.limine.secureBoot.enable = lib.mkDefault false;

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
        enableOffloadCmd = true;
      };
      amdgpuBusId = "PCI:66:0:0";
      nvidiaBusId = "PCI:64:0:0";
    };
  };

  hardware.tuxedo-drivers.enable = true;

  hardware.tuxedo-rs = {
    enable = true;
    tailor-gui.enable = true;
  };
}
