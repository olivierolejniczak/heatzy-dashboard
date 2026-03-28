#!/usr/bin/env bash
# ==============================================================================
# install_heatzy_monitor.sh
# Installation du daemon Heatzy Monitor sur DietPi x86
# À exécuter en root : sudo bash install_heatzy_monitor.sh
# ==============================================================================

set -euo pipefail

# ── Palette ANSI daltonisme-safe (Cyan/Magenta) ───────────────────────────────
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
YELLOW='\033[1;33m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error() { echo -e "${MAGENTA}[ERROR]${RESET} $*" >&2; }

# ── Vérifications préalables ──────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Ce script doit être exécuté en root (sudo)."
    exit 1
fi

info "=== Installation Heatzy Monitor v1.0 ==="

# Vérification Python 3.7+
if ! command -v python3 &>/dev/null; then
    error "Python 3 introuvable. Installer avec : apt install python3"
    exit 1
fi
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
info "Python ${PY_VER} détecté."

# Vérification swap (min 512 MB recommandé)
SWAP_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
SWAP_MB=$(( SWAP_KB / 1024 ))
if [[ $SWAP_MB -lt 512 ]]; then
    warn "Swap disponible : ${SWAP_MB} MB (< 512 MB recommandé pour daemon longue durée)"
    warn "Pour créer 1 GB de swap : dphys-swapfile install && dphys-swapfile swapon"
else
    info "Swap : ${SWAP_MB} MB — OK"
fi

# Vérification espace disque /var/log
FREE_MB=$(df /var/log --output=avail -m | tail -1 | tr -d ' ')
if [[ $FREE_MB -lt 200 ]]; then
    warn "Espace libre sur /var/log : ${FREE_MB} MB (< 200 MB — attention à la rotation)"
else
    info "Espace libre /var/log : ${FREE_MB} MB — OK"
fi

# ── Création utilisateur dédié ────────────────────────────────────────────────
if ! id -u heatzy &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false heatzy
    info "Utilisateur système 'heatzy' créé."
else
    info "Utilisateur 'heatzy' déjà existant."
fi

# ── Arborescence ──────────────────────────────────────────────────────────────
install -d -m 755 -o heatzy -g heatzy /opt/heatzy
install -d -m 755 -o heatzy -g heatzy /var/log/heatzy
install -d -m 750 -o root   -g heatzy /etc/heatzy
info "Répertoires créés : /opt/heatzy  /var/log/heatzy  /etc/heatzy"

# ── Copie du script principal ─────────────────────────────────────────────────
SCRIPT_SRC="$(dirname "$0")/heatzy_monitor.py"
if [[ ! -f "$SCRIPT_SRC" ]]; then
    error "Fichier source introuvable : $SCRIPT_SRC"
    error "Placez heatzy_monitor.py dans le même répertoire que ce script."
    exit 1
fi
install -m 755 -o heatzy -g heatzy "$SCRIPT_SRC" /opt/heatzy/heatzy_monitor.py
info "Script installé : /opt/heatzy/heatzy_monitor.py"

# ── Fichier credentials ───────────────────────────────────────────────────────
CRED_FILE="/etc/heatzy/credentials"
if [[ ! -f "$CRED_FILE" ]]; then
    echo ""
    warn "=== Configuration des identifiants Heatzy ==="
    read -rp "  Email Heatzy    : " HEATZY_EMAIL
    read -rsp "  Mot de passe    : " HEATZY_PASSWORD
    echo ""

    cat > "$CRED_FILE" <<EOF
HEATZY_EMAIL=${HEATZY_EMAIL}
HEATZY_PASSWORD=${HEATZY_PASSWORD}
EOF
    chmod 640 "$CRED_FILE"
    chown root:heatzy "$CRED_FILE"
    info "Credentials écrits dans $CRED_FILE (mode 640, root:heatzy)."
else
    info "Fichier credentials déjà présent : $CRED_FILE"
fi

# ── Paramètre intervalle ──────────────────────────────────────────────────────
echo ""
read -rp "  Intervalle de collecte en minutes (1-60, défaut: 5) : " INTERVAL_INPUT
INTERVAL=${INTERVAL_INPUT:-5}
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ $INTERVAL -lt 1 ]] || [[ $INTERVAL -gt 60 ]]; then
    warn "Valeur invalide, utilisation du défaut : 5 min"
    INTERVAL=5
fi
info "Intervalle retenu : ${INTERVAL} min"

# ── Unit systemd ──────────────────────────────────────────────────────────────
SERVICE_SRC="$(dirname "$0")/heatzy-monitor.service"
if [[ ! -f "$SERVICE_SRC" ]]; then
    error "Fichier service introuvable : $SERVICE_SRC"
    exit 1
fi

# Injection de l'intervalle dans le service
sed "s/--interval 5/--interval ${INTERVAL}/" "$SERVICE_SRC" \
    > /etc/systemd/system/heatzy-monitor.service
chmod 644 /etc/systemd/system/heatzy-monitor.service
info "Service systemd installé : /etc/systemd/system/heatzy-monitor.service"

# ── Activation ────────────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable heatzy-monitor
systemctl restart heatzy-monitor
sleep 3

if systemctl is-active --quiet heatzy-monitor; then
    info "Service heatzy-monitor démarré et activé au boot."
else
    warn "Le service ne semble pas actif. Vérifier avec :"
    warn "  sudo journalctl -u heatzy-monitor -n 50"
    exit 1
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}  Installation terminée${RESET}"
echo -e "${CYAN}========================================${RESET}"
echo -e "  Script        : ${CYAN}/opt/heatzy/heatzy_monitor.py${RESET}"
echo -e "  CSV historique: ${CYAN}/var/log/heatzy/heatzy_history.csv${RESET}"
echo -e "  Credentials   : ${CYAN}/etc/heatzy/credentials${RESET}"
echo -e "  Intervalle    : ${CYAN}${INTERVAL} min${RESET}"
echo -e "  Rétention     : ${CYAN}365 jours${RESET}"
echo ""
echo -e "  Logs en direct   : ${YELLOW}sudo journalctl -u heatzy-monitor -f${RESET}"
echo -e "  Statut           : ${YELLOW}sudo systemctl status heatzy-monitor${RESET}"
echo -e "  Arrêt            : ${YELLOW}sudo systemctl stop heatzy-monitor${RESET}"
echo ""
