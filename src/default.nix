{
  caps ? "[]"
, hostIp4 ? ""
, hostIp6 ? ""
, id
, interface ? ""
, ip4? ""
, ip4route? ""
, ip6? ""
, ip6route? ""
, nixpkgs? <nixpkgs>
, service? null
}:

let
  _modules = nixpkgs + "/nixos/modules";
  lib = pkgs.lib;
  pkgs = import nixpkgs {};

  caps_allow = builtins.fromJSON(caps);

  config = let
    _custom = global.fileCustom service;
    _service = global.fileService service;
    _target = global.fileNix id;
    _file = if builtins.pathExists _target then
        _target
    else
        if builtins.pathExists _custom then
          _custom
        else
          _service;
    _exists = (builtins.pathExists _file);
  in
    if _exists then
      builtins.trace ''Import : ${_file}'' import _file {inherit lib pkgs;}
    else {
      services.${service}.enable = true;
    };

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
        inherit caps_allow config;
        network = {
          inherit hostIp4 hostIp6 interface ip4 ip4route ip6 ip6route;
        };
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
