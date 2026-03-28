# ==============================================================================
# New-HeatzyDashboard.ps1  v12.0
# v12 : Graphe consigne vs reelle, gaps visibles, retry progressif, badge coherent
# Decodage planning : doc officielle Heatzy OpenAPI 3
#   00 = Confort  |  01 = Eco  |  10 = Hors-gel  |  11 = Arret
#   Bits en ordre chronologique inverse
# ==============================================================================
[CmdletBinding()]
param([Parameter(Mandatory=$false)][string]$OutputDir=$PSScriptRoot)
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'

$CollectorScript = @'
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Email,[Parameter(Mandatory=$true)][string]$Password,
      [Parameter(Mandatory=$false)][string]$LogPath="$PSScriptRoot\heatzy_log.json",
      [Parameter(Mandatory=$false)][int]$MaxDays=365)
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'
$API="https://euapi.gizwits.com"; $AID="c70a66ff039d41b4a220e198b0fcc8b3"
function WL{param([string]$M)"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $M"|Out-File "$PSScriptRoot\heatzy_collector.log" -Append -Encoding UTF8}
try{$B=@{username=$Email;password=$Password;lang="fr"}|ConvertTo-Json;$R=Invoke-RestMethod -Uri "$API/app/login" -Method POST -Headers @{"X-Gizwits-Application-Id"=$AID;"Content-Type"="application/json"} -Body $B;$T=$R.token;WL "Auth OK"}catch{WL "ERR Auth:$_";exit 1}
$H=@{"X-Gizwits-Application-Id"=$AID;"X-Gizwits-User-token"=$T}
try{$D=(Invoke-RestMethod -Uri "$API/app/bindings?limit=30&skip=0" -Method GET -Headers $H).devices;WL "$($D.Count) appareils"}catch{WL "ERR:$_";exit 1}
$S=@{}
foreach($d in $D){try{$A=(Invoke-RestMethod -Uri "$API/app/devdata/$($d.did)/latest" -Method GET -Headers $H).attr;$S[$d.dev_alias]=@{cur_temp=$A.cur_temp;cur_humi=$A.cur_humi;cur_mode=$A.cur_mode;Heating_state=$A.Heating_state;window_switch=$A.window_switch;cft_temp=$A.cft_temp;eco_temp=$A.eco_temp;timer_switch=$A.timer_switch;derog_mode=$A.derog_mode;derog_time=$A.derog_time}}catch{WL "WARN $($d.dev_alias):$_"}}
$L=@();if(Test-Path $LogPath){try{$L=Get-Content $LogPath -Encoding UTF8 -Raw|ConvertFrom-Json;if(-not $L){$L=@()}}catch{$L=@()}}
$C=(Get-Date).AddDays(-$MaxDays);$L=@($L|Where-Object{[datetime]$_.ts -ge $C})
$L+=[PSCustomObject]@{ts=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss");data=$S}
try{$L|ConvertTo-Json -Depth 6 -Compress|Out-File $LogPath -Encoding UTF8 -Force;WL "OK $($L.Count)"}catch{WL "ERR:$_";exit 1}
'@

$Html = @'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="theme-color" content="#1c1c1a"><meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Heatzy Dashboard v12</title>
<link rel="manifest" href="manifest.json">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🔥</text></svg>">
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#f8f7f4;--surface:#fff;--border:rgba(0,0,0,.10);--text:#1a1a1a;--muted:#5f5e5a;--accent:#185fa5;--success:#3b6d11;--danger:#a32d2d;--warn:#854f0b;--radius:10px;--cft:#EF9F27;--eco:#378ADD;--hg:#B4B2A9}
:root.dark{--bg:#1c1c1a;--surface:#252523;--border:rgba(255,255,255,.10);--text:#e8e6df;--muted:#9c9a92;--accent:#85b7eb;--success:#97c459;--danger:#f09595;--warn:#ef9f27}
body{background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Segoe UI",Arial,sans-serif;font-size:14px;line-height:1.5;padding:24px;max-width:1280px;margin:0 auto}
h1{font-size:18px;font-weight:500;margin-bottom:20px}
.toolbar{background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);padding:12px 16px;display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:12px}
.toolbar label{font-size:12px;color:var(--muted);white-space:nowrap}
.toolbar input[type=email]{width:210px}.toolbar input[type=password]{width:150px}
.toolbar input[type=email],.toolbar input[type=password]{font-size:13px;padding:6px 10px;border:.5px solid var(--border);border-radius:6px;background:var(--bg);color:var(--text);outline:none}
.toolbar input:focus{border-color:var(--accent)}
.toolbar select{font-size:13px;padding:6px 10px;border:.5px solid var(--border);border-radius:6px;background:var(--bg);color:var(--text);outline:none}
.check-row{display:flex;align-items:center;gap:5px;font-size:12px;color:var(--muted);cursor:pointer;white-space:nowrap}
.check-row input[type=checkbox]{cursor:pointer}
.sep{width:.5px;height:22px;background:var(--border);margin:0 4px}
.btn{font-size:13px;padding:6px 14px;border:.5px solid var(--border);border-radius:6px;background:var(--surface);color:var(--text);cursor:pointer;white-space:nowrap;transition:background .15s}
.btn:hover{background:var(--bg)}.btn-primary{background:var(--accent);color:#fff;border-color:var(--accent)}.btn-primary:hover{opacity:.88}
.btn-danger{color:var(--danger);border-color:var(--danger)}.btn-sm{font-size:12px;padding:4px 10px}
.filter-bar{background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);padding:10px 16px;display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:12px}
.filter-label{font-size:11px;font-weight:500;color:var(--muted);white-space:nowrap}
.filter-chip{display:inline-flex;align-items:center;gap:5px;font-size:12px;padding:3px 10px;border:.5px solid var(--border);border-radius:20px;background:var(--bg);color:var(--text);cursor:pointer;user-select:none;transition:all .15s}
.filter-chip input[type=checkbox]{display:none}
.filter-chip.active{background:var(--accent);color:#fff;border-color:var(--accent)}
.filter-chip .chip-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0}
.filter-all{font-size:12px;color:var(--accent);cursor:pointer;padding:3px 6px;border-radius:4px}
.filter-all:hover{background:var(--bg)}
.log-bar{background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);padding:10px 16px;display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin-bottom:12px;font-size:12px;color:var(--muted)}
.log-bar .log-info{min-width:180px}.log-bar .log-info.active{color:var(--success)}
.log-bar .log-sep{width:.5px;height:22px;background:var(--border);margin:0 2px;flex-shrink:0}
.wx-bar{display:flex;align-items:center;gap:10px;margin-left:auto;font-size:12px;color:var(--muted);flex-shrink:0}
.wx-icon{font-size:18px;line-height:1}.wx-temp{font-size:16px;font-weight:500;color:var(--text)}
.wx-details{display:flex;gap:8px;flex-wrap:wrap}.wx-detail{white-space:nowrap}
.wx-delta{font-size:11px;padding:1px 6px;border-radius:8px;white-space:nowrap}
.wx-delta-cold{background:#E6F1FB;color:#185fa5}.wx-delta-warm{background:#FAEEDA;color:#854f0b}
.dark .wx-delta-cold{background:#042c53;color:#85b7eb}.dark .wx-delta-warm{background:#412402;color:#fac775}
#status{font-size:12px;color:var(--muted);margin-bottom:8px;min-height:18px;display:flex;align-items:center;gap:6px}
#status.ok{color:var(--success)}#status.error{color:var(--danger)}#status.warn{color:var(--warn)}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));gap:10px;margin-bottom:24px}
.card{background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);padding:14px 15px}
.card.mode-cft{border-left:3px solid var(--cft)}.card.mode-eco{border-left:3px solid var(--eco)}.card.mode-fro{border-left:3px solid var(--hg)}
.card-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px}
.card-name{font-size:10px;font-weight:600;letter-spacing:.07em;text-transform:uppercase;color:var(--muted)}
.card-actions{display:flex;align-items:center;gap:5px;position:relative}
.card-plan-btn{font-size:10px;color:var(--accent);cursor:pointer;padding:2px 5px;border-radius:4px;border:.5px solid var(--accent);background:transparent;transition:background .15s}
.card-plan-btn:hover{background:var(--accent);color:#fff}
.mode-icon{width:22px;height:22px;display:flex;align-items:center;justify-content:center;border-radius:50%;flex-shrink:0}
.mode-icon svg{width:14px;height:14px}
.mode-icon.cft{background:#FAEEDA}.mode-icon.eco,.mode-icon.fro{background:#E6F1FB}
.dark .mode-icon.cft{background:#412402}.dark .mode-icon.eco,.dark .mode-icon.fro{background:#042c53}
.card-temp{font-size:28px;font-weight:500;line-height:1;margin-bottom:4px}
.card-sub{font-size:12px;color:var(--muted);margin-bottom:2px}
.card-indicators{display:flex;flex-wrap:wrap;gap:4px;margin-top:8px}
.card-stat{font-size:11px;font-style:italic;opacity:.75}
.mode-popup{position:absolute;top:100%;right:0;z-index:50;background:var(--surface);border:.5px solid var(--border);border-radius:8px;padding:6px;display:none;flex-direction:column;gap:4px;box-shadow:0 4px 12px rgba(0,0,0,.15);min-width:120px}
.mode-popup.open{display:flex}
.mode-popup-btn{font-size:12px;padding:6px 10px;border:none;border-radius:5px;cursor:pointer;text-align:left;background:var(--bg);color:var(--text);transition:background .12s}
.mode-popup-btn:hover{filter:brightness(1.1)}
.mode-popup-btn.m-cft{background:#FAEEDA;color:#633806}.mode-popup-btn.m-eco{background:#E6F1FB;color:#185fa5}
.mode-popup-btn.m-fro{background:#e8e8e6;color:#555}.mode-popup-btn.m-stop{background:#fce4ec;color:#7f1d1d}
.mode-popup-btn.m-prog{background:#e8f5e9;color:#2e6b2e;font-weight:500}
.mode-popup-btn.current{outline:2px solid var(--accent);outline-offset:-2px}
.dark .mode-popup-btn.m-cft{background:#412402;color:#fac775}.dark .mode-popup-btn.m-eco{background:#042c53;color:#85b7eb}.dark .mode-popup-btn.m-fro{background:#333;color:#aaa}.dark .mode-popup-btn.m-stop{background:#4a1010;color:#f5b0b0}.dark .mode-popup-btn.m-prog{background:#1b3d1b;color:#a5d6a7}
.pill{display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:500;padding:2px 7px;border-radius:5px;white-space:nowrap}
.pill svg{width:10px;height:10px;flex-shrink:0}
.pill-heat{background:#faece7;color:#712b13}.pill-win{background:#faeeda;color:#633806}.pill-pres{background:#eeedfe;color:#3c3489}
.pill-prog{background:#e8f5e9;color:#2e6b2e}.pill-manual{background:#fff3e0;color:#8a5600}.pill-override{background:#fce4ec;color:#7f1d1d}
.dark .pill-heat{background:#4a1b0c;color:#f5c4b3}.dark .pill-win{background:#412402;color:#fac775}.dark .pill-pres{background:#26215c;color:#cecbf6}.dark .pill-prog{background:#1b3d1b;color:#a5d6a7}.dark .pill-manual{background:#3e2a00;color:#ffcc80}.dark .pill-override{background:#4a1010;color:#f5b0b0}
.chart-wrap{background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);padding:16px;margin-bottom:14px}
.chart-header{display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:10px;flex-wrap:wrap;gap:8px}
.chart-title{font-size:12px;font-weight:500;color:var(--muted)}
.chart-subtitle{font-size:11px;color:var(--muted);margin-top:2px}
.chart-legend{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
.chart-legend span{display:flex;align-items:center;gap:5px;font-size:11px;color:var(--muted)}
.chart-legend i{display:inline-block;width:22px;height:3px;border-radius:2px;flex-shrink:0}
.chart-legend i.dotted{background:transparent !important;border-bottom:2px dashed currentColor;height:0;margin-bottom:1px}
.chart-legend .leg-sep{width:.5px;height:14px;background:var(--border);margin:0 2px}
.chart-container{position:relative;width:100%;height:260px}
.chart-container-sm{position:relative;width:100%;height:200px}
.table-wrap{background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);overflow-x:auto;margin-bottom:14px}
table{width:100%;border-collapse:collapse;font-size:12px;min-width:600px}
thead th{background:var(--bg);padding:8px 10px;text-align:left;font-weight:500;color:var(--muted);border-bottom:.5px solid var(--border);white-space:nowrap}
tbody tr:nth-child(even){background:var(--bg)}
tbody td{padding:6px 10px;border-bottom:.5px solid var(--border);white-space:nowrap}
tbody tr:last-child td{border-bottom:none}
.section-title{font-size:12px;font-weight:500;color:var(--muted);margin-bottom:8px}
/* ── Modal planning ── */
.modal-backdrop{display:none;position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:100;align-items:flex-start;justify-content:center;padding:16px;overflow-y:auto}
.modal-backdrop.open{display:flex}
.modal{background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);width:100%;max-width:1200px;margin:auto;padding:24px}
.modal-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px;gap:12px;flex-wrap:wrap}
.modal-title{font-size:15px;font-weight:500}
.modal-close{font-size:20px;color:var(--muted);cursor:pointer;background:none;border:none;line-height:1;padding:4px 8px;flex-shrink:0}
.modal-close:hover{color:var(--text)}
.sched-topbar{display:flex;align-items:center;gap:10px;margin-bottom:12px;flex-wrap:wrap}
.sched-note{font-size:11px;color:var(--muted);padding:8px 12px;background:var(--bg);border-radius:6px;border-left:3px solid var(--accent);flex:1;min-width:200px}
.debug-toggle{display:flex;align-items:center;gap:5px;font-size:11px;color:var(--muted);cursor:pointer;white-space:nowrap;flex-shrink:0}
.sched-legend{display:flex;gap:10px;margin-bottom:10px;flex-wrap:wrap}
.sched-legend span{display:flex;align-items:center;gap:5px;font-size:11px;color:var(--muted)}
.sched-legend i{display:inline-block;width:12px;height:12px;border-radius:2px;flex-shrink:0}
/* Grille 48 colonnes x 30min */
.sched-scroll{overflow-x:auto;padding-bottom:8px;margin-bottom:16px}
.sched-grid{
  display:grid;
  grid-template-columns:46px repeat(48,20px);
  gap:1px;
  min-width:calc(46px + 48*21px);
}
.sched-head{text-align:center;color:var(--muted);padding:2px 0;font-size:9px;font-weight:500;white-space:nowrap;line-height:1.2}
.sched-head.hour-mark{font-weight:700;color:var(--text);font-size:10px}
.sched-day{color:var(--muted);display:flex;align-items:center;font-size:11px;white-space:nowrap;padding-right:4px}
/* Cellule 30min */
.sched-cell{
  width:20px;height:32px;border-radius:2px;
  cursor:pointer;transition:all .1s;
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  user-select:none;flex-shrink:0;border:.5px solid transparent;
  font-size:9px;
}
.sched-cell.cft{background:var(--cft);border-color:#C8840A}
.sched-cell.eco{background:var(--eco);border-color:#1E5A8A}
.sched-cell.hg {background:var(--hg);border-color:#888780}
.sched-cell.off{background:var(--bg);border-color:var(--border)}
/* Separateur toutes les 2 cellules (= 1h) */
.sched-cell.hour-sep{border-left:.5px solid var(--border) !important}
.sched-cell:hover{opacity:.75;transform:scale(1.15);z-index:2;box-shadow:0 0 0 1.5px var(--accent)}
.cell-debug{font-size:7px;color:rgba(255,255,255,.7);line-height:1;pointer-events:none}
.dark .sched-cell.cft{background:#BA7517;border-color:#EF9F27}
  .dark .sched-cell.eco{background:#185fa5;border-color:#378ADD}
  .dark .sched-cell.hg {background:#5f5e5a;border-color:#888780}
  .dark .sched-cell.off{background:var(--bg);border-color:var(--border)}
.modal-footer{display:flex;justify-content:flex-end;gap:8px;padding-top:14px;border-top:.5px solid var(--border);margin-top:4px}
.spinner{display:inline-block;width:11px;height:11px;border:1.5px solid var(--border);border-top-color:var(--accent);border-radius:50%;animation:spin .7s linear infinite;flex-shrink:0}
@keyframes spin{to{transform:rotate(360deg)}}

.tw-btn{font-size:12px;padding:4px 12px;border:.5px solid var(--border);border-radius:14px;background:var(--bg);color:var(--muted);cursor:pointer;transition:all .15s;white-space:nowrap}
.tw-btn:hover{border-color:var(--accent);color:var(--text)}
.tw-btn.active{background:var(--accent);color:#fff;border-color:var(--accent);font-weight:500}
.theme-btn{font-size:12px;padding:4px 10px;border:.5px solid var(--border);border-radius:6px;background:var(--bg);color:var(--muted);cursor:pointer;white-space:nowrap;transition:all .15s}
.theme-btn:hover{border-color:var(--accent);color:var(--text)}
</style>
</head>
<body>
<h1>Heatzy Dashboard</h1>
<div class="toolbar">
  <label>Email</label><input type="email" id="inp-email" placeholder="compte@example.fr" autocomplete="username"/>
  <label>Mot de passe</label><input type="password" id="inp-pass" placeholder="••••••••" autocomplete="current-password"/>
  <label class="check-row"><input type="checkbox" id="chk-remember"/> Memoriser</label>
  <div class="sep"></div>
  <label>Refresh</label>
  <select id="inp-interval">
    <option value="0">Manuel</option><option value="60">1 min</option>
    <option value="300" selected>5 min</option><option value="600">10 min</option><option value="1800">30 min</option>
  </select>
  <div class="sep"></div>
  <button class="btn btn-primary" onclick="doRefresh()">Actualiser</button>
  <button class="btn" onclick="openFilePicker()">Importer log</button>
  <button class="btn btn-danger" onclick="clearAll()">Effacer</button>
  <div class="sep"></div>
  <button class="theme-btn" id="btn-theme" onclick="cycleTheme()">Systeme</button>
</div>
<div class="log-bar">
  <div class="log-info" id="log-info">Aucun fichier log charge.</div>
  <button class="btn btn-sm" onclick="downloadLog()">Exporter CSV</button>
  <div class="log-sep"></div>
  <div class="wx-bar" id="wx-bar"></div>
</div>
<div class="filter-bar" id="filter-bar" style="display:none">
  <span class="filter-label">Afficher :</span>
  <div id="filter-chips" style="display:flex;flex-wrap:wrap;gap:6px"></div>
  <span class="filter-all" onclick="filterAll(true)">Tout</span>
  <span class="filter-all" onclick="filterAll(false)">Aucun</span>
</div>
<div id="status">En attente.</div>
<div class="cards" id="cards-container"></div>
<div style="background:var(--surface);border:.5px solid var(--border);border-radius:var(--radius);padding:10px 14px;display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:12px">
  <span style="font-size:11px;font-weight:500;color:var(--muted);white-space:nowrap">Periode :</span>
  <button id="tw-1"    class="tw-btn"        data-h="1"    onclick="setTW(this)">1h</button>
  <button id="tw-4"    class="tw-btn"        data-h="4"    onclick="setTW(this)">4h</button>
  <button id="tw-8"    class="tw-btn"        data-h="8"    onclick="setTW(this)">8h</button>
  <button id="tw-24"   class="tw-btn active" data-h="24"   onclick="setTW(this)">24h</button>
  <button id="tw-168"  class="tw-btn"        data-h="168"  onclick="setTW(this)">7 jours</button>
  <button id="tw-720"  class="tw-btn"        data-h="720"  onclick="setTW(this)">30 jours</button>
  <button id="tw-8760" class="tw-btn"        data-h="8760" onclick="setTW(this)">1 an</button>
</div>
<div class="chart-wrap">
  <div class="chart-header"><span class="chart-title">Temperature reelle vs consigne (C)</span><div class="chart-legend" id="leg-temp"></div></div>
  <div class="chart-container"><canvas id="chart-temp"></canvas></div>
</div>
<div class="chart-wrap">
  <div class="chart-header"><span class="chart-title">Humidite relative (%)</span><div class="chart-legend" id="leg-humi"></div></div>
  <div class="chart-container-sm"><canvas id="chart-humi"></canvas></div>
</div>
<div class="chart-wrap">
  <div class="chart-header">
    <div><div class="chart-title">Radiateurs en chauffe (empile)</div>
    <div class="chart-subtitle">Hauteur = nombre de radiateurs ON simultanement</div></div>
    <div class="chart-legend" id="leg-events"></div>
  </div>
  <div class="chart-container-sm"><canvas id="chart-events"></canvas></div>
</div>
<div class="chart-wrap">
  <div class="chart-header">
    <div><div class="chart-title">Detection fenetre ouverte</div></div>
    <div class="chart-legend" id="leg-window"></div>
  </div>
  <div class="chart-container-sm"><canvas id="chart-window"></canvas></div>
</div>
<div class="section-title">Releves (50 derniers)</div>
<div class="table-wrap">
  <table><thead><tr id="table-head"><th>Heure</th></tr></thead><tbody id="table-body"></tbody></table>
</div>
<div class="modal-backdrop" id="modal-backdrop" onclick="closeModal(event)">
  <div class="modal" onclick="event.stopPropagation()">
    <div class="modal-header">
      <span class="modal-title" id="modal-title">Planning</span>
      <button class="modal-close" onclick="closeModalDirect()">x</button>
    </div>
    <div class="sched-topbar">
      <div class="sched-note" id="sched-note"></div>
      <label class="debug-toggle"><input type="checkbox" id="chk-debug" onchange="toggleDebug()"/> Debug (val. brutes)</label>
    </div>
    <div class="sched-legend">
      <span><i style="background:var(--cft)"></i>Confort</span>
      <span><i style="background:var(--eco)"></i>Eco</span>
      <span><i style="background:var(--hg)"></i>Hors-gel (10)</span>
      <span><i style="background:var(--bg);border:.5px solid var(--border)"></i>Arret</span>
      <span style="font-size:10px;color:var(--muted)">30 min/cellule · Clic=cycle · Doc Heatzy: 00=Confort 01=Eco 10=HG 11=Arret · Bits en ordre chrono inverse</span>
    </div>
    <div class="sched-scroll"><div class="sched-grid" id="sched-grid"></div></div>
    <div class="modal-footer">
      <button class="btn" onclick="closeModalDirect()">Fermer</button>
      <button class="btn btn-primary" id="btn-save-sched" onclick="saveSched()">Enregistrer le planning</button>
    </div>
  </div>
</div>
<script>
// ── Theme (dark/light/system) ───────────────────────────────────────────────
const LST='heatzy_theme';
const THEME_LABELS={system:'Systeme',light:'Clair',dark:'Sombre'};
const THEME_ICONS={system:'◐',light:'☀',dark:'☽'};

function isDark(){return document.documentElement.classList.contains('dark');}

function applyTheme(mode){
  const el=document.documentElement;
  if(mode==='dark'){el.classList.add('dark');}
  else if(mode==='light'){el.classList.remove('dark');}
  else{el.classList.toggle('dark',matchMedia('(prefers-color-scheme:dark)').matches);}
  const btn=document.getElementById('btn-theme');
  if(btn)btn.textContent=THEME_ICONS[mode]+' '+THEME_LABELS[mode];
  // Reconstruire les graphes si deja initialises (couleurs de grille)
  if(chartTemp&&devices.length){buildCharts();updateCharts();applyFilter();}
}

function cycleTheme(){
  const order=['system','light','dark'];
  const cur=localStorage.getItem(LST)||'system';
  const next=order[(order.indexOf(cur)+1)%order.length];
  localStorage.setItem(LST,next);
  applyTheme(next);
}

// Appliquer immediatement pour eviter le flash
(function(){
  const m=localStorage.getItem(LST)||'system';
  if(m==='dark')document.documentElement.classList.add('dark');
  else if(m==='system'&&matchMedia('(prefers-color-scheme:dark)').matches)document.documentElement.classList.add('dark');
  // Ecouter les changements systeme en mode 'system'
  matchMedia('(prefers-color-scheme:dark)').addEventListener('change',()=>{
    if((localStorage.getItem(LST)||'system')==='system')applyTheme('system');
  });
})();

const API='https://euapi.gizwits.com',AID='c70a66ff039d41b4a220e198b0fcc8b3';
const LSE='heatzy_email',LSP='heatzy_pass',LSR='heatzy_remember',LSF='heatzy_filter',LSL='heatzy_log_fallback';
const MAX_DAYS=365,MAX_PTS=MAX_DAYS*288;
const COLORS=['#378ADD','#1D9E75','#D85A30','#D4537E','#7F77DD','#BA7517','#E24B4A'];
const DAYS=['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];

let token=null,devices=[],activeFilter=new Set(),history=[],logEntries=[],fileHandle=null;
let chartTemp=null,chartHumi=null,chartEvents=null,chartWindow=null,timer=null,headersBuilt=false;
let modalDid=null,schedState={},lastSnapshot={},debugMode=false;
let weatherData=null,weatherHistory=[];

// ── Meteo Open-Meteo (gratuit, sans cle API) ────────────────────────────────
// Pas de coordonnees par defaut — l'utilisateur doit configurer sa localisation
const LSLAT='heatzy_lat',LSLON='heatzy_lon',LSLOC='heatzy_loc';
function hasCoords(){return localStorage.getItem(LSLAT)&&localStorage.getItem(LSLON);}
function getCoords(){return{lat:parseFloat(localStorage.getItem(LSLAT)),lon:parseFloat(localStorage.getItem(LSLON))};}
const WX_CODES={0:'☀',1:'🌤',2:'⛅',3:'☁',45:'🌫',48:'🌫',51:'🌦',53:'🌦',55:'🌧',56:'🌧',57:'🌧',61:'🌧',63:'🌧',65:'🌧',66:'🧊',67:'🧊',71:'🌨',73:'🌨',75:'❄',77:'❄',80:'🌦',81:'🌧',82:'🌧',85:'🌨',86:'🌨',95:'⛈',96:'⛈',99:'⛈'};

async function configLocation(){
  const input=prompt('Code postal ou ville (ex: 14000, Caen, Paris) :');
  if(!input)return;
  try{
    const r=await fetch('https://geocoding-api.open-meteo.com/v1/search?name='+encodeURIComponent(input)+'&count=1&language=fr&format=json');
    const j=await r.json();
    if(!j.results||!j.results.length){alert('Localisation introuvable.');return;}
    const loc=j.results[0];
    localStorage.setItem(LSLAT,loc.latitude);
    localStorage.setItem(LSLON,loc.longitude);
    localStorage.setItem(LSLOC,loc.name+(loc.admin1?', '+loc.admin1:''));
    await fetchWeather();
  }catch(e){alert('Erreur geocodage: '+e.message);}
}

async function fetchWeather(){
  if(!hasCoords()){
    // Afficher seulement le bouton de config
    document.getElementById('wx-bar').innerHTML='<button class="btn btn-sm" onclick="configLocation()">Meteo</button>';
    return;
  }
  try{
    const c=getCoords();
    const url=`https://api.open-meteo.com/v1/forecast?latitude=${c.lat}&longitude=${c.lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m&timezone=auto`;
    const r=await fetch(url);if(!r.ok)return;
    const j=await r.json();
    weatherData=j.current;
    weatherHistory.push({ts:new Date(),temp:weatherData.temperature_2m});
    if(weatherHistory.length>MAX_PTS)weatherHistory.shift();
    renderWeather();
  }catch(e){console.warn('Meteo:',e);}
}

function renderWeather(){
  if(!weatherData)return;
  const w=weatherData;
  const locName=localStorage.getItem(LSLOC)||'';
  const dirs=['N','NE','E','SE','S','SO','O','NO'];
  const di=Math.round(w.wind_direction_10m/45)%8;
  // Delta max int/ext (plus grand ecart)
  let maxDelta='',maxDeltaVal=0;
  if(lastSnapshot&&Object.keys(lastSnapshot).length){
    devices.filter(d=>activeFilter.has(d.name)).forEach(d=>{
      const a=lastSnapshot[d.name];if(!a)return;
      const delta=a.cur_temp/10-w.temperature_2m;
      if(Math.abs(delta)>Math.abs(maxDeltaVal)){maxDeltaVal=delta;maxDelta=d.name;}
    });
  }
  const deltaHtml=maxDelta?`<span class="wx-delta ${maxDeltaVal>0?'wx-delta-cold':'wx-delta-warm'}">${maxDelta} ${maxDeltaVal>0?'+':''}${maxDeltaVal.toFixed(1)}°C</span>`:'';
  document.getElementById('wx-bar').innerHTML=
    `<span class="wx-icon">${WX_CODES[w.weather_code]||'?'}</span>`+
    `<span class="wx-temp">${w.temperature_2m.toFixed(1)}°C</span>`+
    `<span class="wx-detail">${locName}</span>`+
    `<span class="wx-detail">Ressenti ${w.apparent_temperature.toFixed(0)}°C</span>`+
    `<span class="wx-detail">${w.wind_speed_10m.toFixed(0)} km/h ${dirs[di]}</span>`+
    deltaHtml+
    `<button class="btn btn-sm" onclick="configLocation()" style="margin-left:4px;font-size:10px;padding:2px 6px">Loc</button>`;
}

// ── Icones ──────────────────────────────────────────────────────────────────
const ICO_SNOW='<svg viewBox="0 0 24 24" fill="none" stroke="#378ADD" stroke-width="2.2" stroke-linecap="round"><line x1="12" y1="2" x2="12" y2="22"/><line x1="2" y1="12" x2="22" y2="12"/><line x1="5.5" y1="5.5" x2="18.5" y2="18.5"/><line x1="18.5" y1="5.5" x2="5.5" y2="18.5"/><line x1="12" y1="2" x2="9.5" y2="5"/><line x1="12" y1="2" x2="14.5" y2="5"/><line x1="12" y1="22" x2="9.5" y2="19"/><line x1="12" y1="22" x2="14.5" y2="19"/></svg>';
const ICO_MOON='<svg viewBox="0 0 24 24" fill="#378ADD" stroke="none"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
const ICO_SUN='<svg viewBox="0 0 24 24" fill="none" stroke="#EF9F27" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="5" fill="#EF9F27" stroke="none"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>';
function getModeIcon(m){return m==='cft'?{cls:'cft',svg:ICO_SUN}:m==='eco'?{cls:'eco',svg:ICO_MOON}:{cls:'fro',svg:ICO_SNOW}}
function getModeLabel(m){return{cft:'Confort',eco:'Eco',fro:'Hors-gel',hg:'Hors-gel',prog:'Prog',stop:'Arret',off:'Arret'}[m]||m}

// ── Decodage planning — Doc officielle Heatzy OpenAPI 3 ─────────────────────
// https://heatzy.com/blog/heatzy-openapi-3
// Chaque registre p{j}_data{n} encode une plage de 2h en 4 blocs de 2 bits (4x30min)
// Mapping officiel : 00=Confort  01=Eco  10=Hors-gel  11=Arret
// Ordre des bits : chronologie INVERSE (bits de poids faible = 1er creneau 30min)
const BIT_MAP={'00':'cft','01':'eco','10':'hg','11':'off'};

function decodeRegister(rawVal){
  const bits=rawVal.toString(2).padStart(8,'0');
  // Lecture de DROITE a GAUCHE (doc Heatzy : ordre chronologique inverse)
  return[6,4,2,0].map(i=>BIT_MAP[bits.substring(i,i+2)]||'cft');
}

function encodeRegister(slots4){
  // slots4 = [slot_0min, slot_30min, slot_60min, slot_90min]
  const revMap={cft:'00',eco:'01',hg:'10',off:'11'};
  // Ecriture en ordre inverse (slot 90min en MSB, slot 0min en LSB)
  const reversed=[...slots4].reverse();
  return parseInt(reversed.map(s=>revMap[s]||'00').join(''),2);
}

// Construit les 48 sous-creneaux de 30min pour un jour donne
// Retourne [{slot:0..47, hour:0..23, half:0|1, regIdx:1..12, bitIdx:0..3, mode, rawVal}]
function buildSlots(snap,day){
  const result=[];
  for(let reg=1;reg<=12;reg++){
    const key='p'+day+'_data'+reg;
    const raw=snap?.[key]??85;
    const modes=decodeRegister(raw);
    const baseHour=(reg-1)*2;
    for(let b=0;b<4;b++){
      const slotIdx=(reg-1)*4+b;
      const hour=baseHour+Math.floor(b/2);
      const half=b%2; // 0=:00, 1=:30
      result.push({slot:slotIdx,hour,half,regIdx:reg,bitIdx:b,mode:modes[b],rawVal:raw,regKey:key});
    }
  }
  return result; // 48 elements
}

function slotKey(day,slot){return day+'_'+slot}

// ── Utils ───────────────────────────────────────────────────────────────────
function setStatus(msg,cls){const el=document.getElementById('status');el.innerHTML=msg;el.className=cls||''}
function fmtTime(d){return d instanceof Date?d.toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit',second:'2-digit'}):String(d).substring(11,19)}
function fmtISO(d){return d.toISOString().replace('T',' ').substring(0,19)}

// ── Identifiants ─────────────────────────────────────────────────────────────
function loadCred(){try{const r=localStorage.getItem(LSR)==='1';document.getElementById('chk-remember').checked=r;if(r){document.getElementById('inp-email').value=localStorage.getItem(LSE)||'';document.getElementById('inp-pass').value=localStorage.getItem(LSP)||'';}}catch(e){}}
function saveCred(){try{const r=document.getElementById('chk-remember').checked;localStorage.setItem(LSR,r?'1':'0');if(r){localStorage.setItem(LSE,document.getElementById('inp-email').value.trim());localStorage.setItem(LSP,document.getElementById('inp-pass').value);}else{localStorage.removeItem(LSE);localStorage.removeItem(LSP);}}catch(e){}}

// ── Log fichier ──────────────────────────────────────────────────────────────
async function openFilePicker(){try{if(!window.showOpenFilePicker){loadFallback();return;}const[fh]=await window.showOpenFilePicker({types:[{description:'Heatzy JSON',accept:{'application/json':['.json']}}],multiple:false});fileHandle=fh;await readLog();}catch(e){if(e.name!=='AbortError')setStatus('Erreur ouverture:'+e.message,'error');}}
async function readLog(){if(!fileHandle)return;try{const f=await fileHandle.getFile();logEntries=JSON.parse(await f.text())||[];purge();rebuildHistory();updateLogInfo();}catch(e){setStatus('Erreur lecture:'+e.message,'error');}}
async function writeLog(){if(!fileHandle){saveFallback();return;}try{const w=await fileHandle.createWritable();await w.write(JSON.stringify(logEntries));await w.close();}catch(e){saveFallback();}}
function loadFallback(){try{const r=localStorage.getItem(LSL);if(r){logEntries=JSON.parse(r);purge();rebuildHistory();updateLogInfo();}}catch(e){}}
function saveFallback(){try{localStorage.setItem(LSL,JSON.stringify(logEntries));}catch(e){if(logEntries.length>1000){logEntries=logEntries.slice(-1000);try{localStorage.setItem(LSL,JSON.stringify(logEntries));}catch(e2){}}}}
function purge(){const c=new Date();c.setDate(c.getDate()-MAX_DAYS);const cs=c.toISOString().replace('T',' ').substring(0,19);logEntries=logEntries.filter(e=>e.ts>=cs);}
function updateLogInfo(){const el=document.getElementById('log-info');if(!logEntries.length){el.textContent='Aucun releve.';el.className='log-info';return;}el.textContent=logEntries.length+' releves · '+logEntries[0].ts.substring(0,10)+' -> '+logEntries[logEntries.length-1].ts.substring(0,10);el.className='log-info active';}
function rebuildHistory(){if(!devices.length||!logEntries.length)return;history=logEntries.slice(-MAX_PTS).map(e=>({ts:new Date(e.ts),data:e.data||{}}));if(chartTemp){updateCharts();updateTable();}}

// ── Filtre ───────────────────────────────────────────────────────────────────
function buildFilterBar(){
  document.getElementById('filter-bar').style.display='flex';
  document.getElementById('filter-chips').innerHTML='';
  try{const s=localStorage.getItem(LSF);activeFilter=s?new Set(JSON.parse(s)):new Set(devices.map(d=>d.name));}catch(e){activeFilter=new Set(devices.map(d=>d.name));}
  devices.forEach((d,i)=>{const chip=document.createElement('label');chip.className='filter-chip'+(activeFilter.has(d.name)?' active':'');chip.innerHTML=`<input type="checkbox" ${activeFilter.has(d.name)?'checked':''}/><span class="chip-dot" style="background:${COLORS[i%COLORS.length]}"></span>${d.name}`;chip.querySelector('input').addEventListener('change',e=>{e.target.checked?activeFilter.add(d.name):activeFilter.delete(d.name);chip.classList.toggle('active',e.target.checked);saveFilter();applyFilter();});document.getElementById('filter-chips').appendChild(chip);});
}
function filterAll(s){devices.forEach(d=>s?activeFilter.add(d.name):activeFilter.delete(d.name));document.querySelectorAll('#filter-chips .filter-chip').forEach(c=>{c.classList.toggle('active',s);c.querySelector('input').checked=s;});saveFilter();applyFilter();}
function saveFilter(){try{localStorage.setItem(LSF,JSON.stringify([...activeFilter]));}catch(e){}}
function applyFilter(){
  document.querySelectorAll('.card[data-name]').forEach(el=>{el.style.display=activeFilter.has(el.dataset.name)?'':'none';});
  if(chartTemp){devices.forEach((d,i)=>{const v=activeFilter.has(d.name);chartTemp.data.datasets[i*2].hidden=!v;chartTemp.data.datasets[i*2+1].hidden=!v;chartHumi.data.datasets[i].hidden=!v;chartEvents.data.datasets[i].hidden=!v;chartWindow.data.datasets[i].hidden=!v;});chartTemp.update('none');chartHumi.update('none');chartEvents.update('none');chartWindow.update('none');}
  updateTableVis();
}
function updateTableVis(){document.querySelectorAll('#table-head th').forEach((th,i)=>{if(i===0)return;const di=Math.floor((i-1)/7);if(di<devices.length)th.style.display=activeFilter.has(devices[di].name)?'':'none';});document.querySelectorAll('#table-body tr').forEach(tr=>{Array.from(tr.cells).forEach((td,i)=>{if(i===0)return;const di=Math.floor((i-1)/7);if(di<devices.length)td.style.display=activeFilter.has(devices[di].name)?'':'none';});});}

// ── API ──────────────────────────────────────────────────────────────────────
async function auth(){const e=document.getElementById('inp-email').value.trim(),p=document.getElementById('inp-pass').value;if(!e||!p){setStatus('Email et mot de passe requis.','error');return false;}const r=await fetch(API+'/app/login',{method:'POST',headers:{'Content-Type':'application/json','X-Gizwits-Application-Id':AID},body:JSON.stringify({username:e,password:p,lang:'fr'})});if(!r.ok){const er=await r.json().catch(()=>({}));setStatus('Erreur auth:'+(er.error_message||r.status),'error');return false;}token=(await r.json()).token;saveCred();return true;}
async function fetchDevices(){const r=await fetch(API+'/app/bindings?limit=30&skip=0',{headers:{'X-Gizwits-Application-Id':AID,'X-Gizwits-User-token':token}});if(!r.ok)throw new Error('Echec bindings:'+r.status);devices=((await r.json()).devices||[]).map(d=>({did:d.did,name:d.dev_alias||d.did}));}
async function fetchAttr(did){const r=await fetch(API+'/app/devdata/'+did+'/latest',{headers:{'X-Gizwits-Application-Id':AID,'X-Gizwits-User-token':token}});if(!r.ok)return null;return(await r.json()).attr||null;}
async function sendAttr(did,attrs){const r=await fetch(API+'/app/control/'+did,{method:'POST',headers:{'Content-Type':'application/json','X-Gizwits-Application-Id':AID,'X-Gizwits-User-token':token},body:JSON.stringify({attrs})});return r.ok;}

// ── Cycle principal ──────────────────────────────────────────────────────────
async function doRefresh(){
  setStatus('<span class="spinner"></span>Connexion...','');
  try{
    if(!token){const ok=await auth();if(!ok)return;}
    if(devices.length===0){setStatus('<span class="spinner"></span>Recuperation...','');await fetchDevices();buildFilterBar();buildTableHead();buildCharts();rebuildHistory();}
    setStatus('<span class="spinner"></span>Lecture '+devices.length+' appareils...','');
    const res=await Promise.all(devices.map(d=>fetchAttr(d.did)));
    const snap={};devices.forEach((d,i)=>{if(res[i])snap[d.name]=res[i];});
    lastSnapshot=snap;
    const now=new Date();
    const outTemp=weatherData?weatherData.temperature_2m:null;
    history.push({ts:now,data:snap,outTemp});if(history.length>MAX_PTS)history.shift();
    const entry={ts:fmtISO(now),data:{}};devices.forEach(d=>{const a=snap[d.name];if(a)entry.data[d.name]={cur_temp:a.cur_temp,cur_humi:a.cur_humi,cur_mode:a.cur_mode,Heating_state:a.Heating_state,window_switch:a.window_switch,cft_temp:a.cft_temp,eco_temp:a.eco_temp,timer_switch:a.timer_switch??-1,derog_mode:a.derog_mode??0,derog_time:a.derog_time??0};});
    logEntries.push(entry);purge();await writeLog();updateLogInfo();
    renderCards(snap);updateCharts();updateTable();applyFilter();renderWeather();
    // Meteo toutes les 15 min (~3 refresh a 5 min)
    if(!weatherData||history.length%3===0) fetchWeather();
    const iv=parseInt(document.getElementById('inp-interval').value);
    setStatus('Actualise '+fmtTime(now)+' - '+devices.length+' appareils'+(iv>0?' · dans '+(iv>=60?Math.round(iv/60)+'min':iv+'s'):''),'ok');
  }catch(err){if(String(err).includes('401'))token=null;setStatus('Erreur:'+err.message,'error');}
}

// ── Cartes ───────────────────────────────────────────────────────────────────

// Determine le mode prevu par le planning pour l'instant courant
// Retourne {mode:'cft'|'eco'|'hg'|'off', label:'Confort'|...} ou null si pas de donnees planning
function getPlannedMode(snap){
  if(!snap) return null;
  const now=new Date();
  // Jour : JS 0=Dim, Heatzy 1=Lun..7=Dim
  const jsDay=now.getDay(); // 0=Dim
  const hDay=jsDay===0?7:jsDay; // 1=Lun..7=Dim
  const hour=now.getHours();
  const min=now.getMinutes();
  // Registre : data1=00h-02h .. data12=22h-24h
  const regIdx=Math.floor(hour/2)+1;
  const key='p'+hDay+'_data'+regIdx;
  const raw=snap[key];
  if(raw===undefined||raw===null) return null;
  const modes=decodeRegister(raw);
  // Sous-creneau dans le registre (4 x 30min)
  const minuteInReg=(hour%2)*60+min;
  const slotIdx=Math.min(Math.floor(minuteInReg/30),3);
  const mode=modes[slotIdx];
  return{mode,label:getModeLabel(mode)};
}

function renderCards(snap){
  const w=document.getElementById('cards-container');w.innerHTML='';
  const filtered=getFilteredHistory();
  devices.forEach(d=>{
    const a=snap[d.name];if(!a)return;
    const heating=a.Heating_state===1,winOpen=a.window_switch===1;
    const ic=getModeIcon(a.cur_mode);
    // Consigne selon mode : Confort→cft_temp, Eco→eco_temp, Hors-gel→7°C fixe, Arret→--
    const csg=a.cur_mode==='cft'?(a.cft_temp/10).toFixed(0)
             :a.cur_mode==='eco'?(a.eco_temp/10).toFixed(0)
             :a.cur_mode==='fro'?'7':'--';
    const bc=a.cur_mode==='cft'?'mode-cft':a.cur_mode==='eco'?'mode-eco':'mode-fro';
    let ind='';
    // Indicateur Planning vs Manuel
    const isProg=(a.timer_switch===1);
    const isManual=(a.timer_switch===0);
    if(isProg){
      const planned=getPlannedMode(a);
      const curNorm=a.cur_mode==='fro'?'hg':a.cur_mode==='stop'?'off':a.cur_mode;
      if(planned && planned.mode!==curNorm){
        ind+=`<span class="pill pill-override"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>Derog. (prog=${planned.label})</span>`;
      } else {
        ind+=`<span class="pill pill-prog"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>Prog</span>`;
      }
    } else if(isManual){
      ind+=`<span class="pill pill-manual"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M18 8h1a4 4 0 010 8h-1"/><path d="M2 8h16v9a4 4 0 01-4 4H6a4 4 0 01-4-4V8z"/></svg>Manuel</span>`;
    }
    if(heating){
      // Verifier coherence : chauffe active alors que T > consigne+1 ?
      const tempC=a.cur_temp/10;
      const csgNum=a.cur_mode==='cft'?(a.cft_temp/10):a.cur_mode==='eco'?(a.eco_temp/10):a.cur_mode==='fro'?7:0;
      const incoherent=csgNum>0 && tempC>csgNum+1;
      if(incoherent){
        ind+=`<span class="pill pill-heat" style="opacity:.6"><svg width="10" height="10" viewBox="0 0 24 24" fill="#D85A30"><path d="M12 2C8 7 6 10 6 13a6 6 0 0 0 12 0c0-3-2-6-4-8-1 3-2 4-2 4z"/></svg>Chauffe (?)</span>`;
      } else {
        ind+=`<span class="pill pill-heat"><svg width="10" height="10" viewBox="0 0 24 24" fill="#D85A30"><path d="M12 2C8 7 6 10 6 13a6 6 0 0 0 12 0c0-3-2-6-4-8-1 3-2 4-2 4z"/></svg>Chauffe</span>`;
      }
    }
    if(winOpen)ind+=`<span class="pill pill-win"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#BA7517" stroke-width="2.5" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="12" y1="3" x2="12" y2="21"/><line x1="3" y1="12" x2="21" y2="12"/></svg>Fenetre</span>`;
    // Statistique chauffe sur la periode affichee
    let statHtml='';
    if(filtered.length>=2){
      const pts=filtered.filter(h=>h.data[d.name]!=null);
      const onPts=pts.filter(h=>h.data[d.name].Heating_state===1).length;
      const pct=pts.length>0?Math.round(100*onPts/pts.length):0;
      const winPts=pts.filter(h=>h.data[d.name].window_switch===1).length;
      const winPct=pts.length>0?Math.round(100*winPts/pts.length):0;
      statHtml=`<div class="card-sub card-stat">Chauffe ${pct}%${winPct>0?' · Fen. '+winPct+'%':''}</div>`;
    }
    w.innerHTML+=`<div class="card ${bc}" data-name="${d.name}" data-did="${d.did}">
      <div class="card-header"><span class="card-name">${d.name}</span>
        <div class="card-actions">
          <button class="card-plan-btn" onclick="openModal('${d.did}','${d.name}')">Planning</button>
          <button class="card-plan-btn" onclick="toggleModePopup(event,'pop-${d.did}')">Mode</button>
          <div class="mode-popup" id="pop-${d.did}">
            <button class="mode-popup-btn m-prog" onclick="doReturnProg('${d.did}','${d.name}',this)">↩ Retour prog</button>
            <div style="height:1px;background:var(--border);margin:2px 0"></div>
            <button class="mode-popup-btn m-cft${a.cur_mode==='cft'?' current':''}" onclick="doOverride('${d.did}','${d.name}','cft',this)">☀ Confort${a.cur_mode==='cft'?' ●':''}</button>
            <button class="mode-popup-btn m-eco${a.cur_mode==='eco'?' current':''}" onclick="doOverride('${d.did}','${d.name}','eco',this)">☽ Eco${a.cur_mode==='eco'?' ●':''}</button>
            <button class="mode-popup-btn m-fro${a.cur_mode==='fro'?' current':''}" onclick="doOverride('${d.did}','${d.name}','fro',this)">❄ Hors-gel${a.cur_mode==='fro'?' ●':''}</button>
            <button class="mode-popup-btn m-stop${a.cur_mode==='stop'?' current':''}" onclick="doOverride('${d.did}','${d.name}','stop',this)">⊘ Arret${a.cur_mode==='stop'?' ●':''}</button>
          </div>
          <span class="mode-icon ${ic.cls}">${ic.svg}</span>
        </div>
      </div>
      <div class="card-temp">${(a.cur_temp/10).toFixed(1)}C</div>
      <div class="card-sub">${a.cur_humi}% HR</div>
      <div class="card-sub">Consigne ${csg}C${weatherData?' · \u0394'+(a.cur_temp/10-weatherData.temperature_2m).toFixed(1)+'°C ext':''}</div>
      ${statHtml}
      <div class="card-indicators">${ind}</div>
    </div>`;
  });
}

// ── Graphes ──────────────────────────────────────────────────────────────────
// Detecte les trous de collecte et insere null pour casser la ligne
function injectGaps(filtered,extractor,gapThresholdMs){
  if(!filtered.length) return[];
  const out=[];
  for(let i=0;i<filtered.length;i++){
    if(i>0){const delta=filtered[i].ts-filtered[i-1].ts;if(delta>gapThresholdMs)out.push(null);}
    out.push(extractor(filtered[i]));
  }
  return out;
}
function labelsWithGaps(filtered,gapThresholdMs){
  if(!filtered.length) return[];
  const out=[];
  for(let i=0;i<filtered.length;i++){
    if(i>0){const delta=filtered[i].ts-filtered[i-1].ts;if(delta>gapThresholdMs)out.push('');}
    out.push(fmtTime(filtered[i].ts));
  }
  return out;
}

function buildCharts(){
  const dk=isDark();
  const g=dk?'rgba(255,255,255,.06)':'rgba(0,0,0,.06)',t=dk?'#9c9a92':'#888780';
  function lo(mn,mx,cb){return{responsive:true,maintainAspectRatio:false,animation:{duration:200},plugins:{legend:{display:false},tooltip:{mode:'index',intersect:false}},scales:{x:{ticks:{font:{size:11},maxTicksLimit:8,color:t,autoSkip:true},grid:{color:g}},y:{min:mn,max:mx,ticks:{font:{size:11},color:t,callback:cb},grid:{color:g}}}};}
  function ld(i,lbl){return{label:lbl||'',data:[],borderColor:COLORS[i%COLORS.length],backgroundColor:'transparent',borderWidth:1.5,pointRadius:0,tension:0.3,spanGaps:false};}
  // Temp chart : real temp lines + consigne stepped lines + outdoor temp
  const tempDs=[];
  devices.forEach((d,i)=>{
    tempDs.push({...ld(i,d.name),pointRadius:2});
    tempDs.push({...ld(i,d.name+' consigne'),borderDash:[6,4],borderWidth:1,pointRadius:0,stepped:'before',opacity:1,borderColor:COLORS[i%COLORS.length]+'88'});
  });
  // Dernier dataset = temperature exterieure (grise, pointillee epaisse)
  tempDs.push({label:'Exterieur',data:[],borderColor:dk?'#888780':'#B4B2A9',backgroundColor:'transparent',borderWidth:2,borderDash:[8,4],pointRadius:0,tension:0.3,spanGaps:false});
  chartTemp=new Chart(document.getElementById('chart-temp'),{type:'line',data:{labels:[],datasets:tempDs},options:lo(0,30,v=>v.toFixed(1)+'C')});
  chartHumi=new Chart(document.getElementById('chart-humi'),{type:'line',data:{labels:[],datasets:devices.map((d,i)=>({...ld(i,d.name),pointRadius:2}))},options:lo(20,100,v=>v+'%')});
  // Stacked area pour Heating_state
  const heatDs=devices.map((d,i)=>{
    const c=COLORS[i%COLORS.length];
    return{label:d.name,data:[],borderColor:c,backgroundColor:c+'44',borderWidth:1,pointRadius:0,fill:true,stepped:'before',spanGaps:false};
  });
  chartEvents=new Chart(document.getElementById('chart-events'),{type:'line',data:{labels:[],datasets:heatDs},options:{
    responsive:true,maintainAspectRatio:false,animation:{duration:200},
    plugins:{legend:{display:false},tooltip:{mode:'index',intersect:false}},
    scales:{x:{ticks:{font:{size:11},maxTicksLimit:10,color:t,autoSkip:true},grid:{color:g}},
      y:{stacked:true,min:0,max:devices.length,ticks:{font:{size:11},color:t,stepSize:1,callback:v=>Number.isInteger(v)?v:''},grid:{color:g}}}}});
  // Fenetre chart
  const winDs=devices.map((d,i)=>{
    const c=COLORS[i%COLORS.length];
    return{label:d.name,data:[],borderColor:c,backgroundColor:'transparent',borderWidth:1.5,borderDash:[4,3],pointRadius:0,stepped:'before',spanGaps:false};
  });
  chartWindow=new Chart(document.getElementById('chart-window'),{type:'line',data:{labels:[],datasets:winDs},options:{
    responsive:true,maintainAspectRatio:false,animation:{duration:200},
    plugins:{legend:{display:false},tooltip:{mode:'index',intersect:false}},
    scales:{x:{ticks:{font:{size:11},maxTicksLimit:10,color:t,autoSkip:true},grid:{color:g}},
      y:{min:-0.1,max:1.1,ticks:{font:{size:11},color:t,callback:v=>v===1?'Ouvert':v===0?'Ferme':''},grid:{color:g}}}}});
  const ll=devices.map((d,i)=>`<span><i style="background:${COLORS[i%COLORS.length]}"></i>${d.name}</span>`).join('');
  document.getElementById('leg-temp').innerHTML=ll+`<span class="leg-sep"></span><span><i style="background:${dk?'#888780':'#B4B2A9'};height:2px" class="dotted"></i>Exterieur</span><span style="font-size:11px;color:var(--muted)">plein=reel · tirets fins=consigne</span>`;
  document.getElementById('leg-humi').innerHTML=ll;
  document.getElementById('leg-events').innerHTML=ll;
  document.getElementById('leg-window').innerHTML=ll;
}
function updateCharts(){
  if(!chartTemp)return;
  const filtered=getFilteredHistory();
  // Seuil de gap = 2x l'intervalle de refresh (defaut 5min) ou 15min minimum
  const iv=parseInt(document.getElementById('inp-interval').value)||300;
  const gap=Math.max(iv*2,900)*1000;
  const labels=labelsWithGaps(filtered,gap);
  chartTemp.data.labels=labels;chartHumi.data.labels=labels;chartEvents.data.labels=labels;chartWindow.data.labels=labels;
  devices.forEach((d,i)=>{
    // Temp reelle
    chartTemp.data.datasets[i*2].data=injectGaps(filtered,h=>h.data[d.name]?parseFloat((h.data[d.name].cur_temp/10).toFixed(1)):null,gap);
    // Consigne (stepped) : cft→cft_temp, eco→eco_temp, fro→7, stop→null
    chartTemp.data.datasets[i*2+1].data=injectGaps(filtered,h=>{
      const a=h.data[d.name];if(!a)return null;
      if(a.cur_mode==='cft')return a.cft_temp?a.cft_temp/10:null;
      if(a.cur_mode==='eco')return a.eco_temp?a.eco_temp/10:null;
      if(a.cur_mode==='fro')return 7;
      return null;
    },gap);
    chartHumi.data.datasets[i].data=injectGaps(filtered,h=>h.data[d.name]?h.data[d.name].cur_humi:null,gap);
    chartEvents.data.datasets[i].data=injectGaps(filtered,h=>h.data[d.name]!=null?h.data[d.name].Heating_state:null,gap);
    chartWindow.data.datasets[i].data=injectGaps(filtered,h=>h.data[d.name]!=null?h.data[d.name].window_switch:null,gap);
  });
  // Temperature exterieure (dernier dataset du chartTemp)
  const outIdx=devices.length*2;
  chartTemp.data.datasets[outIdx].data=injectGaps(filtered,h=>h.outTemp??null,gap);
  chartTemp.update('none');chartHumi.update('none');chartEvents.update('none');chartWindow.update('none');
}

// ── Tableau ──────────────────────────────────────────────────────────────────
function buildTableHead(){if(headersBuilt)return;headersBuilt=true;const tr=document.getElementById('table-head');devices.forEach(d=>{['T','HR%','Mode','Source','Derog','Chauffe','Fenetre'].forEach(c=>{const th=document.createElement('th');th.textContent=d.name+' '+c;tr.appendChild(th);});});}
function updateTable(){const tb=document.getElementById('table-body');tb.innerHTML='';[...getFilteredHistory()].reverse().slice(0,50).forEach(h=>{let html=`<td>${fmtTime(h.ts)}</td>`;devices.forEach(d=>{const a=h.data[d.name];if(a){const src=a.timer_switch===1?'Prog':a.timer_switch===0?'Manuel':'?';const dm=a.derog_mode??0;const dl=['','\u2708','\u26A1','\uD83D\uDC64'][dm]||'';html+=`<td>${(a.cur_temp/10).toFixed(1)}</td><td>${a.cur_humi}%</td><td>${getModeLabel(a.cur_mode)}</td><td>${src}</td><td>${dl}</td><td style="color:${a.Heating_state?'var(--danger)':'var(--muted)'}">${a.Heating_state?'OUI':'-'}</td><td style="color:${a.window_switch?'var(--warn)':'var(--muted)'}">${a.window_switch?'OUI':'-'}</td>`;}else html+='<td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td>';});const tr=document.createElement('tr');tr.innerHTML=html;tb.appendChild(tr);});}

// ── Modal planning 48x30min ──────────────────────────────────────────────────
function openModal(did,name){
  modalDid=did;schedState={};debugMode=false;document.getElementById('chk-debug').checked=false;
  document.getElementById('modal-title').textContent='Planning - '+name;
  const snap=lastSnapshot[name];
  const modeNote = snap
    ? 'Planning programme (independant du mode actuel) | Confort:' +
      (snap.cft_temp/10).toFixed(0)+'C | Eco:'+(snap.eco_temp/10).toFixed(0)+
      'C | Mode actuel: '+getModeLabel(snap.cur_mode)+' | 48 creneaux x 30 min'
    : 'Actualisez d abord.';
  document.getElementById('sched-note').textContent = modeNote;
  buildSchedGrid(snap);
  document.getElementById('modal-backdrop').classList.add('open');
}

function buildSchedGrid(snap){
  const grid=document.getElementById('sched-grid');grid.innerHTML='';
  // En-tete : etiquettes heures toutes les 2 cellules (=1h)
  grid.appendChild(Object.assign(document.createElement('div'),{className:'sched-head'}));
  for(let s=0;s<48;s++){
    const el=document.createElement('div');
    if(s%2===0){
      el.className='sched-head hour-mark';
      el.textContent=(s/2)+'h';
    } else {
      el.className='sched-head';
      el.textContent='';
    }
    grid.appendChild(el);
  }
  // Lignes jours
  for(let day=1;day<=7;day++){
    grid.appendChild(Object.assign(document.createElement('div'),{className:'sched-day',textContent:DAYS[day-1].substring(0,3)+'.'}));
    const slots=buildSlots(snap,day);
    slots.forEach(slot=>{
      const ck=slotKey(day,slot.slot);
      schedState[ck]={mode:slot.mode,regIdx:slot.regIdx,bitIdx:slot.bitIdx,regKey:slot.regKey,rawVal:slot.rawVal};
      const cell=document.createElement('div');
      cell.className='sched-cell '+slot.mode+(slot.slot%2===0?' hour-sep':'');
      cell.dataset.key=ck;
      if(debugMode&&slot.half===0&&slot.bitIdx===0){const dbg=document.createElement('span');dbg.className='cell-debug';dbg.textContent=slot.rawVal;cell.appendChild(dbg);}
      cell.title=DAYS[day-1]+' '+(slot.hour<10?'0':'')+slot.hour+'h'+(slot.half===0?'00':'30');
      cell.onclick=()=>cycleCell(cell,ck);
      grid.appendChild(cell);
    });
  }
}

function toggleDebug(){
  debugMode=document.getElementById('chk-debug').checked;
  // Afficher/masquer la valeur brute sur la 1ere cellule de chaque registre
  document.querySelectorAll('.sched-cell').forEach(cell=>{
    const k=cell.dataset.key;if(!k)return;
    const s=schedState[k];if(!s)return;
    const isFirst=s.bitIdx===0;
    let dbg=cell.querySelector('.cell-debug');
    if(debugMode&&isFirst){if(!dbg){dbg=document.createElement('span');dbg.className='cell-debug';cell.appendChild(dbg);}dbg.textContent=s.rawVal;}
    else if(dbg){dbg.remove();}
  });
}

// Cycle clic : cft -> eco -> hg -> off -> cft (ordre naturel)
function cycleCell(cell,ck){
  const order=['cft','eco','hg','off'];
  const s=schedState[ck];
  const next=order[(order.indexOf(s.mode)+1)%order.length];
  schedState[ck]={...s,mode:next};
  cell.className='sched-cell '+next+(ck.split('_')[1]%2===0?' hour-sep':'');
  if(debugMode){let dbg=cell.querySelector('.cell-debug');if(dbg){// recalculer rawVal du registre
    const day=parseInt(ck.split('_')[0]);
    const raw=calcRaw(day,s.regIdx);
    dbg.textContent=raw;}}
}

// Recalcule la valeur brute d'un registre depuis schedState
function calcRaw(day,regIdx){
  const revMap={cft:'00',eco:'01',hg:'10',off:'11'};
  const baseSlot=(regIdx-1)*4;
  // Collecter les 4 modes dans l'ordre chronologique
  let slots=[];
  for(let b=0;b<4;b++){
    const ck=slotKey(day,baseSlot+b);
    const s=schedState[ck];
    slots.push(s?revMap[s.mode]||'00':'00');
  }
  // Ecrire en ordre inverse (dernier creneau = MSB, premier = LSB)
  slots.reverse();
  return parseInt(slots.join(''),2);
}

async function saveSched(){
  if(!modalDid||!token){alert('Non connecte.');return;}
  const btn=document.getElementById('btn-save-sched');btn.textContent='Envoi...';btn.disabled=true;
  const attrs={};
  for(let day=1;day<=7;day++){
    for(let reg=1;reg<=12;reg++){
      attrs['p'+day+'_data'+reg]=calcRaw(day,reg);
    }
  }
  const ok=await sendAttr(modalDid,attrs);btn.textContent='Enregistrer le planning';btn.disabled=false;
  if(ok){setStatus('Planning enregistre.','ok');closeModalDirect();doRefresh();}
  else alert('Erreur envoi.');
}

function closeModal(e){if(e.target===document.getElementById('modal-backdrop'))closeModalDirect();}
function closeModalDirect(){document.getElementById('modal-backdrop').classList.remove('open');}

// ── Override mode — dropdown cliquable sur carte ─────────────────────────────
// ── Retry progressif apres override ──────────────────────────────────────────
// Rafraichit a 3s, 6s, 12s pour laisser l'API Gizwits refleter le changement
function retryRefresh(maxRetries){
  let attempt=0;
  const delays=[3000,6000,12000];
  function go(){
    if(attempt>=maxRetries)return;
    const d=delays[attempt]||12000;
    attempt++;
    setTimeout(async()=>{
      await doRefresh();
      go();
    },d);
  }
  go();
}

function toggleModePopup(ev,popId){
  ev.stopPropagation();
  // Fermer tous les autres popups
  document.querySelectorAll('.mode-popup.open').forEach(p=>{if(p.id!==popId)p.classList.remove('open');});
  document.getElementById(popId).classList.toggle('open');
}
// Fermer le popup si clic ailleurs
document.addEventListener('click',()=>{document.querySelectorAll('.mode-popup.open').forEach(p=>p.classList.remove('open'));});

async function doOverride(did,name,apiMode,btn){
  if(!token){setStatus('Non connecte. Actualisez d abord.','error');return;}
  const label=getModeLabel(apiMode==='stop'?'off':apiMode==='fro'?'hg':apiMode);
  // Feedback visuel immédiat
  btn.textContent='⏳ Envoi...';btn.disabled=true;
  setStatus(`<span class="spinner"></span>Envoi ${label} a ${name}...`,'');
  const ok=await sendAttr(did,{mode:apiMode});
  // Fermer le popup
  btn.closest('.mode-popup').classList.remove('open');
  if(ok){
    setStatus(`✓ ${name} → ${label} (derogation active)`,'ok');
    const card=document.querySelector(`.card[data-did="${did}"]`);
    if(card){card.style.outline='2px solid var(--success)';card.style.outlineOffset='1px';setTimeout(()=>{card.style.outline='';card.style.outlineOffset='';},2000);}
    // Retry progressif : 3s, 6s, 12s pour laisser l'API refleter le changement
    retryRefresh(3);
  } else {
    setStatus('✗ Erreur envoi commande a '+name,'error');
    btn.textContent='Erreur';setTimeout(()=>{btn.disabled=false;btn.textContent=label;},2000);
  }
}

async function doReturnProg(did,name,btn){
  if(!token){setStatus('Non connecte. Actualisez d abord.','error');return;}
  btn.textContent='⏳...';btn.disabled=true;
  // Determiner le mode prevu par le planning maintenant
  const snap=lastSnapshot[name];
  const planned=snap?getPlannedMode(snap):null;
  // Convertir mode planning (cft/eco/hg/off) vers API (cft/eco/fro/stop)
  const apiModeMap={cft:'cft',eco:'eco',hg:'fro',off:'stop'};
  const targetMode=planned?apiModeMap[planned.mode]||'cft':'cft';
  const targetLabel=planned?planned.label:'Confort';
  setStatus(`<span class="spinner"></span>Retour planning ${name} → ${targetLabel}...`,'');
  // Envoyer le mode prevu + desactiver la derogation
  const ok=await sendAttr(did,{mode:targetMode,derog_mode:0,derog_time:0});
  btn.closest('.mode-popup').classList.remove('open');
  if(ok){
    setStatus(`✓ ${name} → ${targetLabel} (planning)`,'ok');
    const card=document.querySelector(`.card[data-did="${did}"]`);
    if(card){card.style.outline='2px solid var(--success)';card.style.outlineOffset='1px';setTimeout(()=>{card.style.outline='';card.style.outlineOffset='';},2000);}
    retryRefresh(3);
  } else {
    setStatus('✗ Erreur retour planning '+name,'error');
    btn.textContent='↩ Retour prog';btn.disabled=false;
  }
}

// ── Export CSV ────────────────────────────────────────────────────────────────
function downloadLog(){if(!logEntries.length){setStatus('Aucun releve.','warn');return;}const dn=[...new Set(logEntries.flatMap(e=>Object.keys(e.data||{})))];const cols=['Horodatage'];dn.forEach(n=>cols.push(n+'_temp',n+'_humi',n+'_mode',n+'_chauffe',n+'_fenetre',n+'_prog',n+'_derog'));const rows=[cols.join(';')];logEntries.forEach(e=>{const row=[e.ts];dn.forEach(n=>{const a=e.data?.[n];if(a){const dm=a.derog_mode??0;const dl=['','Vacances','Boost','Presence'][dm]||'';row.push((a.cur_temp/10).toFixed(1),a.cur_humi,a.cur_mode,a.Heating_state,a.window_switch,a.timer_switch??'',dl);}else row.push('','','','','','','');});rows.push(row.join(';'));});const blob=new Blob(['\uFEFF'+rows.join('\r\n')],{type:'text/csv;charset=utf-8;'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='heatzy_log_'+new Date().toISOString().substring(0,10)+'.csv';a.click();URL.revokeObjectURL(url);}
function clearAll(){if(!confirm('Effacer tout?'))return;history=[];logEntries=[];try{localStorage.removeItem(LSL);}catch(e){}[chartTemp,chartHumi,chartEvents,chartWindow].forEach(c=>{if(!c)return;c.data.labels=[];c.data.datasets.forEach(ds=>ds.data=[]);c.update('none');});document.getElementById('table-body').innerHTML='';updateLogInfo();setStatus('Efface.','');}

// ── Timer + init ──────────────────────────────────────────────────────────────

// ── Fenetre temporelle ─────────────────────────────────────────────────────
let currentWindowHours = 24;

function setTW(btn) {
  currentWindowHours = parseInt(btn.dataset.h);
  document.querySelectorAll('.tw-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  updateCharts();
  updateTable();
  // Recalculer les stats chauffe% sur les cartes
  if(lastSnapshot && Object.keys(lastSnapshot).length) renderCards(lastSnapshot);
  applyFilter();
}

function getFilteredHistory() {
  if(currentWindowHours >= 8760) return history; // tout
  const cutoff = new Date(Date.now() - currentWindowHours * 3600 * 1000);
  return history.filter(h => h.ts >= cutoff);
}

function startTimer(){clearInterval(timer);const v=parseInt(document.getElementById('inp-interval').value);if(v>0)timer=setInterval(doRefresh,v*1000);}
document.getElementById('inp-interval').addEventListener('change',startTimer);
loadCred();loadFallback();fetchWeather();applyTheme(localStorage.getItem(LST)||'system');document.getElementById('inp-email').focus();
// PWA — service worker registration
if('serviceWorker' in navigator){navigator.serviceWorker.register('sw.js').catch(()=>{});}
</script>
</body>
</html>
'@

$Manifest = @'
{
  "name": "Heatzy Dashboard",
  "short_name": "Heatzy",
  "description": "Dashboard chauffage Heatzy Pilote Pro",
  "start_url": "./Heatzy-Dashboard.html",
  "display": "standalone",
  "background_color": "#1c1c1a",
  "theme_color": "#1c1c1a",
  "orientation": "any",
  "icons": [
    {"src": "icon-192.png", "sizes": "192x192", "type": "image/png"},
    {"src": "icon-512.png", "sizes": "512x512", "type": "image/png"}
  ]
}
'@

$ServiceWorker = @'
const CACHE='heatzy-v12';
const ASSETS=['./Heatzy-Dashboard.html','./manifest.json','https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting()));});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',e=>{
  const url=new URL(e.request.url);
  // API calls et meteo : toujours reseau (pas de cache)
  if(url.hostname.includes('gizwits.com')||url.hostname.includes('open-meteo.com')){e.respondWith(fetch(e.request));return;}
  // Tout le reste : cache-first avec fallback reseau
  e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request).then(resp=>{if(resp.ok){const cl=resp.clone();caches.open(CACHE).then(c=>c.put(e.request,cl));}return resp;})));
});
'@

# Generateur d'icone SVG (pas de fichier PNG externe necessaire)
$IconSvg = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<rect width="512" height="512" rx="64" fill="#1c1c1a"/>
<text x="256" y="320" font-size="280" text-anchor="middle" fill="#EF9F27" font-family="sans-serif" font-weight="700">H</text>
<circle cx="380" cy="140" r="40" fill="#D85A30"/>
<path d="M380 110 Q388 90 395 100 Q402 80 410 110 Q402 120 395 115 Q388 120 380 110Z" fill="#EF9F27"/>
</svg>
'@

Write-Host "`n[INFO] Generation dashboard v12 PWA..." -ForegroundColor Cyan
$HtmlPath=Join-Path $OutputDir "Heatzy-Dashboard.html"
$CollectorPath=Join-Path $OutputDir "Heatzy-Collector.ps1"
$ManifestPath=Join-Path $OutputDir "manifest.json"
$SwPath=Join-Path $OutputDir "sw.js"
$Icon192Path=Join-Path $OutputDir "icon-192.png"
$Icon512Path=Join-Path $OutputDir "icon-512.png"
$IconSvgPath=Join-Path $OutputDir "icon.svg"
try{
  $Html|Out-File -FilePath $HtmlPath -Encoding UTF8 -Force
  $CollectorScript|Out-File -FilePath $CollectorPath -Encoding UTF8 -Force
  $Manifest|Out-File -FilePath $ManifestPath -Encoding UTF8 -Force
  $ServiceWorker|Out-File -FilePath $SwPath -Encoding UTF8 -Force
  $IconSvg|Out-File -FilePath $IconSvgPath -Encoding UTF8 -Force
  Write-Host "[OK] Dashboard  : $HtmlPath" -ForegroundColor Green
  Write-Host "[OK] Collecteur : $CollectorPath" -ForegroundColor Green
  Write-Host "[OK] Manifest   : $ManifestPath" -ForegroundColor Green
  Write-Host "[OK] SW         : $SwPath" -ForegroundColor Green
  Write-Host "[OK] Icone SVG  : $IconSvgPath" -ForegroundColor Green
  Write-Host ""
  Write-Host "[INFO] Pour les icones PNG (Android), convertir icon.svg :" -ForegroundColor Yellow
  Write-Host "  - https://realfavicongenerator.net ou" -ForegroundColor Yellow
  Write-Host "  - magick icon.svg -resize 192x192 icon-192.png" -ForegroundColor Yellow
  Write-Host "  - magick icon.svg -resize 512x512 icon-512.png" -ForegroundColor Yellow
}catch{Write-Error "Erreur:$_";exit 1}
Write-Host @"
`n[INFO] Tache planifiee (5 min) :
  schtasks /Create /TN "HeatzyCollector" /TR "powershell.exe -NonInteractive -WindowStyle Hidden -File `"$CollectorPath`" -Email VOTRE_EMAIL -Password VOTRE_MDP" /SC MINUTE /MO 5 /F /RU SYSTEM
  Supprimer : schtasks /Delete /TN HeatzyCollector /F

[INFO] PWA — Installation sur Android :
  1. Servir les fichiers via un serveur local : python -m http.server 8080
  2. Ouvrir http://IP_DU_SERVEUR:8080/Heatzy-Dashboard.html dans Chrome Android
  3. Menu Chrome > Ajouter a l'ecran d'accueil
  OU : heberger sur votre DietPi avec nginx/lighttpd sur le LAN
"@ -ForegroundColor Cyan
try{Start-Process $HtmlPath;Write-Host "[OK] Dashboard ouvert." -ForegroundColor Green}catch{Write-Host "[WARN] Ouvrez: $HtmlPath" -ForegroundColor Yellow}
Write-Host "`n[DONE] v12 PWA pret.`n" -ForegroundColor Cyan