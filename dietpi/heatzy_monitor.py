#!/usr/bin/env python3
# ==============================================================================
# heatzy_monitor.py  v1.0
# Daemon de surveillance Heatzy pour DietPi x86 (Python 3)
# - Interroge l'API Gizwits toutes les N minutes (défaut : 5 min)
# - Stocke les relevés dans un CSV (séparateur ';', BOM UTF-8)
# - Conservation automatique sur 365 jours glissants
# - Renouvellement du token transparent (401 → re-auth)
# - Prêt systemd : logs structurés sur stdout, gestion SIGTERM propre
# ==============================================================================
# Usage :
#   python3 heatzy_monitor.py --email user@example.fr --password XXXX
#   python3 heatzy_monitor.py --email user@example.fr --password XXXX \
#           --interval 10 --csv /data/heatzy.csv
#
# Prérequis : Python 3.7+, aucune dépendance externe (stdlib uniquement)
# ==============================================================================

import argparse
import csv
import io
import json
import logging
import os
import signal
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

# ── Constantes API Gizwits / Heatzy ──────────────────────────────────────────
API_BASE  = "https://euapi.gizwits.com"
APP_ID    = "c70a66ff039d41b4a220e198b0fcc8b3"
MAX_DAYS  = 365          # durée de conservation CSV
RETRY_MAX = 3            # tentatives par appel API
RETRY_DELAY_S = 5        # secondes entre tentatives

# ── Palette ANSI — daltonisme-safe (deuteranopie / protanopie) ────────────────
# Cyan  → succès/info   (remplace Vert)
# Magenta → erreur      (remplace Rouge)
# Jaune → avertissement
# Gras systématique pour lisibilité maximale
CYAN    = '\033[1;36m'
MAGENTA = '\033[1;35m'
YELLOW  = '\033[1;33m'
BLUE    = '\033[1;34m'
RESET   = '\033[0m'

# ── Colonnes CSV ─────────────────────────────────────────────────────────────
# Horodatage + 8 champs par appareil (nom de l'appareil en préfixe de colonne)
DEVICE_FIELDS = [
    "cur_temp_c",   # température ambiante (divisée par 10)
    "cur_humi_pct", # humidité relative
    "cur_mode",     # cft / eco / fro / stop
    "heating",      # 0/1 : résistance active
    "window_open",  # 0/1 : détection fenêtre ouverte
    "cft_temp_c",   # consigne Confort (divisée par 10)
    "eco_temp_c",   # consigne Eco (divisée par 10)
    "timer_switch", # 0=manuel / 1=programmé / -1=inconnu
]

# ── Logging structuré ─────────────────────────────────────────────────────────
def setup_logging(verbose: bool) -> logging.Logger:
    level = logging.DEBUG if verbose else logging.INFO
    fmt   = "%(asctime)s  %(levelname)-8s  %(message)s"
    logging.basicConfig(stream=sys.stdout, format=fmt, datefmt="%Y-%m-%d %H:%M:%S", level=level)
    return logging.getLogger("heatzy")


# ── Requêtes HTTP (stdlib uniquement) ────────────────────────────────────────
def _http(method: str, path: str, headers: dict, body: dict | None = None,
          timeout: int = 15) -> dict:
    """Effectue une requête HTTP avec retry/backoff.

    Raises:
        urllib.error.HTTPError si status != 2xx après RETRY_MAX tentatives.
    """
    url  = API_BASE + path
    data = json.dumps(body).encode() if body else None

    for attempt in range(1, RETRY_MAX + 1):
        try:
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                raise  # re-auth requise, remonter immédiatement
            if attempt == RETRY_MAX:
                raise
            logging.getLogger("heatzy").warning(
                f"HTTP {exc.code} sur {path} — tentative {attempt}/{RETRY_MAX}, "
                f"attente {RETRY_DELAY_S}s"
            )
            time.sleep(RETRY_DELAY_S * attempt)
        except (urllib.error.URLError, OSError) as exc:
            if attempt == RETRY_MAX:
                raise
            logging.getLogger("heatzy").warning(
                f"Erreur réseau ({exc}) — tentative {attempt}/{RETRY_MAX}, "
                f"attente {RETRY_DELAY_S}s"
            )
            time.sleep(RETRY_DELAY_S * attempt)


