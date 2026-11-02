{
  pkgs,
  ...
}:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.steam-hardware.enable = true;

  programs.gamemode.enable = true;
  programs.gamescope.enable = true;

  programs.steam = {
    enable = true;
    extest.enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [
      proton-cachyos
      proton-ge-custom
    ];
  };

  services.lact.enable = true;

  environment.systemPackages = with pkgs; [
    lact
    mangohud
    goverlay
    mesa-demos
    lsfg-vk
  ];
}
