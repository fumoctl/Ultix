{
  description = "Ultix: Modular host-separated NixOS Stable configuration with Hyprland, Noctalia, and Impermanence";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    impermanence.url = "github:nix-community/impermanence";
    disko.url = "github:nix-community/disko";
    noctalia.url = "github:noctalia-dev/noctalia";
    lsfg-vk.url = "github:Daaboulex/lsfg-vk-nix";
    nix-alien.url = "github:thiagokokada/nix-alien";
    windscribe-nixos.url = "github:fumoctl/windscribe-nixos";
    antigravity-nix.url = "github:jacopone/antigravity-nix";
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://noctalia.cachix.org"
      "https://nyx-cache.chaotic.cx"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
    ];
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      disko,
      chaotic,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            chaotic.nixosModules.nyx-cache
            chaotic.nixosModules.nyx-overlay
            chaotic.nixosModules.nyx-registry
            hostModule
          ];
        };
    in
    {
      nixosConfigurations = {
        fumonix-desktop = mkHost ./hosts/desktop;
        fumonix-laptop = mkHost ./hosts/laptop;
      };
    };
}
