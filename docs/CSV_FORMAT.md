# Heatzy Monitor — Collecteur CSV pour DietPi

Daemon Python autonome qui interroge l'API Heatzy (Gizwits) à intervalle régulier et stocke les relevés de tous les thermostats Pilote Pro dans un fichier CSV rotatif sur 365 jours.

Conçu pour DietPi x86 — stdlib Python uniquement, aucune dépendance externe.

## Fichiers du projet

| Fichier | Rôle |
|---|---|
| `heatzy_monitor.py` | Daemon principal — collecte, CSV, gestion token, retry |
| `heatzy-monitor.service` | Unit systemd — démarrage auto, redémarrage sur échec |
| `install_heatzy_monitor.sh` | Script d'installation interactif (crée utilisateur, répertoires, credentials) |

## Installation

```bash
# Placer les 3 fichiers dans le même répertoire, puis :
sudo bash install_heatzy_monitor.sh
```

L'installeur demande l'email/mot de passe du compte Heatzy et l'intervalle de collecte (défaut 5 min), puis active le service.

## Commandes courantes

```bash
sudo systemctl status heatzy-monitor     # Statut
sudo journalctl -u heatzy-monitor -f     # Logs en direct
tail -5 /var/log/heatzy/heatzy_history.csv  # Derniers relevés
sudo systemctl restart heatzy-monitor    # Redémarrage
sudo systemctl stop heatzy-monitor       # Arrêt
```

## Arborescence installée

```
/opt/heatzy/
  └── heatzy_monitor.py          # Script principal

/etc/heatzy/
  └── credentials                # HEATZY_EMAIL + HEATZY_PASSWORD (mode 640)

/var/log/heatzy/
  └── heatzy_history.csv         # Historique CSV (365 jours glissants)

/etc/systemd/system/
  └── heatzy-monitor.service     # Unit systemd
```

## Architecture API

Le daemon utilise l'API cloud Gizwits (plateforme IoT chinoise sous-jacente à Heatzy) :

- **Endpoint** : `https://euapi.gizwits.com`
- **App ID** : `c70a66ff039d41b4a220e198b0fcc8b3`
- **Auth** : `POST /app/login` → token (validité ~7 jours, renouvelé automatiquement sur 401)
- **Appareils** : `GET /app/bindings?limit=30&skip=0` → liste des DID
- **Relevé** : `GET /app/devdata/{did}/latest` → attributs courants

Documentation officielle : https://heatzy.com/blog/heatzy-openapi-3

---

## Format du fichier CSV

**Emplacement** : `/var/log/heatzy/heatzy_history.csv`

**Encodage** : UTF-8 avec BOM (`\xEF\xBB\xBF`) — ouvrable directement dans Excel sans assistant d'importation.

**Séparateur** : point-virgule `;` (standard français, compatible Excel FR).

**Fréquence** : une ligne par relevé, à l'intervalle configuré (défaut 5 min = 288 lignes/jour).

**Rétention** : 365 jours glissants. Les lignes plus anciennes sont purgées automatiquement avant chaque écriture. Volume maximal estimé : ~105 000 lignes, ~20 MB.

**Écriture atomique** : le daemon écrit dans un fichier `.tmp` puis fait un `os.replace()` — aucun risque de CSV corrompu en cas d'arrêt brutal ou de coupure de courant.

### Structure des colonnes

La première colonne est l'horodatage. Les colonnes suivantes sont groupées par appareil : 8 champs par appareil, préfixés par le nom de l'appareil tel qu'il apparaît dans l'application Heatzy (ex. `ENTRÉE`, `SALON`, `TOM`).

Pour un compte avec N appareils, le CSV contient `1 + (N × 8)` colonnes.

#### Colonne d'horodatage

| Colonne | Format | Exemple |
|---|---|---|
| `Horodatage` | `YYYY-MM-DD HH:MM:SS` | `2025-03-27 14:35:02` |

