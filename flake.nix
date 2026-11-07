{
  description = "Nix unit";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:  let
    rev = self.shortRev or self.dirtyShortRev or "unknown";
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
      f (import nixpkgs {
        overlays = [];
        inherit system;
      })
    );
  in {
    nixosModules.default = { config, lib, pkgs, ... }@args:
      import ./module.nix (args // { nixunitsRev = rev; });

    lib = forAllSystems (pkgs: {
      mkContainer = { configFile, id ? null, propertiesJSON }:
        pkgs.callPackage ./nix/default.nix {
            inherit configFile id pkgs propertiesJSON;
        };
    });

    packages = forAllSystems (pkgs: {
      portable = import ./nix/portable { inherit (pkgs) lib pkgs; inherit rev; };
      nixunits = import ./nixunits.nix { inherit (pkgs) lib stdenv pkgs; inherit rev; };
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