# ── Client API Heatzy ─────────────────────────────────────────────────────────
class HeatzyClient:
    def __init__(self, email: str, password: str) -> None:
        self.email    = email
        self.password = password
        self._token   = None
        self.log      = logging.getLogger("heatzy")

    # En-têtes communs
    def _headers(self, with_token: bool = True) -> dict:
        h = {
            "X-Gizwits-Application-Id": APP_ID,
            "Content-Type": "application/json",
        }
        if with_token and self._token:
            h["X-Gizwits-User-token"] = self._token
        return h

    def authenticate(self) -> None:
        """Authentification et mise en cache du token."""
        self.log.info("Authentification auprès de l'API Gizwits…")
        resp = _http(
            "POST", "/app/login",
            headers=self._headers(with_token=False),
            body={"username": self.email, "password": self.password, "lang": "fr"},
        )
        self._token = resp["token"]
        self.log.info(f"{CYAN}[AUTH OK]{RESET} Token obtenu.")

    def get_devices(self) -> list[dict]:
        """Retourne la liste des appareils liés au compte."""
        resp = _http("GET", "/app/bindings?limit=30&skip=0", headers=self._headers())
        devices = resp.get("devices", [])
        self.log.info(f"{CYAN}[DEVICES]{RESET} {len(devices)} appareil(s) trouvé(s).")
        return [{"did": d["did"], "name": d.get("dev_alias") or d["did"]} for d in devices]

    def get_attr(self, did: str) -> dict | None:
        """Retourne les attributs courants d'un appareil. None si erreur."""
        try:
            resp = _http("GET", f"/app/devdata/{did}/latest", headers=self._headers())
            return resp.get("attr")
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                raise
            self.log.warning(f"{YELLOW}[WARN]{RESET} Impossible de lire {did} : HTTP {exc.code}")
            return None
        except Exception as exc:
            self.log.warning(f"{YELLOW}[WARN]{RESET} Impossible de lire {did} : {exc}")
            return None

    def poll_all(self, devices: list[dict]) -> dict:
        """Interroge tous les appareils. Retourne {name: attr_dict}."""
        snapshot = {}
        for dev in devices:
            attr = self.get_attr(dev["did"])
            if attr:
                snapshot[dev["name"]] = attr
                self.log.debug(f"  {dev['name']} → {attr.get('cur_temp', '?')/10:.1f}°C "
                               f"mode={attr.get('cur_mode','?')} "
                               f"chauffe={attr.get('Heating_state','?')}")
        return snapshot


