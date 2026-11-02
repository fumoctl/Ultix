{
  description = "Ultix: Modular host-separated NixOS Stable configuration with Hyprland, Noctalia, and Impermanence";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
    disko = {
      url = "github:nix-community/disko";
    };
    nur = {
      url = "github:nix-community/NUR";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia";
    };
    lsfg-vk = {
      url = "github:Daaboulex/lsfg-vk-nix";
    };
    nix-alien = {
      url = "github:thiagokokada/nix-alien";
    };
    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
    };
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
      self,
      nixpkgs,
      home-manager,
      disko,
      chaotic,
      nix-flatpak,
      sops-nix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        fumonix-desktop = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            nix-flatpak.nixosModules.nix-flatpak
            sops-nix.nixosModules.sops
            chaotic.nixosModules.nyx-cache
            chaotic.nixosModules.nyx-overlay
            chaotic.nixosModules.nyx-registry
            ./hosts/desktop/default.nix
          ];
        };

        fumonix-laptop = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            nix-flatpak.nixosModules.nix-flatpak
            sops-nix.nixosModules.sops
            chaotic.nixosModules.nyx-cache
            chaotic.nixosModules.nyx-overlay
            chaotic.nixosModules.nyx-registry
            ./hosts/laptop/default.nix
          ];
        };
      };
    };
}
