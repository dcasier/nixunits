# NixUnits

Exécutez des services **NixOS** dans des conteneurs **légers**, **déclaratifs**, et **isolés**.

Inspiré de **nixos-container** et **extra-container**,
conçu initialement pour Aevoo et utilisable sur un hôte Linux systemd.

## Fonctionnalités

NixUnits permet d’exécuter du NixOS sur n’importe quel Linux systemd, avec une isolation par service,
en conservant une gestion purement déclarative.

* **Nix**  
  Le service fonctionne dans un environnement système minimal et reproductible.
* S'appuie sur **NixOS/nixpkgs** pour la construction de l'image
* **systemd-nspawn** sur l’hôte  
  Orchestration via `systemctl` et `machinectl`.
* **Overlay Nix store partagé**  
  Duplication minimale entre conteneurs.
* **Réseau configurable**  
  Interfaces, IPs, OVS, VLAN, netns, routes.
* **Sécurité explicite**  
  Capabilities contrôlées par la déclaration Nix.
* Empreinte minimale : **systemd-minimal** et dépendances limitées.


> Ce qui est déclaré est ce qui est exécuté.

---

## Empreinte mémoire et processus

Un conteneur NixUnits lance généralement :

* systemd-minimal (PID1)
* journald conteneur  
* le service principal + auxiliaires

Supprimé :  
✗ logind  
✗ getty  
✗ user-sessions  
✗ coredumpd  
✗ autres services inutiles pour un workload conteneurisé

> Suffisant pour orchestrer un service complet.  

Overhead structurel faible.

> Coût du conteneur NixUnits limité

---

## Installation

### NixOS

Dans `flake.nix` :

```nix
{
  inputs.nixunits.url = "github:.../nixunits";

  outputs = { self, nixunits, nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        nixunits.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

ou :

```nix
environment.systemPackages = [
  nixunits.packages.${system}.nixunits
];
```

### Debian + Nix

* Dépendance : systemd-container 
* Les dépendances sur une infra non NixOS sont traités avec le store nix.
* Le développement est initié depuis NixOS et est testé sous Debian : des oublis/bug peuvent exister => contact@aevoo.fr 

```bash
nix run github:dcasier/nixunits#portable
```

---

## Démarrage rapide


**web2.json**
```json
{
  "id": "web2",
  "ip4": "192.168.20.2/31",
  "hostIp4": "192.168.20.1/31"
}
```

**web_default.nix**
```nix
{ pkgs, properties, lib, ... }: let 
  get = path: default: lib.attrByPath path default properties;
  ip4     = get [ "ip4" ]             "10.0.0.2/31";
  hostIp4 = get [ "hostIp4" ]         "10.0.0.1/31";
in {
  caps_allow = [ "CAP_NET_BIND_SERVICE" ];

  network.interfaces.veth = {
    inherit ip4 hostIp4;
  };

  config = {
    services.httpd.enable = true;
    system.stateVersion = "25.05";
  };
}
```

Build + start :

```bash
nixunits build -n ./web_default.nix -j ./web2.json -s
```

Inspection :

```bash
journalctl -M web2 -b
journalctl -u nixunits@web2 -f
journalctl -M web2 -u httpd
nixunits shell web2
```

---

## Architecture

```
Host (Linux systemd)
 └─ systemd-nspawn (machine.slice)
     ├─ /var/lib/nixunits/store/default/root  ← base NixOS ro
     └─ /var/lib/nixunits/containers/<id>/
         ├─ root/     ← writable
         ├─ (work/)
         ├─ (merged/)
         └─ unit.conf ← paramètres runtime générés
