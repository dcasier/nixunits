{
  serviceConfig ? null
, id ? null
, pkgs
}:

let
  _modules = pkgs.path + "/nixos/modules";
  lib = pkgs.lib;

  global = import ./global.nix {inherit lib pkgs;};
  nixunits = pkgs.callPackage ../nixunits.nix {
    inherit (pkgs) lib stdenv;
    inherit pkgs;
  };

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
  ] ++ (if serviceConfig == null then [
    ({ config, lib, pkgs, ... }: {
      config = {
        systemd = import ./systemd.nix {
          inherit config global lib pkgs nixunits;
        };
      };
    })
  ] else [
    {
      ${global.moduleName}.${id} = serviceConfig;
    }
  ]);

  utils = import ./utils.nix;

  system = (
    lib.evalModules({
      inherit modules;
      specialArgs = {inherit pkgs;};
    })
  ).config.system;
in
if serviceConfig == null then
  system
else
  system.build.etc
