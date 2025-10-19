{
  description = "Nix unit";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable"; };

  outputs = { self, nixpkgs }:  let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
      f (import nixpkgs { inherit system; })
    );
  in {
    nixosModules.default = import ./module.nix;

    packages = forAllSystems (pkgs: {
      portable = import ./src/portable { nixpkgs = pkgs; };
      nixunits = import ./src/nixunits.nix { inherit (pkgs) lib stdenv pkgs; };
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = [ self.packages.${pkgs.system}.nixunits ];
        shellHook = ''
          export SHELL=${pkgs.bashInteractive}/bin/bash
        '';
      };
    });
  };
}