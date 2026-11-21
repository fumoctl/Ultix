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

  networking.hostName = "ultix-desktop";

  boot.loader.limine.secureBoot.enable = lib.mkDefault true;

  # AMD GPU hardware acceleration
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "modesetting" ];

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
