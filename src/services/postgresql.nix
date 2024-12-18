{ lib, pkgs, ... }: let

in {
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    ensureDatabases = [ "default" ];
  };
}