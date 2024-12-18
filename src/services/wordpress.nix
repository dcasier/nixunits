{ lib, pkgs, ... }: {
  services = {
    mysql.enable = true;
    wordpress.sites."localhost" = {};
  };
}
