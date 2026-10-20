[CmdletBinding()]
param(
    [string]$ScreenshotRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScreenshotRoot)) {
    $ScreenshotRoot = $env:SMARTKEYS_SCREENSHOT_DIR
}
if ([string]::IsNullOrWhiteSpace($ScreenshotRoot)) {
    $ScreenshotRoot = Join-Path $repoRoot 'build/ui_screenshots'
}
$root = [System.IO.Path]::GetFullPath($ScreenshotRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Screenshot root does not exist: $root"
}

function Html([object]$Value) {
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Resolve-ScreenshotFile([string]$MetadataPath, [string]$FileName) {
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        throw "Missing fileName in metadata: $MetadataPath"
    }
    $normalized = $FileName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $candidate = Join-Path $root $normalized
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        # Accept older sidecars that stored only a filename relative to their folder.
        if ([System.IO.Path]::GetFileName($normalized) -eq $normalized) {
            $candidate = Join-Path (Split-Path -Parent $MetadataPath) $normalized
        }
    }
    $full = [System.IO.Path]::GetFullPath($candidate)
    $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Screenshot path escapes its root: $FileName"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "PNG referenced by metadata is missing: $full"
    }
    return $full
}

$sidecars = @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -Recurse | Sort-Object FullName)
if ($sidecars.Count -eq 0) {
    throw "No screenshot metadata found under $root"
}
$cards = [System.Collections.Generic.List[string]]::new()
foreach ($sidecar in $sidecars) {
    $item = Get-Content -LiteralPath $sidecar.FullName -Raw | ConvertFrom-Json
    foreach ($field in @('id', 'title', 'platform', 'orientation', 'width', 'height', 'fileName', 'notes')) {
        if (-not ($item.PSObject.Properties.Name -contains $field)) {
            throw "Screenshot metadata lacks '$field': $($sidecar.FullName)"
        }
    }
    $image = Resolve-ScreenshotFile $sidecar.FullName ([string]$item.fileName)
    $relative = [System.IO.Path]::GetRelativePath($root, $image).Replace('\', '/')
    $safeRelative = (($relative -split '/') | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
    $search = Html("$($item.id) $($item.title) $($item.platform) $($item.orientation) $($item.notes)")
    $cards.Add(@"
<article class="card" data-platform="$(Html $item.platform)" data-orientation="$(Html $item.orientation)" data-search="$search">
  <button class="preview" type="button" aria-label="Open $(Html $item.title)"><img loading="lazy" src="$safeRelative" alt="$(Html $item.title)"></button>
  <div class="details"><h2>$(Html $item.title)</h2><div class="badges"><span>$(Html $item.platform)</span><span>$(Html $item.orientation)</span><span>$(Html $item.width) × $(Html $item.height)</span></div><p>$(Html $item.notes)</p><a href="$safeRelative" target="_blank" rel="noopener">Open PNG</a></div>
</article>
"@)
}

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>LumiaKey UI screenshot gallery</title>
<style>
:root{color-scheme:dark;font:15px/1.5 system-ui,Segoe UI,sans-serif;background:#090d12;color:#e7eef7}*{box-sizing:border-box}body{margin:0}header{position:sticky;top:0;z-index:2;padding:20px clamp(16px,4vw,48px);background:#10151dee;border-bottom:1px solid #263341;backdrop-filter:blur(12px)}h1{margin:0 0 4px;font-size:clamp(22px,3vw,32px)}header p{margin:0;color:#aebdca}.filters{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}input,select{min-height:42px;padding:8px 12px;border:1px solid #354454;border-radius:9px;background:#0b1118;color:inherit}.filters input{flex:1;min-width:220px}#count{color:#aebdca;margin:12px 0 0}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,350px),1fr));gap:16px;padding:20px clamp(16px,4vw,48px) 48px}.card{overflow:hidden;border:1px solid #263341;border-radius:14px;background:#111923}.preview{display:block;width:100%;padding:0;border:0;background:#080b10;cursor:zoom-in}.preview img{display:block;width:100%;height:auto;max-height:620px;object-fit:contain}.details{padding:14px}.details h2{font-size:17px;margin:0 0 9px}.badges{display:flex;gap:6px;flex-wrap:wrap}.badges span{font-size:12px;padding:3px 8px;border-radius:999px;background:#1c2a37;color:#b8d9e8}.details p{color:#c0ccd7;min-height:2.5em}.details a{color:#67e8f9}dialog{max-width:min(96vw,1400px);max-height:95vh;padding:0;border:1px solid #405266;border-radius:12px;background:#090d12;color:inherit}dialog::backdrop{background:#000d}dialog img{display:block;max-width:92vw;max-height:88vh;object-fit:contain}dialog button{position:sticky;top:8px;float:right;margin:8px;padding:8px 12px;border:0;border-radius:8px;background:#243443;color:white;cursor:pointer}.empty{display:none;color:#aebdca;padding:20px}
</style>
</head>
<body>
<header><h1>LumiaKey UI screenshot gallery</h1><p>Flutter widget renders · deterministic test fixtures · no physical-device screenshot claim</p><div class="filters"><input id="search" type="search" placeholder="Search screens, notes, platform…" aria-label="Search screenshots"><select id="platform"><option value="">All platforms</option></select><select id="orientation"><option value="">All orientations</option></select></div><div id="count" aria-live="polite"></div></header>
<main id="gallery">
$($cards -join "`n")
</main><p class="empty" id="empty">No screenshots match these filters.</p>
<dialog id="viewer"><button type="button" id="close">Close</button><img alt="Expanded screenshot"></dialog>
<script>
const cards=[...document.querySelectorAll('.card')],search=document.querySelector('#search'),platform=document.querySelector('#platform'),orientation=document.querySelector('#orientation'),count=document.querySelector('#count'),empty=document.querySelector('#empty');
for(const [select,attr] of [[platform,'data-platform'],[orientation,'data-orientation']]){for(const value of [...new Set(cards.map(c=>c.getAttribute(attr)))].sort()){const option=document.createElement('option');option.value=value;option.textContent=value;select.append(option)}}
function update(){const q=search.value.toLowerCase();let shown=0;for(const c of cards){const visible=(!q||c.dataset.search.toLowerCase().includes(q))&&(!platform.value||c.dataset.platform===platform.value)&&(!orientation.value||c.dataset.orientation===orientation.value);c.hidden=!visible;if(visible)shown++}count.textContent=shown+' of '+cards.length+' screenshots';empty.style.display=shown?'none':'block'}
search.addEventListener('input',update);platform.addEventListener('change',update);orientation.addEventListener('change',update);update();
const viewer=document.querySelector('#viewer'),viewImage=viewer.querySelector('img');for(const button of document.querySelectorAll('.preview'))button.addEventListener('click',()=>{viewImage.src=button.querySelector('img').src;viewImage.alt=button.getAttribute('aria-label');viewer.showModal()});document.querySelector('#close').addEventListener('click',()=>viewer.close());viewer.addEventListener('click',e=>{if(e.target===viewer)viewer.close()});
</script>
</body></html>
"@
$indexPath = Join-Path $root 'index.html'
[System.IO.File]::WriteAllText($indexPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Output "Generated $indexPath with $($cards.Count) screenshots."
