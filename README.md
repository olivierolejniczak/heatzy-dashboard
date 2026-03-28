# Heatzy Dashboard

Self-hosted dashboard for [Heatzy Pilote Pro](https://heatzy.com/pilote-pro) smart radiator controllers. Real-time monitoring, scheduling, and control — all from a single HTML file.

![Dashboard screenshot](docs/screenshot.png)

## Features

- **Real-time monitoring** — Temperature, humidity, heating state, window detection for all radiators
- **Temperature vs setpoint chart** — Actual temperature (solid) overlaid with active setpoint (dashed) per room
- **Outdoor weather** — Open-Meteo integration with indoor/outdoor delta (no API key needed)
- **Stacked heating chart** — See how many radiators are ON simultaneously
- **Schedule viewer/editor** — 48-slot (30-min) weekly grid, decoded per official Heatzy OpenAPI 3 spec
- **Mode override** — One-click mode change (Comfort/Eco/Frost/Off) with return-to-schedule
- **365-day CSV logging** — Persistent history with atomic writes, auto-purge
- **PWA installable** — Add to home screen on Android/iOS, works offline
- **Dark/Light/System theme** — Persisted toggle, charts auto-adapt
- **Data gap visualization** — Periods without collection shown as breaks, not fake lines

## How it works

A single PowerShell script generates a standalone HTML dashboard that calls the Heatzy (Gizwits) cloud API directly from the browser. No server, no database, no dependencies beyond a modern browser.

```
┌──────────────────┐     ┌─────────────────┐     ┌──────────────┐
│ Heatzy Pilote Pro│◄───►│  Gizwits Cloud  │◄───►│  Dashboard   │
│   (radiators)    │     │  euapi.gizwits  │     │  (browser)   │
└──────────────────┘     └─────────────────┘     └──────────────┘
                                                        │
                                                 ┌──────┴───────┐
                                                 │  Open-Meteo  │
                                                 │  (weather)   │
                                                 └──────────────┘
```

## Quick start

### Windows (PowerShell)

```powershell
.\New-HeatzyDashboard.ps1
# Opens Heatzy-Dashboard.html in your default browser
# Enter your Heatzy email/password in the toolbar
```

### DietPi/Linux headless collector

For 24/7 data collection on a DietPi or any Linux box (Python 3.7+, stdlib only):

```bash
cd dietpi/
sudo bash install_heatzy_monitor.sh
```

See [dietpi/](dietpi/) folder and [CSV format documentation](docs/CSV_FORMAT.md).

## Generated files

Running `New-HeatzyDashboard.ps1` creates:

| File | Purpose |
|---|---|
| `Heatzy-Dashboard.html` | The dashboard (open in browser) |
| `Heatzy-Collector.ps1` | Headless PowerShell collector for scheduled task |
| `manifest.json` | PWA manifest for Android/iOS install |
| `sw.js` | Service worker for offline support |
| `icon.svg` | App icon (convert to PNG for full PWA support) |

## PWA installation (Android)

1. Serve the files via a local web server:
   ```bash
   python -m http.server 8080
   ```
2. Open `http://YOUR_IP:8080/Heatzy-Dashboard.html` in Chrome on Android
3. Chrome menu → **Add to home screen**

Or host on your LAN via nginx/lighttpd on DietPi.

## API reference

Based on the [official Heatzy OpenAPI 3 documentation](https://heatzy.com/blog/heatzy-openapi-3):

- **Endpoint**: `https://euapi.gizwits.com`
- **App ID**: `c70a66ff039d41b4a220e198b0fcc8b3`
- **Schedule encoding**: Each `pX_dataY` register = 2h = 4×30min slots, 2 bits each. `00`=Comfort, `01`=Eco, `10`=Frost, `11`=Off. Bits in **reverse chronological** order (LSB = first slot).

Weather data from [Open-Meteo](https://open-meteo.com/) — free, no API key, CORS enabled.

## Schedule decoding

The schedule bit mapping was reverse-engineered and confirmed against the official documentation:

| Bits | Mode | Full register example |
|------|------|-----------------------|
| `00` | Comfort | `0` (00000000) = Comfort ×4 |
| `01` | Eco | `85` (01010101) = Eco ×4 |
| `10` | Frost | `170` (10101010) = Frost ×4 |
| `11` | Off | `255` (11111111) = Off ×4 |

Bits are read **right-to-left** (LSB first = first 30-min slot chronologically).

## Project structure

```
├── New-HeatzyDashboard.ps1    # Main generator script (PowerShell 5.1)
├── dietpi/
│   ├── heatzy_monitor.py      # Python daemon for 24/7 CSV collection
│   ├── heatzy-monitor.service # systemd unit
│   └── install_heatzy_monitor.sh  # Interactive installer
├── docs/
│   └── CSV_FORMAT.md          # Detailed CSV column documentation
├── LICENSE
└── README.md
```

## Requirements

- **Dashboard**: Any modern browser (Chrome, Edge, Firefox). Chart.js loaded from CDN.
- **Generator**: PowerShell 5.1+ (Windows) or PowerShell Core (cross-platform)
- **DietPi collector**: Python 3.7+, stdlib only (no pip install needed)
- **Heatzy account**: Email + password (same as Heatzy mobile app)

## Acknowledgments

- [Heatzy](https://heatzy.com/) for the Pilote Pro hardware and public API documentation
- [cyr-ius/hass-heatzy](https://github.com/cyr-ius/hass-heatzy) Home Assistant integration — invaluable cross-reference
- [OlivierZal/heatzy-api](https://github.com/OlivierZal/heatzy-api) TypeScript API — derogation mode discovery
- [Open-Meteo](https://open-meteo.com/) for the free weather API
- [Chart.js](https://www.chartjs.org/) for the charting library

## License

MIT — see [LICENSE](LICENSE).
