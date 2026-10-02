{{flutter_js}}
{{flutter_build_config}}

function showBootError() {
  document.getElementById('boot-status').textContent =
    'The workspace could not load. Check your connection and reload.';
  document.getElementById('boot-retry').hidden = false;
}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      document.getElementById('boot')?.remove();
    } catch (_) {
      showBootError();
    }
  }
}).catch(showBootError);
