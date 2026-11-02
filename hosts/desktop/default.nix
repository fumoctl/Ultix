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

  networking.hostName = "fumonix-desktop";

  boot.loader.limine.secureBoot.enable = lib.mkDefault true;

  # AMD GPU hardware acceleration
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "modesetting" ];
  hardware.graphics.extraPackages = with pkgs; [
    libva
    libva-vdpau-driver
    libvdpau-va-gl
  ];

  # CachyOS kernel optimized for Zen 4 (Ryzen 7600X)
  boot.kernelPackages = lib.mkDefault (
    if pkgs ? linuxPackages_cachyos-lto-znver4 then
      pkgs.linuxPackages_cachyos-lto-znver4
    else
      pkgs.linuxPackages_latest
  );

  boot.kernelParams = [
    "amdgpu.runpm=0"
  ];
}
