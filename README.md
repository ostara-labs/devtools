# home

Hub domotique personnel — Home Assistant en socle, installé et configuré par un script unique.

## Contenu

- [`docs/spec-materiel.md`](docs/spec-materiel.md) — spécification matérielle : BOM, décisions d'achat, pièges connus.
- [`docs/spec-installation.md`](docs/spec-installation.md) — spécification d'installation : contrat du script unique `scripts/install.sh` (à implémenter).

## Principe

Une machine dédiée (mini PC Intel N100), Debian minimal, puis **une seule commande** :

```bash
./install.sh
```

…qui mène de l'OS vierge à un hub fonctionnel : Docker Compose {Home Assistant, Mosquitto, Zigbee2MQTT, Tailscale}, configs générées depuis les templates du repo, vérification finale automatique.

## Statut

🚧 En spécification. Prochaine étape : implémentation de `scripts/install.sh` conforme à `spec-installation.md`.
