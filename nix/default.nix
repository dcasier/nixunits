{
  configFile ? null
, id ? null
, propertiesJSON ? null
, pkgs
}:

let
  global = import ./global.nix {inherit lib pkgs;};
  id_ = if id != null then id else properties.id;
  lib = pkgs.lib;

  modules = [
    (_modules + "/misc/extra-arguments.nix")
    (_modules + "/misc/nixpkgs.nix")
    (_modules + "/system/boot/systemd.nix")
    (_modules + "/system/etc/etc.nix")
    (import ./tmpfiles.nix)
    (import ./dummy_options.nix)
    (import ./wrappers.nix)
    ({ config, lib, pkgs, ... }: with lib; {
      config = global.conf config.${global.moduleName};
      options = global.options // {
        boot.isContainer = mkOption {
          type = types.bool;
          default = true;
        };
        systemdDeps = mkOption {
          default = [];
          type = types.listOf types.str;
        };
      };
    })
  ] ++ (if configFile == null then [
    ({ config, lib, pkgs, ... }: {
      config = {
        systemd = import ./systemd.nix {
          inherit config global lib pkgs nixunits;
        };
      };
    })
  ] else [
    ({ config, pkgs, lib, ... }: {
      ${global.moduleName}.${id_} = import configFile { inherit config lib pkgs properties; id = id_; };
    })
  ] ++ modules_from_dir);
  modules_dir = work_dir + "/modules";
  modules_from_dir =
    lib.filter (x: x != null)
      (lib.mapAttrsToList
        (name: type:
          if type == "regular" && lib.hasSuffix ".nix" name
          then modules_dir + "/${name}"
          else null)
        (builtins.readDir modules_dir));

  nixunits = pkgs.callPackage ../nixunits.nix {
    inherit (pkgs) lib stdenv;
    inherit pkgs;
  };
  properties = builtins.fromJSON(propertiesJSON);

  utils = import ./utils.nix;

  system = (
    lib.evalModules({
      inherit modules;
      specialArgs = { inherit global pkgs; id = id_; };
    })
  ).config.system;
  work_dir = "/var/lib/nixunits";
  _modules = pkgs.path + "/nixos/modules";
in
  if configFile == null then
    system
  else
    system.build.etc
