{ config, lib, pkgs, ... }@host:

with lib;

let
  autoStartFilter = cfg:
    filterAttrs(n: v: v.autoStart) cfg;

  global = import ./src/global.nix {inherit lib pkgs;};
  moduleName = global.moduleName;

  nixunits = pkgs.callPackage ./src/nixunits.nix {
    inherit (pkgs) lib stdenv;
    inherit pkgs;
  };

  systemd = import ./src/systemd.nix {
    inherit lib pkgs global nixunits;
  };
in

{
  config = recursiveUpdate (global.conf config.${moduleName}) {

    environment.systemPackages = [
      nixunits
    ];

    networking.dhcpcd.denyInterfaces = [ "ve-*" "vb-*" ];

    services.udev.extraRules = optionalString config.networking.networkmanager.enable ''
      # Don't manage interfaces created by nspawn.
      ENV{INTERFACE}=="v[eb]-*", ENV{NM_UNMANAGED}="1"
    '';

  };
  options = global.options // {
    path = mkOption {
      type = types.str;
    };
  };
}
