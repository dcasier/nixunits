{ config, lib, pkgs, ... }@host:

with lib; let
  autoStartFilter = cfg:
    filterAttrs(n: v: v.autoStart) cfg;

  global = import ./nix/global.nix {inherit lib pkgs;};
  moduleName = global.moduleName;

  nixunits = pkgs.callPackage ./nixunits.nix {
    inherit (pkgs) lib stdenv;
    inherit pkgs;
  };
  systemd = import ./nix/systemd.nix { inherit config global lib pkgs nixunits; };
in {
  config = recursiveUpdate (global.conf config.${moduleName}) {
    inherit systemd;

    environment.systemPackages = [ nixunits ];
    networking.dhcpcd.denyInterfaces = [ "ve-*" "vb-*" ];
    services.udev.extraRules = optionalString config.networking.networkmanager.enable ''
      # Don't manage interfaces created by nspawn.
      ENV{INTERFACE}=="v[eb]-*", ENV{NM_UNMANAGED}="1"
    '';

    users.groups.nixunits = {};
  };
  options = global.options // {
    path = mkOption {
      type = types.str;
    };
  };
}