Heure locale du serveur DietPi au moment du relevé. Pas de fuseau horaire explicite — s'assurer que le système est configuré en `Europe/Paris` (`timedatectl set-timezone Europe/Paris`).

#### Colonnes par appareil

Pour chaque appareil (ex. `SALON`), le CSV contient ces 8 colonnes :

| Colonne | Type | Unité | Description | Exemple |
|---|---|---|---|---|
| `SALON_cur_temp_c` | float | °C | Température ambiante mesurée par la sonde intégrée du Pilote Pro. Valeur brute API `cur_temp` divisée par 10. | `18.9` |
| `SALON_cur_humi_pct` | int | % | Humidité relative mesurée par le capteur intégré. Valeur brute API `cur_humi` non transformée. | `54` |
| `SALON_cur_mode` | string | — | Mode de fonctionnement actif à cet instant. Voir table des modes ci-dessous. | `cft` |
| `SALON_heating` | int | 0/1 | État de chauffe instantané. `1` = le Pilote Pro envoie le signal Confort sur le fil pilote à cet instant (le radiateur chauffe). `0` = signal Éco, Hors-gel ou Arrêt (le radiateur est en repos). Correspond à l'attribut API `Heating_state`. | `1` |
| `SALON_window_open` | int | 0/1 | Détection fenêtre ouverte. `1` = chute rapide de température détectée par le Pilote Pro, interprétée comme une fenêtre ouverte. Le chauffage est automatiquement suspendu. `0` = pas de détection. Correspond à l'attribut API `window_switch`. | `0` |
| `SALON_cft_temp_c` | float | °C | Consigne de température en mode Confort, telle que configurée dans l'application Heatzy. Valeur brute API `cft_temp` divisée par 10. | `19.0` |
| `SALON_eco_temp_c` | float | °C | Consigne de température en mode Éco. Valeur brute API `eco_temp` divisée par 10. Typiquement 3 à 4°C en dessous de la consigne Confort. | `16.0` |
| `SALON_timer_switch` | int | — | Source de la consigne active. `1` = mode décidé par la programmation horaire. `0` = mode imposé manuellement (depuis l'app, le bouton physique, ou l'API). `-1` = information non disponible. | `1` |

#### Table des modes (`cur_mode`)

| Valeur | Nom | Signal fil pilote | Comportement Pilote Pro |
|---|---|---|---|
| `cft` | Confort | Pleine puissance | Le Pilote Pro régule : envoie Confort quand T° < `cft_temp`, bascule en Hors-gel quand T° ≥ `cft_temp`. `Heating_state` alterne entre 0 et 1. |
| `eco` | Éco | Demi-tarif | Idem mais sur la consigne `eco_temp` (typiquement consigne Confort − 3/4°C). |
| `fro` | Hors-gel | Minimum | Maintient 7°C fixe (non configurable). Le radiateur ne chauffe que si T° < 7°C. |
| `stop` | Arrêt | Coupure | Aucun chauffage. Le fil pilote envoie l'ordre d'arrêt. |

#### Fonctionnement de la régulation Pilote Pro

Le Pilote Pro n'envoie pas une température au radiateur — il ne peut envoyer que 4 ordres sur le fil pilote (Confort, Éco, Hors-gel, Arrêt). Pour réguler la température, il alterne entre les signaux :

- En mode `cft` à consigne 19°C, si la sonde mesure 17°C → il envoie Confort (`Heating_state=1`), le radiateur chauffe à pleine puissance.
- Quand la sonde atteint 19°C → il bascule en Hors-gel (`Heating_state=0`), le radiateur s'arrête.
- Quand la sonde redescend sous 19°C → il renvoie Confort, etc.

C'est pourquoi `Heating_state` oscille régulièrement — c'est le cycle de régulation normal, pas un dysfonctionnement.

### Exemple de CSV (6 appareils)

