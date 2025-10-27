# NixUnits

Exécutez des services **NixOS** dans des conteneurs **légers**, **déclaratifs**, et **isolés**.

NixUnits combine :

* **NixOS** dans le conteneur  
  Le service fonctionne dans un environnement système minimal et reproductible.
* **systemd-nspawn** sur l’hôte  
  Pas de runtime supplémentaire, orchestration native via `systemctl` et `machinectl`.
* **Overlay Nix store partagé**  
  Duplication minimale entre conteneurs.
* **Réseau configurable**  
  Interfaces, IPs, OVS, VLAN, netns, routes.
* **Sécurité explicite**  
  Capabilities contrôlées par la déclaration Nix.

---

## Pourquoi NixUnits ?

| Besoin | Réponse |
|--------|---------|
| Déployer un service NixOS isolé | Un conteneur = un service |
| Éviter Dockerfile, couches mutables | Configuration **Nix** uniquement |
| Utiliser systemd pour orchestrer | Unités `nixunits@<id>.service` |
| Réseau adapté à la production | Définition déclarative |
| Sécurité lisible | Capabilities définies dans la config du conteneur |

> Ce qui est déclaré est **exactement** ce qui est exécuté.

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

## Systemd minimal

Présent :  
✓ PID 1  
✓ journald conteneur  
✓ services déclarés  
✓ cgroups/slice dédiée

Supprimé :  
✗ logind  
✗ getty  
✗ user-sessions  
✗ coredumpd  
✗ autres services inutiles pour un workload conteneurisé

> Suffisant pour orchestrer un service complet.  

---

## Empreinte mémoire et processus

Un conteneur NixUnits lance généralement :

* systemd-minimal (PID1)
* journald interne
* le service principal + auxiliaires

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

### Debian/Ubuntu + Nix

Dépendances : systemd-container, overlayfs, yq

```bash
nix run #portable --install
nixunits-install
```

---

## Démarrage rapide (OVS + VLAN)

**properties.json**
```json
{
  "id": "web2",
  "ip4": "192.168.20.10/24",
  "bridge": "brsrv",
  "vlan": 30
}
```

**config.nix**
```nix
{ pkgs, properties, lib, ... }: {
  caps_allow = [ "CAP_NET_BIND_SERVICE" ];

  network.interfaces = {
    "eth0" = {
      ip4 = properties.ip4;
      ovs = {
        bridge = properties.bridge;
        vlan = properties.vlan;
      };
    };
  };

  config = {
    services.nginx.enable = true;
    system.stateVersion = "25.05";
  };
}
```

Build + start :

```bash
nixunits build web2 -n config.nix -j properties.json -s
```

Inspection :

```bash
journalctl -u nixunits@web2 -f
nixunits shell web2
```

---

## Réseau : exemples avancés

### Deux interfaces OVS + VLANs

**properties.json**
```json
{
  "id": "router1",
  "bridgeLan": "br-lan",
  "vlanLan": 10,
  "bridgeWan": "br-wan",
  "vlanWan": 20,
  "ipLan": "192.168.10.1/24",
  "ipWan": "10.0.0.2/24"
}
```

**config.nix**
```nix
{ pkgs, properties, lib, ... }: {
  caps_allow = [ "CAP_NET_ADMIN" ];

  network.interfaces = {
    lan = {
      ip4 = properties.ipLan;
      ovs = {
        bridge = properties.bridgeLan;
        vlan = properties.vlanLan;
      };
    };
    wan = {
      ip4 = properties.ipWan;
      ovs = {
        bridge = properties.bridgeWan;
        vlan = properties.vlanWan;
      };
    };
  };

  config = {
    services.dnsmasq.enable = true;
    system.stateVersion = "25.05";
  };
}
```

---

### Injection nftables dans le conteneur

**properties.json**
```json
{
  "id": "fw1",
  "ip4": "192.168.50.10/24",
  "nft": "table inet filter {\n  chain input {\n    type filter hook input priority 0;\n    accept\n  }\n}"
}
```

**config.nix**
```nix
{ pkgs, properties, ... }: {
  network.interfaces.eth0.ip4 = properties.ip4;

  config = {
    services.nginx.enable = true;
    system.stateVersion = "25.05";
  };
}
```

---

### Paramètres sysctl spécifiques au conteneur

**properties.json**
```json
{
  "id": "rt1",
  "ip4": "192.168.99.1/24",
  "sysctl": "net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1"
}
```

**config.nix**
```nix
{ pkgs, properties, ... }: {
  network.interfaces.eth0.ip4 = properties.ip4;

  config = {
    services.frr.zebra.enable = true;
    system.stateVersion = "25.05";
  };
}
```

---

## CLI

```
nixunits <action> [options]
```

Actions principales :

| Action | Effet |
|--------|------|
| build <id> | créer ou mettre à jour le conteneur |
| start / restart / status | gestion systemd |
| shell / nsenter | entrer dans le conteneur |
| list | conteneurs déclarés et actifs |
| delete <id> | supprimer le conteneur |

---

## Sécurité déclarative

* User Namespace activé sauf `netns_path`
* Capabilities explicites

```nix
caps_allow = [ "CAP_NET_BIND_SERVICE" ];
```

> Politique stricte par défaut, ouverture volontaire.

---

## Support

* Linux avec systemd PID1
* OverlayFS
* Nix (runtime + build)

NixOS : prise en charge complète  
Debian/Ubuntu : support fonctionnel via `nixunits-install`

Certaines fonctionnalités réseau nécessitent des composants préalablement configurés sur l’hôte.

---

## Cas d’usage

* Services réseau isolés : nginx, dnsmasq, frr, powerdns…
* Déploiement NixOS sur des hôtes non NixOS
* Séparation stricte de responsabilités
* Reproductibilité des environnements multi-services

---

## État du projet

Opérationnel dans des environnements Aevoo.  
Évolution continue selon besoins utilisateurs.

---

### Résumé

> NixUnits exécute **des services NixOS** isolés  
> sans daemon supplémentaire  
> avec un réseau configurable et une sécurité explicite.

> **Nix + systemd**. Rien d’autre.

