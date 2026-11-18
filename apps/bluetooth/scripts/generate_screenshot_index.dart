import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final rootArgument = _parseRoot(arguments);
  final repoRoot = File.fromUri(Platform.script).parent.parent;
  final requestedRoot =
      rootArgument ??
      Platform.environment['SMARTKEYS_SCREENSHOT_DIR'] ??
      '${repoRoot.path}${Platform.pathSeparator}build${Platform.pathSeparator}ui_screenshots';
  if (requestedRoot.trim().isEmpty) {
    throw ArgumentError('Screenshot root must not be empty.');
  }
  final requestedDirectory = Directory(requestedRoot).absolute;
  if (!await requestedDirectory.exists()) {
    throw FileSystemException(
      'Screenshot root does not exist',
      requestedDirectory.path,
    );
  }
  final canonicalRoot = await requestedDirectory.resolveSymbolicLinks();
  final root = Directory(canonicalRoot);
  final sidecars = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
      sidecars.add(entity);
    }
  }
  sidecars.sort((a, b) => a.path.compareTo(b.path));
  if (sidecars.isEmpty) {
    throw StateError('No screenshot metadata found under ${root.path}');
  }

  final cards = <String>[];
  for (final sidecar in sidecars) {
    final decoded = jsonDecode(await sidecar.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Screenshot metadata must be a JSON object: ${sidecar.path}',
      );
    }
    for (final field in const [
      'id',
      'title',
      'platform',
      'orientation',
      'width',
      'height',
      'fileName',
      'notes',
    ]) {
      if (!decoded.containsKey(field)) {
        throw FormatException(
          "Screenshot metadata lacks '$field': ${sidecar.path}",
        );
      }
    }
    final fileName = decoded['fileName'];
    if (fileName is! String || fileName.trim().isEmpty) {
      throw FormatException('Missing fileName in metadata: ${sidecar.path}');
    }
    final image = await _resolveImage(root, canonicalRoot, sidecar, fileName);
    final relative = _relativePath(root.path, image.path);
    final src = relative
        .split(Platform.pathSeparator)
        .map(Uri.encodeComponent)
        .join('/');
    String value(String key) => _escapeHtml(decoded[key].toString());
    final search = _escapeHtml(
      [
        'id',
        'title',
        'platform',
        'orientation',
        'notes',
      ].map((key) => decoded[key]).join(' '),
    );
    cards.add(
      '''<article class="card" data-platform="${value('platform')}" data-orientation="${value('orientation')}" data-search="$search">
  <button class="preview" type="button" aria-label="Open ${value('title')}"><img loading="lazy" src="$src" alt="${value('title')}"></button>
  <div class="details"><h2>${value('title')}</h2><div class="badges"><span>${value('platform')}</span><span>${value('orientation')}</span><span>${value('width')} × ${value('height')}</span></div><p>${value('notes')}</p><a href="$src" target="_blank" rel="noopener">Open PNG</a></div>
</article>''',
    );
  }

  final html =
      '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>LumiaKey current product screens</title>