```csv
Horodatage;ENTRÉE_cur_temp_c;ENTRÉE_cur_humi_pct;ENTRÉE_cur_mode;ENTRÉE_heating;ENTRÉE_window_open;ENTRÉE_cft_temp_c;ENTRÉE_eco_temp_c;ENTRÉE_timer_switch;CHLOÉ_cur_temp_c;CHLOÉ_cur_humi_pct;CHLOÉ_cur_mode;CHLOÉ_heating;CHLOÉ_window_open;CHLOÉ_cft_temp_c;CHLOÉ_eco_temp_c;CHLOÉ_timer_switch
2025-03-27 19:00:05;18.9;54;cft;0;0;18.5;16.0;1;16.9;56;eco;0;0;18.0;16.0;1
2025-03-27 19:05:04;18.8;54;cft;1;0;18.5;16.0;1;16.8;56;eco;0;0;18.0;16.0;1
2025-03-27 19:10:05;19.1;53;cft;0;0;18.5;16.0;1;16.9;57;eco;0;0;18.0;16.0;1
```

### Colonnes vides

Si un appareil est hors-ligne au moment du relevé (WiFi coupé, module éteint), ses 8 colonnes sont vides pour cette ligne. L'appareil réapparaît automatiquement au relevé suivant une fois reconnecté.

### Ouverture dans Excel

Le CSV est directement ouvrable dans Excel (double-clic) grâce au BOM UTF-8 et au séparateur `;`. Les accents dans les noms d'appareils (ENTRÉE, CHLOÉ) sont correctement interprétés.

Pour un traitement automatisé, le séparateur `;` est spécifié dans le `csv.DictReader` / `DictWriter` du script.

### Compatibilité avec le dashboard HTML

Le format CSV est volontairement aligné avec le dashboard `New-HeatzyDashboard.ps1` (généré sur Windows). Les deux utilisent le même séparateur `;`, le même encodage UTF-8 BOM, et les mêmes noms de champs API. Le dashboard peut charger le fichier CSV du DietPi via le bouton "Charger log" (après transfert SCP/SFTP).

---

## Colonnes envisagées pour une version future (v1.1)

Ces attributs sont disponibles dans l'API mais ne sont pas encore collectés :

| Attribut API | Description | Ajout prévu |
|---|---|---|
| `derog_mode` | Mode de dérogation : 0=aucune, 1=vacances, 2=boost, 3=présence | v1.1 |
| `derog_time` | Minutes restantes de dérogation | v1.1 |
| `lock_switch` | Verrouillage du bouton physique (0/1) | Si besoin |
| `cur_signal` | Signal fil pilote envoyé à cet instant (`cft`/`eco`/`fro`) | Si besoin |

---

## Dépannage

**Le service ne démarre pas** (`status=226/NAMESPACE`) : DietPi avec Dropbear ne supporte pas toujours le namespace mounting. Éditer le service (`systemctl edit --full heatzy-monitor`) et commenter les lignes `PrivateTmp=true`, `ProtectSystem=full`, `ReadWritePaths=...`.

**Erreur 9020 (username or password error)** : le compte Heatzy de l'app mobile est distinct d'un éventuel compte Google/Apple. Réinitialiser le mot de passe depuis l'écran de connexion de l'app Heatzy → "Mot de passe oublié".

**Token expiré** : géré automatiquement. Sur réponse HTTP 401, le daemon se ré-authentifie et retente le relevé sans redémarrage.

**CSV corrompu après coupure de courant** : impossible par design. L'écriture passe par un fichier `.tmp` suivi d'un `os.replace()` atomique au niveau du filesystem.

**Espace disque** : à 288 lignes/jour × 6 appareils × 8 champs, le CSV atteint ~20 MB après 365 jours. Un avertissement est logué si l'espace libre passe sous 100 MB.

## Licence

Usage interne ALTICAP. API Heatzy/Gizwits soumise aux conditions d'utilisation Heatzy.
