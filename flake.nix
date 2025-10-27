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

    lib = forAllSystems (pkgs: {
      mkContainer = { configFile, propertiesJSON }:
        let
          properties = builtins.fromJSON(propertiesJSON);
          config = import configFile { inherit pkgs properties; lib = pkgs.lib; };
          id = properties.id;
        in
          pkgs.callPackage ./nix/default.nix {
              inherit id config;
          };
    });

    packages = forAllSystems (pkgs: {
      portable = import ./nix/portable { nixpkgs = pkgs; };
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
