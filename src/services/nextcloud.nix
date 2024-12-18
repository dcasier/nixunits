{ lib, pkgs, ... }: {
  services = {
    nextcloud = {
      enable = true;
      package = pkgs.nextcloud30;
      hostName = "localhost";
      config = {
        adminpassFile = "/etc/nextcloud-admin-pass";
        adminuser = "admin";
      };
    };
    # nginx.enable = false;
  };
}

