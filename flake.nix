{
  description = "Nix, NixOS and Nix Darwin System Flake Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nordvpn-flake = {
      url = "github:nightconcept/nordvpn-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    nvchad = {
      url = "github:nix-community/nix4nvchad";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lazyvim-nixvim = {
      url = "github:azuwis/lazyvim-nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    libbyrip = {
      url = "git+https://forge.solivan.dev/nightconcept/libbyrip.git?rev=f10d2a90b165a35916239f636a59b356b94c8327";
      flake = false;
    };

    # Built on Rinoa by the events container module.
    events = {
      url = "git+https://forge.solivan.dev/nightconcept/events.git?rev=02cf0f27f415735a85f8242a03449fc4d393df65";
      flake = false;
    };

    # Self-hosted SMS gateway API and web UI, built on Rinoa.
    httpsms = {
      url = "github:NdoleStudio/httpsms/f352d81800e05c677f5118c6c3d32040769bb7e5";
      flake = false;
    };

    pi-agent = {
      url = "github:earendil-works/pi?ref=v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    ...
  } @ inputs: let
    lib = import ./lib/lib.nix {inherit inputs;};
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  in {
    nixosConfigurations = {
      tidus = lib.mkNixos inputs.nixpkgs "tidus";
      aerith = lib.mkNixosServer inputs.nixpkgs "aerith";
      barrett = lib.mkNixosServer inputs.nixpkgs "barrett";
      rinoa = lib.mkNixosServer inputs.nixpkgs "rinoa";
      vincent = lib.mkNixosServer inputs.nixpkgs "vincent";
      yuffie = lib.mkNixosServer inputs.nixpkgs "yuffie";
    };

    # Real builds of every active NixOS host, plus a VM boot of tidus. Yuffie builds these
    # nightly before it pushes a flake update (docs/yuffie.md). CI only evaluates them.
    checks.x86_64-linux =
      nixpkgs.lib.genAttrs ["tidus" "aerith" "rinoa" "vincent" "yuffie"] (
        host: self.nixosConfigurations.${host}.config.system.build.toplevel
      )
      // {
        tidus-boot = import ./tests/nixos/tidus-boot.nix {
          inherit pkgs inputs;
          modules = lib.nixosDesktopModules "tidus";
        };
      };

    darwinConfigurations = {
      waver = lib.mkDarwin inputs.nixpkgs "waver";
      merlin = lib.mkDarwin inputs.nixpkgs "merlin";
    };

    homeConfigurations = {
      # Generic configurations for standalone home-manager
      desktop = lib.mkHome "desktop";
      laptop = lib.mkHome "laptop";
      server = lib.mkHome "server";
    };

    # Formatters for different systems
    formatter = {
      x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
      aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
    };
  };
}
