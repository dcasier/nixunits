{
  caps_allow ? "[]"
, hostIp4 ? ""
, hostIp6 ? ""
, id
, interface ? ""
, ip4? ""
, ip4route? ""
, ip6? ""
, ip6route? ""
, nixpkgs? <nixpkgs>
, properties ? "{}"
}:

let
  _modules = nixpkgs + "/nixos/modules";
  lib = pkgs.lib;
  pkgs = import nixpkgs {};

  _caps_allow = builtins.fromJSON(caps_allow);
  _properties = builtins.fromJSON(properties);

  config = let
    _file = global.fileNix id;
    _ = lib.assertMgs (builtins.pathExists _file) "Service undefined";
    _conf = import _file;
  in
    if builtins.isFunction _conf then
      _conf { inherit lib pkgs properties; }
    else
      _conf;

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
      ${global.moduleName}.${id} = {
        inherit config;
        network = {
          inherit hostIp4 hostIp6 interface ip4 ip4route ip6 ip6route;
        };
        caps_allow=_caps_allow;
      };
    }
  ];

  utils = import ./utils.nix;
in (
  lib.evalModules({
    inherit modules;
    specialArgs = {inherit pkgs;};
  })
).config.system.build.etc
