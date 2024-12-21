{ lib, pkgs, ... }: let
in {
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
  };
}