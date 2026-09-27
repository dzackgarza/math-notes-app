{{flutter_js}}
{{flutter_build_config}}

import('./host.js').then(() => _flutter.loader.load({
  config: { canvasKitBaseUrl: './canvaskit/' },
}));
