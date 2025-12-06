{
  configFile ? null
, propertiesJSON ? null
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
  ] ++ modules_from_dir
    ++ (if configFile == null then [
    ({ config, lib, pkgs, ... }: {
      config = {
        systemd = import ./systemd.nix {
          inherit config global lib pkgs nixunits;
        };
      };
    })
  ] else [
    ({ config, pkgs, lib, ... }: let
      properties = builtins.fromJSON(propertiesJSON);
      id = properties.id;
    in {
      ${global.moduleName}.${id} = import configFile { inherit config lib pkgs properties; };
    })
  ]);
  modules_dir = work_dir + "/modules";
  modules_from_dir =
  lib.filter (x: x != null)
    (lib.mapAttrsToList
      (name: type:
        if type == "regular" && lib.hasSuffix ".nix" name
        then modules_dir + "/${name}"
        else null)
      (builtins.readDir modules_dir));

  utils = import ./utils.nix;

  system = (
    lib.evalModules({
      inherit modules;
      specialArgs = {inherit pkgs;};
    })
  ).config.system;
  work_dir = "/var/lib/nixunits";
in
  if configFile == null then
    system
  else
    system.build.etc
