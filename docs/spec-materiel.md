---
title: Spécification matérielle du socle domotique
version: 0.1.0
date: 2026-08-23
status: draft
---

# Spécification matérielle du socle domotique

## TL;DR

Une seule boîte matérielle dédiée héberge Home Assistant (HA Container sous
Docker Compose sur Debian, voir [spec-installation.md](spec-installation.md)).
Le cœur est un mini PC Intel N100 à refroidissement passif, relié au réseau par
câble Ethernet, avec un dongle Zigbee Home Assistant Connect ZBT-2 branché sur
une rallonge USB 2.0. L'accès distant passe exclusivement par Tailscale, et
l'app mobile est l'application compagnon officielle de Home Assistant. Budget
cible : environ 200 € en base Zigbee, environ 255 € avec l'option Z-Wave.

## Tableau BOM

| Composant | Modèle | Prix indicatif EUR (août 2026) | Rôle | Statut |
|---|---|---|---|---|
| Mini PC | Intel N100 (classe Beelink Mini S12 / GMKtec NucBox), quad-core, 8–16 Go RAM, NVMe 256–500 Go inclus, refroidissement passif | 140–180 | Hôte de Home Assistant, Docker Compose, Debian | OBLIGATOIRE |
| Dongle Zigbee | Home Assistant Connect ZBT-2 (USB-C, Silicon Labs EFR32MG24) | ~45 | Coordinateur Zigbee 3.0, appairage et pilotage des appareils | OBLIGATOIRE |
| Rallonge USB | Rallonge USB 2.0 (≥ 1 m) | ~8 | Éloigne le dongle des ports USB 3.0 et du routeur Wi-Fi | OBLIGATOIRE |
| Câble Ethernet | Câble RJ45 (catégorie 5e ou supérieure) | déjà possédé probablement | Liaison filaire du mini PC au routeur | OBLIGATOIRE (si non possédé, ~10) |
| Dongle Z-Wave | Home Assistant Connect ZWA-2 | ~59 | Z-Wave pour volets roulants et serrures | OPTIONNEL |
| Onduleur | Onduleur compact (classe 600–800 VA) | ~40–60 | Protection du mini PC contre les microcoupures | OPTIONNEL |

Total indicatif : ~193 € en base Zigbee (mini PC 150 + ZBT-2 45 + rallonge 8),
~252 € avec l'option Z-Wave (ZWA-2 59). Ces montants sont des ordres de
grandeur, les prix réels variant selon les revendeurs et les promotions.

## Décisions argumentées

### DEC-MAT-001 : le mini PC Intel N100 est retenu comme hôte

Comparaison des trois candidats sérieux :

- **Raspberry Pi 5, 8 Go, correctement équipé** : la carte seule coûte environ
  90 €, mais il faut ajouter l'alimentation et le boîtier avec refroidissement
  actif (~35 €) puis un HAT PCIe et un NVMe (~55 €) pour un stockage fiable.
  Total réaliste : environ 180 €. Le Pi 5 est une excellente carte, mais son
  coût final rejoint celui d'un mini PC tout inclus.
- **Mini PC Intel N100** : environ 150 € tout inclus (RAM, NVMe, alimentation,
  boîtier). Il offre environ 3 à 4 fois la puissance CPU du Pi 5, une
  architecture x86 qui garantit une compatibilité Docker totale (aucune image
  à recompiler pour ARM), et un refroidissement passif donc silencieux et sans
  pièce mobile à entretenir.
- **Home Assistant Green** : 179 €, soit un prix doublé depuis 2023. La boîte
  est fermée et non extensible : pas de RAM supplémentaire, pas de stockage
  évolutif, pas de possibilité d'ajouter un disque pour des caméras.

**Décision** : le N100 est retenu pour sa marge CPU, qui laisse de la place
pour Frigate et des caméras plus tard, pour sa compatibilité Docker totale et
pour son refroidissement passif. Le Green est écarté car fermé et non
extensible ; le Pi 5 est écarté car son coût équipé ne justifie pas sa
puissance inférieure.

### DEC-MAT-002 : un seul dongle ZBT-2 au départ, contrainte XOR

Le Home Assistant Connect ZBT-2 (Silicon Labs EFR32MG24) fait du Zigbee 3.0
**ou** du Thread, mais jamais les deux simultanément. Le mode multiprotocole
MultiPAN, qui permettrait de faire les deux à la fois, est rejeté par Nabu Casa
car jugé instable.

**Décision** : le choix initial est le Zigbee, pour son plus grand catalogue
d'appareils peu chers et son maillage automatique. Le Thread et Matter seront
ajoutés plus tard via un second dongle dédié, branché sur un autre port. Les
prédécesseurs ZBT-1 et le kit Yellow ont été discontinués fin 2025, donc le
ZBT-2 est le choix d'avenir.

### DEC-MAT-003 : la rallonge USB 2.0 est obligatoire

