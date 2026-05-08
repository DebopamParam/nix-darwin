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

    # mac-app-util: Spotlight indexing for Nix .app files
    # TEMPORARILY DISABLED — SBCL/fare-quasiquote build failure on nixpkgs-unstable
    # Uncomment when upstream is fixed:
    # mac-app-util = {
    #   url = "github:hraban/mac-app-util";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # Declarative Homebrew management
    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
      # Override the brew version pinned by nix-homebrew (5.1.7) which has a
      # parser crash on the current cask JSON API. 5.1.10 fixes it.
      inputs.brew-src.follows = "brew-src";
    };
    brew-src = {
      url = "github:Homebrew/brew";
      flake = false;
    };

  };

  outputs = inputs@{
    self,
    nixpkgs,
    nix-darwin,
    home-manager,
    nix-homebrew,
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

        # ── mac-app-util: TEMPORARILY DISABLED ──
        # mac-app-util.darwinModules.default

        # ── nix-homebrew: takes over your existing Homebrew ──
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = username;

            # *** IMPORTANT: migrates your existing Homebrew install ***
            autoMigrate = true;

          };
        }

        # ── home-manager (shell, git, dotfiles) ──
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # backupFileExtension = "backup";
            extraSpecialArgs = { inherit inputs; };
            users.${username} = import ./modules/home.nix;
          };
        }
      ];
    };
  };
}