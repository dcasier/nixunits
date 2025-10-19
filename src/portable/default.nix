{ nixpkgs ? import <nixpkgs> {}, lib ? nixpkgs.lib, pkgs ? nixpkgs, ... }:
let
  global = import ../global.nix { inherit lib pkgs; };
  nixunits = pkgs.callPackage ../nixunits.nix { inherit (pkgs) lib stdenv pkgs; };
  installTool = pkgs.callPackage ./install.nix { inherit lib pkgs global nixunits; };
in
pkgs.stdenv.mkDerivation {
  name = "nixunits-install";

  buildCommand = ''
    mkdir -p $out/bin
    ln -s ${installTool}/bin/nixunits-install $out/bin/
  '';

  meta = {
    description = "Portable nixunits installer for non-NixOS systems";
    platforms = lib.platforms.linux;
  };
}