```

Cycle de build :

1. build de base (store default)
2. overlay et build final (propriétés du conteneur)

---

## Important

### Build et overlay

Les paramètres spécifiques à un conteneur (IP, noms, ...) doivent être fournis via properties.json.
Le contenu de config.nix sera présent dans le store partagé (par défaut) aux autres conteneurs.

> Cela ne concerne pas la **gestion des secrets**, qui reste identique à une configuration Nix standard.

Exemple :

✓ Correct (données propres au conteneur)
```json
{ "ip4": "10.0.0.2/31" }
```

✗ Incorrect (stocké dans le store partagé)
```nix
network.interfaces.veth.ip4 = "10.0.0.2/31";
```



### Conteneur "PID 1" mais **minimaliste**

Systemd n'a pour fonction que de s'assurer du bon fonctionnement des services et de la gestion des logs.

> D-Bus n’est pas fourni par défaut dans un conteneur NixUnits.

Activé :
 - Gestion des logs (depuis le host ou le conteneur)
 - Gestion des process, dans le conteneur (stop, restart, ...)
 - Services de base systemd

## Exemple avancé

**properties.json**
```json
{
  "id": "router1",
  "bridge":  "br0",
  "ip4": "10.0.0.2/16",
  "ip6":  "a:b:c:d::e/64",
  "vlan": 4356,
  "bridgeWan":  "br0",
  "ip4Wan": "70.0.0.2/31",
  "ip6Wan":  "2001:bc8::a/64",
  "vlanWan": 356,
  "ip4route":  "20.0.0.254",
  "ip6route": "2001:bc8::ffff:ffff:ffff:fffe"
}
```

**config.nix**
```nix
{ pkgs, properties, lib, ... }: let 
  get = path: default: lib.attrByPath path default properties;
  bridge    = get [ "bridge" ]     "br0";
  ip4       = get [ "ip4" ]        "192.168.0.2/24";
  ip6       = get [ "ip6" ]        "a:b:c:d::e/64";
  vlan      = get [ "vlan" ]        4356;
  bridgeWan = get [ "bridgeWan" ]  "br0";
  ip4Wan    = get [ "ip4Wan" ]     "20.0.0.2/31";
  ip6Wan    = get [ "ip6Wan" ]     "fe80::a/64";
  vlanWan   = get [ "vlanWan" ]     356;
  ip4route  = get [ "ip4route" ]   "20.0.0.254";
  ip6route  = get [ "ip6route" ]   "fe80::ffff:ffff:ffff:fffe";
in {
  bind = [
    "/srv/logs:/var/log/service:ro"
  ];
  caps_allow = [ "CAP_NET_ADMIN" ];

  config = {
    services.dnsmasq.enable = true;
    system.stateVersion = "25.05";
  };
  extra = ''
    # Contenu évalué par /bin/sh sur le conteneur 
  '';
  # netns_path = # incompatible avec la déclaration des interfaces et avec "private-user" (c.f. doc systemd-nspawn) 

  network = {
    interfaces = {
        lan = {
          inherit ip4 ip6;
          ovs = {
            inherit bridge vlan;
          };
        };
        wan = {
          ip4 = ip4Wan;
          ip6 = ip6Wan;
          ovs = {
            bridge = bridgeWan;
            vlan = vlanWan;
          };
        };
    };
    nft = ''
        table inet filter {
          chain input {
            type filter hook input priority 0;
            accept
          }
        }
    '';  
    inherit ip4route ip6route;
  };
  nspawnArgs = ""; # Args systemd-nspawn 
  sysctl = ''
    net.ipv4.ip_forward=1
  '';
}
```

> Définitions déclarées dans le fichier nix/global.nix

---

## Limitations

Ce projet est sous statut **expérimental**.
Certaines fonctionnalités réseau nécessitent une configuration préalable sur l’hôte :

| Fonction | Requis |
|---------|--------|
| Interfaces réseaux | veth, OVS, bridge, netns configurés |
| OVS / VLAN | openvswitch installé |
| nft | nftables actif |
| netns_path | ip netns (ou équivalent) |

Hormis pour OVS/private-network, nixUnits **n’automatise pas** le provisionnement réseau sur l’hôte.

## Comparatif Docker / Podman vs NixUnits

| Critère | Docker / Podman | NixUnits |
|--------|----------------|----------|
| Cible | Applications conteneurisées | Services NixOS isolés |
| Construction | Dockerfile / OCI | Dérivations Nix (déclaratif) |
| Distribution | Registres d’images | Code source Nix + store |
| Système dans le conteneur | Pas nécessairement de systemd | Systemd-minimal |
| Orchestration | Docker CLI, compose, K8s | Aevoo, systemctl, machinectl (ou déclaratif Nixos) |
| Sécurité | Configuration de runtime | Déclaratif (nix) |
| Portabilité | portable | Linux systemd uniquement |
| Usage modèle | Dev & CI, portabilité applicative | Ops Nix sur infrastructure systemd |

NixUnits ne vise pas à remplacer Docker/Podman.
Il est conçu pour exécuter des **services NixOS** (sur le marketplace Aevoo) isolés sur un hôte Linux systemd,
avec un contrôle réseau et une configuration entièrement déclaratifs.

---

## CLI

```
nixunits <action> [options]
```

| Action | Effet |
|--------|------|
| build <id> | créer ou mettre à jour le conteneur |
| start / restart / status | gestion systemd |
| shell / nsenter | entrer dans le conteneur |
| list | conteneurs déclarés et actifs |
| delete <id> | supprimer le conteneur |
| * | wrapper machinectl $@ |

---

## Dépannage

* Option nix build -d active --show-trace
* Solution testée sous Debian et NixOS
* La gestion des logs est assurée par journalctl -M <machineID>
* Pour toute question : contact@aevoo.fr

## Sécurité déclarative

* User Namespace activé sauf `netns_path` spécifié
* Capabilities explicites

```nix
caps_allow = [ "CAP_NET_BIND_SERVICE" ];
```

> Politique stricte par défaut, ouverture volontaire.

---

