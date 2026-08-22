#!/usr/bin/env bash
# =============================================================================
# install.sh — Installation du hub domotique (Home Assistant + Mosquitto +
# Zigbee2MQTT + Tailscale) sur Debian 12/13 x86_64.
#
# Cahier des charges : docs/spec-installation.md
# Strictement idempotent : une ré-exécution ne produit aucun changement
# destructif. Chaque phase détecte son état déjà-fait et saute.
#
# Usage : ./install.sh
#   - En root directement, ou
#   - En tant qu'utilisateur sudo : le script se ré-exécute automatiquement
#     via sudo (documenté dans la spec).
# =============================================================================
set -euo pipefail

# --- Répertoire du script (racine du dépôt) ---------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
cd "$REPO_DIR"

# --- Journalisation ----------------------------------------------------------
# Préfixes de phase [1/7] etc. et niveaux INFO/WARN/ERREUR.
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$1" "$2"; }
info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; }
err()  { printf '\033[1;31m[ERREUR]\033[0m %s\n' "$1" >&2; }

# --- Ré-exécution sudo si non-root ------------------------------------------
# Le script est prévu pour tourner en root. S'il est lancé par un utilisateur
# sudo, on se ré-exécute via sudo (documenté dans la spec).
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    info "Non-root : ré-exécution via sudo."
    exec sudo -E bash "$0" "$@"
  else
    err "Ce script doit être exécuté en root (ou via sudo)."
    exit 1
  fi
fi

