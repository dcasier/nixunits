{
  description = "Nix unit";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable"; };

  outputs = { self, nixpkgs }: {
    nixosModules.default = import ./module.nix;

    devShells.x86_64-linux.default =
      let pkgs = import nixpkgs { system = "x86_64-linux"; };
      in pkgs.mkShell {
        packages = [
          (import ./src/nixunits.nix { inherit (pkgs) lib stdenv pkgs; })
        ];
        shellHook = ''
          export SHELL=${pkgs.bashInteractive}/bin/bash
        '';
      };
  };
}