Les ports USB 3.0 émettent des interférences dans la bande des 2,4 GHz, celle
du Zigbee. Un dongle branché directement sur un port USB 3.0 peut subir 5 à
15 % de pertes de paquets Zigbee, ce qui se traduit par des commandes lentes ou
perdues.

**Décision** : le dongle est branché sur une rallonge USB 2.0, et placé à au
moins 3 mètres du routeur Wi-Fi. Cette distance réduit aussi le risque de
collision entre le canal Zigbee et les canaux Wi-Fi voisins.

### DEC-MAT-004 : le plan de canaux est figé avant l'appairage

Le Zigbee et le Wi-Fi partagent la bande des 2,4 GHz. Changer le canal Zigbee
après l'appairage oblige à ré-appairer tous les appareils, une opération
fastidieuse.

**Décision** : avant tout appairage, on fixe le canal Zigbee sur 25 ou 26, et
le Wi-Fi sur les canaux 1, 6 ou 11, en évitant les chevauchements. Ce plan est
écrit et vérifié une fois pour toutes.

### DEC-MAT-005 : stockage NVMe exclusif, cartes SD interdites

Les cartes SD ne sont pas conçues pour une écriture continue 24/7 : elles se
corrompent rapidement sous la charge d'une base de données SQLite et des logs
de Home Assistant.

**Décision** : le stockage principal est exclusivement un NVMe. Aucune carte SD
n'est utilisée comme stockage principal, ni même comme stockage de secours.

## Exigences

### REQ-MAT-001 : budget total maîtrisé

- **Étant donné** un socle configuré en Zigbee seul,
- **Quand** on additionne le mini PC, le dongle ZBT-2 et la rallonge USB,
- **Alors** le total est inférieur ou égal à 260 €.

### REQ-MAT-002 : consommation électrique maîtrisée

- **Étant donné** le socle en fonctionnement normal, sans tâche lourde,
- **Quand** on mesure la consommation au repos (idle),
- **Alors** elle est inférieure ou égale à 15 W.

### REQ-MAT-003 : disponibilité en France

- **Étant donné** une commande de l'ensemble du matériel,
- **Quand** on vérifie les revendeurs,
- **Alors** chaque composant est disponible en livraison en France.

### REQ-MAT-004 : dongle adressable de façon persistante

- **Étant donné** le dongle ZBT-2 branché sur la rallonge USB,
- **Quand** on liste les périphériques série du système,
- **Alors** le dongle est adressable par un chemin persistant de type
  `/dev/serial/by-id/...`, stable entre les redémarrages.

## Évolutions futures possibles

La marge CPU du N100 ouvre plusieurs pistes, sans changer de boîte :

- **Frigate et caméras** : détection d'objets par IA sur le flux vidéo, rendue
  possible par la puissance CPU disponible.
- **ESPHome** : compiler et flasher des firmwares pour des capteurs et actionneurs
  personnalisés.
- **Music Assistant** : serveur audio multi-pièces.
- **Second dongle Thread/Matter** : ajouter le Thread et Matter pour des
  appareils compatibles, sans toucher au Zigbee existant.
- **ZWA-2 Z-Wave** : piloter des volets roulants et des serrures Z-Wave, en
  complément du Zigbee.

## Sécurité et limites d'usage

### Toujours

- Brancher le dongle sur une rallonge USB 2.0.
- Fixer le plan de canaux avant tout appairage.
- Utiliser un stockage NVMe.
- Relier le mini PC au réseau par câble Ethernet.

### Demander d'abord

- Ajouter le module Z-Wave (ZWA-2).
- Changer le canal Zigbee après l'appairage (ré-appairage complet requis).
- Ajouter un second dongle Thread/Matter.
- Ajouter un onduleur ou modifier l'alimentation.

### Jamais

- Utiliser une carte SD comme stockage principal.
- Brancher le dongle directement sur un port USB 3.0.
- Exposer Home Assistant directement sur Internet (accès distant par Tailscale
  uniquement).

## Glossaire

- **Zigbee** : protocole radio basse consommation (2,4 GHz) pour la domotique,
  basé sur un maillage automatique.
- **Thread** : protocole radio maillé basse consommation, conçu pour Matter.
- **Matter** : standard d'interopérabilité unifié pour la domotique, qui
  s'appuie sur Thread ou le Wi-Fi.
- **Coordinateur** : le nœud central d'un réseau Zigbee, qui gère l'appairage
  et le routage des messages.
- **Mesh** : maillage, topologie où chaque appareil relaie les messages des
  autres pour étendre la portée.
- **Z-Wave** : protocole radio domotique propriétaire (bande sub-GHz), apprécié
  pour les volets roulants et les serrures.
- **MultiPAN** : mode multiprotocole permettant à un seul dongle de faire du
  Zigbee et du Thread simultanément, jugé instable par Nabu Casa.