# --- Chargement du .env ------------------------------------------------------
# Lit le .env s'il existe (généré depuis .env.example). Simple parseur
# KEY=VALUE, robuste aux commentaires et guillemets — le fichier n'est jamais
# exécuté.
load_env() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS='=' read -r key value; do
    [[ -z "$key" ]] && continue
    [[ "$key" == \#* ]] && continue
    key="${key%%[[:space:]]*}"
    value="${value%%[[:space:]]*}"
    value="${value#\"}"; value="${value%\"}"
    value="${value#\'}"; value="${value%\'}"
    export "$key=$value"
  done < "$file"
}
load_env .env

# Valeurs par défaut (alignées sur .env.example).
TZ="${TZ:-Europe/Paris}"
ZIGBEE_CHANNEL="${ZIGBEE_CHANNEL:-25}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
HOSTNAME="${HOSTNAME:-}"

# --- Phase 1 : Preflight -----------------------------------------------------
log "1/7" "Preflight"

# 1.1 Architecture x86_64
if [[ "$(uname -m)" != "x86_64" ]]; then
  err "Architecture non supportée : $(uname -m). Ce script cible x86_64 (Intel N100)."
  exit 1
fi
info "Architecture x86_64 OK."

# 1.2 Connectivité internet
if ! curl -fsSL --max-time 10 https://deb.debian.org >/dev/null 2>&1; then
  err "Pas de connectivité internet. Vérifiez le réseau du mini PC."
  exit 1
fi
info "Connectivité internet OK."

# 1.3 Droits root (déjà assurés par la ré-exécution sudo)
if [[ $EUID -ne 0 ]]; then
  err "Droits root requis."
  exit 1
fi
info "Droits root OK."

# 1.4 Espace disque ≥ 10 Go sur /
avail_kb=$(df -Pk / | awk 'NR==2 {print $4}')
avail_gb=$((avail_kb / 1024 / 1024))
if (( avail_gb < 10 )); then
  err "Espace disque insuffisant sur / : ${avail_gb} Go disponibles (≥ 10 Go requis)."
  exit 1
fi
info "Espace disque OK : ${avail_gb} Go disponibles sur /."

# 1.5 Présence du dongle Zigbee (Silicon Labs)
# On matche sur le nom vendeur (case-insensitive), pas sur un ID USB constant
# (REQ-INS-003). Échec explicite AVANT toute modification du système.
if ! lsusb | grep -qi "silicon labs"; then
  err "Dongle Zigbee (Silicon Labs) introuvable via lsusb."
  err "Branchez le dongle Home Assistant Connect ZBT-2 (rallonge USB 2.0) puis relancez."
  exit 1
fi
info "Dongle Zigbee (Silicon Labs) détecté."

# --- Phase 2 : Base système --------------------------------------------------
log "2/7" "Base système"

# 2.1 Paquets apt requis
# mosquitto-clients fournit mosquitto_passwd (génération du fichier de mots de
# passe Mosquitto en phase 4).
required_pkgs=(ca-certificates curl gnupg jq mosquitto-clients)
missing_pkgs=()
for pkg in "${required_pkgs[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing_pkgs+=("$pkg")
  fi
done
if (( ${#missing_pkgs[@]} > 0 )); then
  info "Installation des paquets : ${missing_pkgs[*]}"
  apt-get update -y
  apt-get install -y "${missing_pkgs[@]}"
else
  info "Paquets requis déjà présents, sauté."
fi

# 2.2 Docker Engine (idempotent)
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  info "Docker déjà présent et fonctionnel, installation sautée."
  if ! docker compose version >/dev/null 2>&1; then
    info "Plugin docker compose absent, installation de docker-compose-plugin."
    apt-get update -y
    apt-get install -y docker-compose-plugin
  else
    info "Plugin docker compose présent, sauté."
  fi
else
  info "Installation de Docker Engine depuis le repo apt officiel."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $codename stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

# 2.3 Utilisateur dans le groupe docker
# L'utilisateur réel (celui qui a lancé le script via sudo) est ajouté au groupe
# docker s'il n'y est pas déjà. Root n'en a pas besoin.
target_user="${SUDO_USER:-root}"
if [[ "$target_user" != "root" ]] && ! id -nG "$target_user" | grep -qw docker; then
  usermod -aG docker "$target_user"
  info "Utilisateur '$target_user' ajouté au groupe docker."
else
  info "Utilisateur '$target_user' déjà dans le groupe docker (ou root), sauté."
fi

# --- Phase 3 : Persistance série ---------------------------------------------
log "3/7" "Persistance série"

# 3.1 Résolution de DONGLE_PATH via /dev/serial/by-id
# On cherche un lien by-id pointant vers un ttyUSB* ou ttyACM*, dont le nom
# encode le vendeur Silicon Labs. Le chemin by-id est stable au redémarrage,
# contrairement à /dev/ttyUSB0 (REQ-INS-007).
dongle_path=""
for link in /dev/serial/by-id/*; do
  [[ -e "$link" ]] || continue
  target=$(readlink -f "$link")
  if [[ "$target" == *ttyUSB* || "$target" == *ttyACM* ]]; then
    if [[ "$(basename "$link")" =~ [Ss]ilicon[_-]?[Ll]abs ]]; then
      dongle_path="$link"
      break
    fi
  fi
done

if [[ -z "$dongle_path" ]]; then
  err "Impossible de résoudre le chemin série persistant du dongle Silicon Labs."
  err "Vérifiez que le dongle est branché et que /dev/serial/by-id existe."
  exit 1
fi
info "Dongle résolu : $dongle_path"

# 3.2 Écriture idempotente dans .env
# Crée .env depuis .env.example s'il n'existe pas ; ne l'écrase jamais ensuite.
if [[ ! -f .env ]]; then
  cp .env.example .env
  info ".env créé depuis .env.example."
else
  info ".env déjà présent, conservé."
fi

if grep -q '^DONGLE_PATH=' .env; then
  info "DONGLE_PATH déjà présent dans .env, sauté."
else
  echo "DONGLE_PATH=$dongle_path" >> .env
  info "DONGLE_PATH écrit dans .env."
fi

# Recharge le .env pour que les phases suivantes disposent de DONGLE_PATH.
load_env .env

# 3.3 Utilisateur dans le groupe dialout (accès série)
if [[ "$target_user" != "root" ]] && ! id -nG "$target_user" | grep -qw dialout; then
  usermod -aG dialout "$target_user"
  info "Utilisateur '$target_user' ajouté au groupe dialout."
else
  info "Utilisateur '$target_user' déjà dans le groupe dialout (ou root), sauté."
fi

# --- Phase 4 : Génération des configs ----------------------------------------
log "4/7" "Génération des configs"

# 4.1 Secrets (générés une seule fois, hors git — REQ-INS-004)
mkdir -p secrets/mosquitto
mqtt_user="mqtt"
passwd_file="secrets/mosquitto/passwd"

# Mot de passe MQTT : généré une seule fois (openssl rand -hex).
if [[ -f secrets/mosquitto/mqtt_password ]]; then
  mqtt_password=$(cat secrets/mosquitto/mqtt_password)
  info "Mot de passe MQTT déjà généré, sauté."
else
  mqtt_password=$(openssl rand -hex 24)
  printf '%s' "$mqtt_password" > secrets/mosquitto/mqtt_password
  chmod 600 secrets/mosquitto/mqtt_password
  info "Mot de passe MQTT généré."
fi

# Création de l'utilisateur MQTT (mosquitto_passwd idempotent).
if [[ -f "$passwd_file" ]]; then
  info "Fichier de mots de passe Mosquitto déjà présent, sauté."
else
  mosquitto_passwd -b "$passwd_file" "$mqtt_user" "$mqtt_password"
  # Lisible par le conteneur (l'utilisateur mosquitto du conteneur lit ce fichier).
  chmod 644 "$passwd_file"
  info "Utilisateur MQTT '$mqtt_user' créé."
fi

# 4.2 Rendu des templates (jamais d'écrasement — REQ-INS-002)
# Remplace les placeholders {{VAR}} par les valeurs. Si le fichier cible existe
# déjà, il est conservé tel quel (idempotence).
# NB : TZ et DONGLE_PATH ne sont pas injectés ici — ils le sont par docker
# compose via l'interpolation ${TZ} / ${DONGLE_PATH} du fichier .env.
render_template() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]]; then
    info "Config déjà présente : $dst (sautée)."
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  sed -e "s|{{MQTT_USER}}|$mqtt_user|g" \
      -e "s|{{MQTT_PASSWORD}}|$mqtt_password|g" \
      -e "s|{{ZIGBEE_CHANNEL}}|$ZIGBEE_CHANNEL|g" \
      "$src" > "$dst"
  info "Config générée : $dst"
}

render_template templates/mosquitto.conf config/mosquitto/mosquitto.conf
render_template templates/zigbee2mqtt/configuration.yaml config/zigbee2mqtt/configuration.yaml
render_template templates/homeassistant/configuration.yaml config/homeassistant/configuration.yaml

# --- Phase 5 : Déploiement ---------------------------------------------------
log "5/7" "Déploiement"

# S'assure que /dev/net/tun existe (requis par Tailscale).
if [[ ! -e /dev/net/tun ]]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200 2>/dev/null || true
  chmod 600 /dev/net/tun
fi

docker compose up -d

# --- Phase 6 : Tailscale -----------------------------------------------------
log "6/7" "Tailscale"

if [[ -z "$TAILSCALE_AUTHKEY" ]]; then
  info "Aucune clé d'authentification Tailscale (TAILSCALE_AUTHKEY vide)."
  info "Le conteneur tailscale est démarré en mode login interactif."
  info "Récupérez l'URL de login :"
  info "  docker compose logs tailscale"
  info "  → cherchez la ligne 'To authenticate, visit: https://login.tailscale.com/a/...'"
  info "Ouvrez cette URL dans un navigateur pour associer le nœud au réseau."
else
  info "Clé d'authentification Tailscale fournie : le conteneur s'authentifie automatiquement."
  # Force un up explicite au cas où le conteneur n'a pas encore rejoint.
  docker compose exec -T tailscale tailscale up --authkey="$TAILSCALE_AUTHKEY" >/dev/null 2>&1 || true
fi

# --- Phase 7 : Vérification finale -------------------------------------------
log "7/7" "Vérification finale"

# 7.1 Home Assistant : HTTP 200 sur http://localhost:8123
# Premier démarrage long : jusqu'à 60 tentatives espacées de 2 s (~120 s).
ha_ok=0
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null --max-time 5 http://localhost:8123; then
    ha_ok=1
    break
  fi
  sleep 2
done
if (( ha_ok )); then
  info "Home Assistant répond HTTP 200 sur http://localhost:8123."
else
  err "Home Assistant ne répond pas HTTP 200 après ~120 s."
  err "Consultez les logs : docker compose logs homeassistant"
  exit 10
fi

# 7.2 Mosquitto : port 1883 joignable sur 127.0.0.1
if timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/1883' 2>/dev/null; then
  info "Mosquitto joignable sur 127.0.0.1:1883."
else
  err "Mosquitto injoignable sur 127.0.0.1:1883."
  err "Consultez les logs : docker compose logs mosquitto"
  exit 11
fi

# 7.3 Zigbee2MQTT : répond sur 8080 ET voit le coordinateur
# L'interface web (8080) répond en HTTP. La détection du coordinateur est
# vérifiée dans les logs : la ligne "Coordinator firmware version" n'apparaît
# que si le dongle est détecté et initialisé. (L'API GET /api du frontend est
# un WebSocket, pas un endpoint HTTP GET — d'où le choix des logs.)
z2m_ok=0
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null --max-time 5 http://localhost:8080 \
     && docker compose logs zigbee2mqtt 2>/dev/null | grep -qi "coordinator firmware version"; then
    z2m_ok=1
    break
  fi
  sleep 2
done
if (( z2m_ok )); then
  info "Zigbee2MQTT répond sur 8080 et voit le coordinateur."
else
  err "Zigbee2MQTT ne répond pas correctement ou ne voit pas le coordinateur."
  err "Consultez les logs : docker compose logs zigbee2mqtt"
  exit 12
fi

# 7.4 Tous les conteneurs Up
# Version-safe : `docker compose ps --status running --services` liste les
# services en cours, sans dépendre du format JSON de `--format json` (qui varie
# entre NDJSON et tableau selon les versions de compose).
all_up=1
for svc in homeassistant mosquitto zigbee2mqtt tailscale; do
  if ! docker compose ps --status running --services 2>/dev/null | grep -qx "$svc"; then
    all_up=0
    err "Conteneur '$svc' non démarré (état != running)."
  fi
done
if (( all_up )); then
  info "Tous les conteneurs sont Up."
else
  err "Certains conteneurs ne sont pas Up."
  err "Consultez : docker compose ps"
  exit 13
fi

# --- Récapitulatif final -----------------------------------------------------
ip_addr=$(hostname -I | awk '{print $1}')
info "=== Hub domotique installé avec succès ==="
info "Interface locale : http://${ip_addr}:8123"
info ""
info "Étapes post-install manuelles (spec-installation.md) :"
info "  1. Onboarding Home Assistant : créez le compte admin via le wizard sur http://${ip_addr}:8123"
info "  2. App mobile : installez l'app compagnon HA et connectez-la (réseau local ou Tailscale)"
info "  3. Appairage Zigbee : via l'interface Zigbee2MQTT (http://${ip_addr}:8080) ou l'intégration HA"
info "  4. Vérifiez que le canal Zigbee (${ZIGBEE_CHANNEL}) ne chevauche pas le Wi-Fi (canaux 1, 6, 11)"
exit 0