<style>
:root{color-scheme:dark;font:15px/1.5 system-ui,sans-serif;background:#090d12;color:#e7eef7}*{box-sizing:border-box}body{margin:0}header{position:sticky;top:0;z-index:2;padding:20px clamp(16px,4vw,48px);background:#10151dee;border-bottom:1px solid #263341}h1{margin:0 0 4px;font-size:clamp(22px,3vw,32px)}header p{margin:0;color:#aebdca}.filters{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}input,select{min-height:42px;padding:8px 12px;border:1px solid #354454;border-radius:9px;background:#0b1118;color:inherit}.filters input{flex:1;min-width:220px}#count{color:#aebdca;margin:12px 0 0}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,350px),1fr));gap:16px;padding:20px clamp(16px,4vw,48px) 48px}.card{overflow:hidden;border:1px solid #263341;border-radius:14px;background:#111923}.preview{display:block;width:100%;padding:0;border:0;background:#080b10;cursor:zoom-in}.preview img{display:block;width:100%;height:auto;max-height:620px;object-fit:contain}.details{padding:14px}.details h2{font-size:17px;margin:0 0 9px}.badges{display:flex;gap:6px;flex-wrap:wrap}.badges span{font-size:12px;padding:3px 8px;border-radius:999px;background:#1c2a37;color:#b8d9e8}.details p{color:#c0ccd7;min-height:2.5em}.details a{color:#67e8f9}dialog{max-width:min(96vw,1400px);max-height:95vh;padding:0;border:1px solid #405266;border-radius:12px;background:#090d12;color:inherit}dialog::backdrop{background:#000d}dialog img{display:block;max-width:92vw;max-height:88vh;object-fit:contain}dialog button{position:sticky;top:8px;float:right;margin:8px;padding:8px 12px;border:0;border-radius:8px;background:#243443;color:white;cursor:pointer}.empty{display:none;color:#aebdca;padding:20px}
</style></head><body><header><h1>LumiaKey current product screens</h1><p>Full mobile · Desktop · Bluetooth Lite · Web. Capture method and validation limits are recorded on each screen.</p><div class="filters"><input id="search" type="search" placeholder="Search screens, notes, platform…" aria-label="Search screenshots"><select id="platform"><option value="">All platforms</option></select><select id="orientation"><option value="">All orientations</option></select></div><div id="count" aria-live="polite"></div></header>
<main id="gallery">${cards.join('\n')}</main><p class="empty" id="empty">No screenshots match these filters.</p><dialog id="viewer"><button type="button" id="close">Close</button><img alt="Expanded screenshot"></dialog>
<script>const cards=[...document.querySelectorAll('.card')],search=document.querySelector('#search'),platform=document.querySelector('#platform'),orientation=document.querySelector('#orientation'),count=document.querySelector('#count'),empty=document.querySelector('#empty');for(const [select,attr] of [[platform,'data-platform'],[orientation,'data-orientation']])for(const value of [...new Set(cards.map(c=>c.getAttribute(attr)))].sort()){const option=document.createElement('option');option.value=value;option.textContent=value;select.append(option)}function update(){const q=search.value.toLowerCase();let shown=0;for(const c of cards){const visible=(!q||c.dataset.search.toLowerCase().includes(q))&&(!platform.value||c.dataset.platform===platform.value)&&(!orientation.value||c.dataset.orientation===orientation.value);c.hidden=!visible;if(visible)shown++}count.textContent=shown+' of '+cards.length+' screenshots';empty.style.display=shown?'none':'block'}search.addEventListener('input',update);platform.addEventListener('change',update);orientation.addEventListener('change',update);update();const viewer=document.querySelector('#viewer'),viewImage=viewer.querySelector('img');for(const button of document.querySelectorAll('.preview'))button.addEventListener('click',()=>{viewImage.src=button.querySelector('img').src;viewImage.alt=button.getAttribute('aria-label');viewer.showModal()});document.querySelector('#close').addEventListener('click',()=>viewer.close());viewer.addEventListener('click',e=>{if(e.target===viewer)viewer.close()});</script></body></html>''';
  final output = File('${root.path}${Platform.pathSeparator}index.html');
  await output.writeAsString(html, encoding: utf8);
  stdout.writeln('Generated ${output.path} with ${cards.length} screenshots.');
}

String? _parseRoot(List<String> arguments) {
  if (arguments.isEmpty) return null;
  if (arguments.length == 1 && !arguments.single.startsWith('--')) {
    return arguments.single;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    if (arguments[1].trim().isEmpty) {
      throw ArgumentError('Screenshot root must not be empty.');
    }
    return arguments[1];
  }
  throw ArgumentError(
    'Usage: dart run scripts/generate_screenshot_index.dart [--root <directory>]',
  );
}

Future<File> _resolveImage(
  Directory root,
  String canonicalRoot,
  File sidecar,
  String fileName,
) async {
  final normalized = fileName
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator);
  var candidate = File('${root.path}${Platform.pathSeparator}$normalized');
  if (!await candidate.exists() &&
      !normalized.contains(Platform.pathSeparator)) {
    candidate = File(
      '${sidecar.parent.path}${Platform.pathSeparator}$normalized',
    );
  }
  if (!await candidate.exists()) {
    throw FileSystemException(
      'PNG referenced by metadata is missing',
      candidate.path,
    );
  }
  final resolved = await candidate.resolveSymbolicLinks();
  final prefix = canonicalRoot.endsWith(Platform.pathSeparator)
      ? canonicalRoot
      : '$canonicalRoot${Platform.pathSeparator}';
  if (resolved != canonicalRoot && !resolved.startsWith(prefix)) {
    throw ArgumentError('Screenshot path escapes its root: $fileName');
  }
  return File(resolved);
}

String _relativePath(String root, String file) {
  final rootParts = root.split(Platform.pathSeparator);
  final fileParts = file.split(Platform.pathSeparator);
  var common = 0;
  while (common < rootParts.length &&
      common < fileParts.length &&
      rootParts[common] == fileParts[common]) {
    common++;
  }
  return [
    ...List.filled(rootParts.length - common, '..'),
    ...fileParts.skip(common),
  ].join(Platform.pathSeparator);
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
