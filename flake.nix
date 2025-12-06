{
  description = "Nix unit";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:  let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
      f (import nixpkgs {
        overlays = [];
        inherit system;
      })
    );
  in {
    nixosModules.default = import ./module.nix;

    lib = forAllSystems (pkgs: {
      mkContainer = { configFile, propertiesJSON }:
        pkgs.callPackage ./nix/default.nix {
            inherit configFile pkgs propertiesJSON;
        };
    });

    packages = forAllSystems (pkgs: {
      portable = import ./nix/portable { inherit (pkgs) lib pkgs; };
      nixunits = import ./nixunits.nix { inherit (pkgs) lib stdenv pkgs; };
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