# ── Gestionnaire CSV ──────────────────────────────────────────────────────────
class CsvStore:
    """Lecture / écriture du fichier CSV historique.

    Format :
      Horodatage ; {nom}_cur_temp_c ; {nom}_cur_humi_pct ; … (1 ligne / relevé)

    Stratégie de mise à jour :
      - Chargement intégral en mémoire (365 j × 288 relevés/j ≈ 105k lignes ≈ 20 MB max)
      - Purge des lignes > MAX_DAYS avant chaque écriture
      - Réécriture atomique (fichier temp + rename)
    """

    def __init__(self, path: Path, device_names: list[str]) -> None:
        self.path    = path
        self.names   = device_names  # ordre stable des appareils
        self.log     = logging.getLogger("heatzy")
        self._rows: list[dict] = []

    @property
    def header(self) -> list[str]:
        cols = ["Horodatage"]
        for name in self.names:
            for field in DEVICE_FIELDS:
                cols.append(f"{name}_{field}")
        return cols

    def load(self) -> None:
        """Charge le CSV existant en mémoire. Silencieux si absent."""
        if not self.path.exists():
            self.log.info(f"Nouveau fichier CSV : {self.path}")
            return
        try:
            with open(self.path, encoding="utf-8-sig", newline="") as fh:
                reader = csv.DictReader(fh, delimiter=";")
                self._rows = list(reader)
            self.log.info(f"{CYAN}[CSV LOAD]{RESET} {len(self._rows)} relevés chargés depuis {self.path}")
        except Exception as exc:
            self.log.error(f"{MAGENTA}[CSV ERROR]{RESET} Lecture impossible : {exc}")
            self._rows = []

    def _purge(self) -> None:
        """Supprime les relevés antérieurs à MAX_DAYS jours."""
        cutoff = (datetime.now() - timedelta(days=MAX_DAYS)).strftime("%Y-%m-%d %H:%M:%S")
        before = len(self._rows)
        self._rows = [r for r in self._rows if r.get("Horodatage", "") >= cutoff]
        removed = before - len(self._rows)
        if removed:
            self.log.debug(f"Purge CSV : {removed} ligne(s) supprimée(s) (> {MAX_DAYS} j).")

    def append(self, snapshot: dict) -> None:
        """Ajoute un relevé et réécrit le fichier de façon atomique."""
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        row: dict[str, str] = {"Horodatage": now}

        for name in self.names:
            attr = snapshot.get(name, {})
            if attr:
                row[f"{name}_cur_temp_c"]   = f"{attr.get('cur_temp', '') / 10:.1f}" if attr.get('cur_temp') is not None else ""
                row[f"{name}_cur_humi_pct"] = str(attr.get("cur_humi", ""))
                row[f"{name}_cur_mode"]     = str(attr.get("cur_mode", ""))
                row[f"{name}_heating"]      = str(attr.get("Heating_state", ""))
                row[f"{name}_window_open"]  = str(attr.get("window_switch", ""))
                row[f"{name}_cft_temp_c"]   = f"{attr.get('cft_temp', '') / 10:.1f}" if attr.get('cft_temp') is not None else ""
                row[f"{name}_eco_temp_c"]   = f"{attr.get('eco_temp', '') / 10:.1f}" if attr.get('eco_temp') is not None else ""
                row[f"{name}_timer_switch"] = str(attr.get("timer_switch", -1))
            else:
                # Appareil non disponible ce relevé → colonnes vides
                for field in DEVICE_FIELDS:
                    row[f"{name}_{field}"] = ""

        self._rows.append(row)
        self._purge()
        self._write_atomic()
        self.log.info(
            f"{CYAN}[CSV OK]{RESET} {len(self._rows)} relevés "
            f"— dernier : {now} "
            f"({len([n for n in self.names if snapshot.get(n)])} appareil(s) OK)"
        )

    def _write_atomic(self) -> None:
        """Écriture dans un fichier temporaire puis rename pour atomicité."""
        tmp = self.path.with_suffix(".tmp")
        try:
            with open(tmp, mode="w", encoding="utf-8-sig", newline="") as fh:
                writer = csv.DictWriter(fh, fieldnames=self.header, delimiter=";",
                                        extrasaction="ignore")
                writer.writeheader()
                writer.writerows(self._rows)
            os.replace(tmp, self.path)
        except Exception as exc:
            self.log.error(f"{MAGENTA}[CSV WRITE ERROR]{RESET} {exc}")
            if tmp.exists():
                tmp.unlink(missing_ok=True)
            raise

    def update_names(self, names: list[str]) -> None:
        """Met à jour la liste des appareils (utile si l'inventaire change)."""
        self.names = names


# ── Vérifications DietPi avant démarrage ─────────────────────────────────────
def check_system(log: logging.Logger) -> None:
    """Vérifie swap et espace disque disponibles (contraintes DietPi)."""
    # Vérification swap (min 512 MB recommandé pour ce daemon léger)
    swap_total = 0
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("SwapTotal:"):
                    swap_total = int(line.split()[1])  # kB
                    break
    except OSError:
        pass

    if swap_total < 512 * 1024:  # < 512 MB
        log.warning(
            f"{YELLOW}[SYS WARN]{RESET} Swap disponible : {swap_total // 1024} MB "
            "(< 512 MB recommandé pour daemon longue durée)"
        )
    else:
        log.debug(f"Swap : {swap_total // 1024} MB — OK")

    # Vérification espace disque (chemin courant)
    try:
        stat = os.statvfs(".")
        free_mb = (stat.f_bavail * stat.f_frsize) // (1024 * 1024)
        if free_mb < 100:
            log.warning(
                f"{YELLOW}[SYS WARN]{RESET} Espace disque libre : {free_mb} MB "
                "(< 100 MB — purge CSV prioritaire)"
            )
        else:
            log.debug(f"Espace disque libre : {free_mb} MB — OK")
    except OSError:
        pass


# ── Signal handler (arrêt propre via systemd SIGTERM) ─────────────────────────
class GracefulExit:
    def __init__(self) -> None:
        self._stop = False
        signal.signal(signal.SIGTERM, self._handler)
        signal.signal(signal.SIGINT,  self._handler)

    def _handler(self, signum, _frame) -> None:
        sig_name = "SIGTERM" if signum == signal.SIGTERM else "SIGINT"
        logging.getLogger("heatzy").info(
            f"{YELLOW}[SIGNAL]{RESET} {sig_name} reçu — arrêt propre en cours…"
        )
        self._stop = True

    @property
    def stop(self) -> bool:
        return self._stop


