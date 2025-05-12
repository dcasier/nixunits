# NixUnits

Implémentation inspiré de nixos-container et extra-container

Travaux, à titre expérimentales, de mini-conteneurs Nix sécurisés, pour la plateforme Aevoo.

## Objectif

 - (Similaire à extra-container) Permettre d'instancier des conteneurs, sans à avoir à recharger tout le système;
 - (Sécurité) Augmenter, au maximum, le niveau d'isolation du conteneur ;
 - Réduire l'empreinte du conteneur au minimum (systemdMinimal).

### Limitations

 - Plusieurs fonctionnalités de nixos-container n'ont pas (encore ? ) été implémentées ;
 - Pilotable avec machinectl, à l'exception du shell (passage par nsenter) ;
 - Dans la version initiale, la configuration du réseau est réalisée après démarrage (depuis le host).

### Niveau réseau, 3 implémentations

 - private-network, si aucune configuration réseau spécifié
 - pas d'interface et host_ip => private-network network-veth (host_ip, c'est celle de l'interface ve-XXX)
 - interface seule => réseau uniquement dans le conteneur

## Installation

### Flake

```
nixunits.url = "git+https://git.aevoo.com/aevoo/os/nixunits.git";

imports = [
  nixunits.nixosModules.default
];

```

## Configuration

### CLI

#### Create

```
[root@aevoo-home:~]# nixunits build pg -cc "{ services.postgresql.enable = true; }" -6 -r
Container : pg
  ip6: fc00::bd30:9ff2:2
  hostIp6: fc00::bd30:9ff2:1

[root@aevoo-home:~]# nixunits nsenter pg -- su postgres -c "psql -c \"ALTER USER postgres PASSWORD 'myPassword';\"" 2>/dev/null
ALTER ROLE

nix-build /nix/store/v0f4qns0clv6iaayb8q4lhx3bnyk33aj-nixunits-0.1/default.nix --argstr id pg --argstr service postgresql --argstr hostIp6 fc00::bd30:9ff2:1 --argstr ip6 fc00::bd30:9ff2:2 --out-link /var/lib/nixunits/containers//pg/result
/nix/store/iw4r42696fa807m88xpyfx2bifiwc2n7-etc
systemctl restart nixunits@pg
● nixunits@pg.service - NixUnit container 'pg'
     Loaded: loaded (/etc/systemd/system/nixunits@.service; static)
     Active: active (running) since Wed 2024-12-18 16:12:17 CET; 12ms ago
(...)
```

#### Shell

```
[nix-shell:/var/lib/nixunits]# nixunits nsenter pg 

[root@pg:/]# su postgres
su: Authentication service cannot retrieve authentication info
(Ignored)

[postgres@pg:/]$ psql
psql (16.5)
Type "help" for help.

postgres=# 
```

#### Customs service

```
[root@aevoo-home:/var/lib/nixunits]# cat > customs/postgresql.nix >> EOF 
{ lib, pkgs, ... }: let

in {
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    ensureDatabases = [ "default" ];
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method      
      local all all              peer
      host  all all     ::0/0    md5
      host  all all 0.0.0.0/0    md5
    '';
  };
}
EOF 

[root@aevoo-home:/var/lib/nixunits]# nixunits build pg -cf /var/lib/nixunits/customs/postgresql.nix -6 -r
(...)

[root@aevoo-home:/var/lib/nixunits]# nix-shell -p postgresql
[nix-shell:/var/lib/nixunits]# psql -h fc00::bd30:9ff2:2 -U postgres 
Password for user postgres: 
psql (16.5)
Type "help" for help.

postgres=# 
```

##### Delete

```
[nix-shell:/var/lib/nixunits]# ls -lrth containers/pg
total 4,0K
lrwxrwxrwx  1 root    nixunits  47 déc.  18 17:46 result -> /nix/store/rqb55dmyfj18piz5cbkpya1c2flip1cr-etc
lrwxrwxrwx  1 root    nixunits  60 déc.  18 17:46 unit.conf -> /var/lib/nixunits/containers//pg/result/etc/nixunits/pg.conf
drwxr-xr-x 14 vu-pg-0 vg-pg-0  141 déc.  18 17:46 root
-rw-r--r--  1 root    nixunits 316 déc.  18 17:46 unit.log

[nix-shell:/var/lib/nixunits]# nixunits delete pg 
Delete /var/lib/nixunits/containers//pg ? [y/N] : y
[nix-shell:/var/lib/nixunits]# ls -lrth containers/pg
total 0
drwxr-xr-x 14 1494155264 1494155264 141 déc.  18 17:46 root
[nix-shell:/var/lib/nixunits]# ls -lrth containers/
[nix-shell:/var/lib/nixunits]#
```

### Nixos

```
 nixunits = {
    mysql1 = {
      autoStart = true;
      config = {
        services.mysql = {
          enable = true;
          package = pkgs.mariadb;
        };
      };
      network = {
        host_ip6 = "fc00::1/64";
        # interface = "test2";
        ip6 = "fc00::2/64";
        # ip6route = "fe80::1";
      };
    };
  };
```


