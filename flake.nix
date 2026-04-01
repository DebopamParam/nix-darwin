{
  description = "Debopam's MacBook nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Spotlight indexing for Nix-installed .app files
    mac-app-util = {
      url = "github:hraban/mac-app-util";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Homebrew management
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Pinned Homebrew taps
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };

  outputs = inputs@{
    self,
    nixpkgs,
    nix-darwin,
    home-manager,
    mac-app-util,
    nix-homebrew,
    homebrew-core,
    homebrew-cask,
    homebrew-bundle,
    ...
  }: let
    # ═══════════════════════════════════════════
    #  EDIT THESE TWO VALUES
    # ═══════════════════════════════════════════
    username = "debopamchowdhury";       # ← output of: whoami
    hostname = "Debopams-MacBook-Pro";         # ← output of: scutil --get LocalHostName
    system   = "aarch64-darwin";      # Apple Silicon (M-series)
  in {

    darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = { inherit inputs username hostname; };
      modules = [

        # ── System config (packages + macOS settings) ──
        ./modules/system.nix
        ./modules/homebrew.nix

        # ── mac-app-util: makes Nix apps visible in Spotlight ──
        mac-app-util.darwinModules.default

        # ── nix-homebrew: takes over your existing Homebrew ──
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = username;

            # *** IMPORTANT: migrates your existing Homebrew install ***
            autoMigrate = true;

            taps = {
              "homebrew/homebrew-core"   = homebrew-core;
              "homebrew/homebrew-cask"   = homebrew-cask;
              "homebrew/homebrew-bundle" = homebrew-bundle;
            };
            mutableTaps = false;
          };
        }

        # ── home-manager (shell, git, dotfiles) ──
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs; };
            users.${username} = import ./modules/home.nix;
          };
        }
      ];
    };
  };
}