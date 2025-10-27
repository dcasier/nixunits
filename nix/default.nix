{
  id
, nixpkgs? <nixpkgs>
, config
}:

let
  _modules = nixpkgs + "/nixos/modules";
  lib = pkgs.lib;
  pkgs = import nixpkgs {};

  global = import ./global.nix {inherit lib pkgs;};

  modules = [
    (_modules + "/misc/extra-arguments.nix")
    (_modules + "/misc/nixpkgs.nix")
    (_modules + "/system/boot/systemd.nix")
    (_modules + "/system/etc/etc.nix")
    (import ./tmpfiles.nix)
    (import ./dummy_options.nix)
    ({ config, lib, pkgs, ... }: {
      config = global.conf config.${global.moduleName};
      options = global.options // {
        boot.isContainer = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
      };
    })
    {
      ${global.moduleName}.${id} = config;
    }
  ];

  utils = import ./utils.nix;

  system = (
    lib.evalModules({
      inherit modules;
      specialArgs = {inherit pkgs;};
    })
  ).config.system;
in system.build.etc