# ── Boucle principale ─────────────────────────────────────────────────────────
def run(args: argparse.Namespace) -> None:
    log   = setup_logging(args.verbose)
    stopper = GracefulExit()

    log.info(f"{CYAN}{'='*60}{RESET}")
    log.info(f"{CYAN}  Heatzy Monitor v1.0  —  ALTICAP{RESET}")
    log.info(f"{CYAN}{'='*60}{RESET}")
    log.info(f"CSV        : {args.csv}")
    log.info(f"Intervalle : {args.interval} min")
    log.info(f"Rétention  : {MAX_DAYS} jours")

    check_system(log)

    client  = HeatzyClient(args.email, args.password)
    csv_path = Path(args.csv)
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    store: CsvStore | None = None
    devices: list[dict]    = []

    def init_session() -> None:
        nonlocal store, devices
        client.authenticate()
        devices = client.get_devices()
        if not devices:
            raise RuntimeError("Aucun appareil trouvé sur ce compte.")
        store = CsvStore(csv_path, [d["name"] for d in devices])
        store.load()

    # Initialisation avec retry si réseau indisponible au démarrage
    for attempt in range(1, 6):
        try:
            init_session()
            break
        except Exception as exc:
            if attempt == 5:
                log.error(f"{MAGENTA}[FATAL]{RESET} Initialisation impossible après 5 tentatives : {exc}")
                sys.exit(1)
            wait = 30 * attempt
            log.warning(f"{YELLOW}[INIT RETRY]{RESET} Tentative {attempt}/5 échouée ({exc}). "
                        f"Nouvelle tentative dans {wait}s…")
            time.sleep(wait)
            if stopper.stop:
                sys.exit(0)

    interval_s = args.interval * 60
    log.info(f"{CYAN}[START]{RESET} Daemon actif. Premier relevé dans {args.interval} min.")

    # Attente initiale (évite un relevé immédiat au démarrage)
    next_poll = time.monotonic() + interval_s

    while not stopper.stop:
        now = time.monotonic()
        if now < next_poll:
            # Sommeil fractionné pour réactivité aux signaux
            time.sleep(min(5.0, next_poll - now))
            continue

        next_poll = time.monotonic() + interval_s

        try:
            snapshot = client.poll_all(devices)
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                # Token expiré → re-authentification transparente
                log.warning(f"{YELLOW}[TOKEN EXPIRED]{RESET} Re-authentification…")
                try:
                    client.authenticate()
                    snapshot = client.poll_all(devices)
                except Exception as exc2:
                    log.error(f"{MAGENTA}[AUTH FAIL]{RESET} {exc2} — relevé ignoré.")
                    continue
            else:
                log.error(f"{MAGENTA}[API ERROR]{RESET} HTTP {exc.code} — relevé ignoré.")
                continue
        except Exception as exc:
            log.error(f"{MAGENTA}[POLL ERROR]{RESET} {exc} — relevé ignoré.")
            continue

        try:
            store.append(snapshot)
        except Exception as exc:
            log.error(f"{MAGENTA}[STORE ERROR]{RESET} Impossible d'écrire le CSV : {exc}")

    log.info(f"{CYAN}[STOP]{RESET} Daemon arrêté proprement.")


# ── Entrypoint ────────────────────────────────────────────────────────────────
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Heatzy Monitor — daemon de collecte CSV pour DietPi",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--email",    required=True,  help="Email du compte Heatzy")
    parser.add_argument("--password", required=True,  help="Mot de passe du compte Heatzy")
    parser.add_argument(
        "--csv",
        default="/var/log/heatzy/heatzy_history.csv",
        help="Chemin du fichier CSV de sortie",
    )
    parser.add_argument(
        "--interval",
        type=int, default=5, metavar="MINUTES",
        help="Intervalle de collecte en minutes (1–60)",
    )
    parser.add_argument("--verbose", action="store_true", help="Logs détaillés (DEBUG)")
    args = parser.parse_args()

    if not 1 <= args.interval <= 60:
        parser.error("--interval doit être compris entre 1 et 60 minutes.")

    return args


if __name__ == "__main__":
    run(parse_args())
