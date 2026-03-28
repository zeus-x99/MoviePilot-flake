{
  lib,
  stdenv,
  fetchYarnDeps,
  nodejs_20,
  yarnConfigHook,
  src,
  iconsSrc,
  version,
  yarnHash,
}:

stdenv.mkDerivation {
  pname = "moviepilot-frontend";
  inherit version src;

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = src + "/yarn.lock";
    hash = yarnHash;
  };

  nativeBuildInputs = [
    nodejs_20
    yarnConfigHook
  ];

  postPatch = ''
    mkdir -p public/plugin_icon
    cp -r ${iconsSrc}/icons/. public/plugin_icon/
  '';

  configurePhase = ''
    runHook preConfigure
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    yarn run build:icons
    yarn run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    frontend_dir="$out/share/moviepilot/frontend"
    mkdir -p "$frontend_dir"
    cp -r dist "$frontend_dir/"
    cat > "$frontend_dir/dist/service.js" <<'EOF'
    const path = require('node:path')
    const express = require('express')
    const proxy = require('express-http-proxy')

    const app = express()
    const port = process.env.NGINX_PORT || 3000
    const rootDir = __dirname
    const indexFile = path.join(rootDir, 'index.html')

    const proxyConfig = {
      URL: '127.0.0.1',
      PORT: process.env.PORT || 3001
    }

    const staleAssetRecoveryModule = `
    const reloadWithFreshCache = async () => {
      try {
        if ('caches' in globalThis) {
          const cacheNames = await caches.keys()
          await Promise.all(cacheNames.map((name) => caches.delete(name)))
        }
        if ('serviceWorker' in navigator) {
          const registrations = await navigator.serviceWorker.getRegistrations()
          await Promise.all(registrations.map((registration) => registration.unregister()))
        }
      } catch (error) {
        console.error('[MoviePilotNix] Failed to recover from stale frontend asset', error)
      } finally {
        const url = new URL(window.location.href)
        url.searchParams.set('_t', Date.now().toString())
        window.location.replace(url.pathname + url.search + url.hash)
      }
    }

    void reloadWithFreshCache()

    export {}
    `

    const sendIndex = (res) => {
      res.setHeader('Cache-Control', 'no-store')
      res.sendFile(indexFile)
    }

    app.use(express.static(rootDir, {
      index: false,
      setHeaders: (res, filePath) => {
        if (filePath === indexFile) {
          res.setHeader('Cache-Control', 'no-store')
          return
        }

        if (filePath.includes(path.sep + 'assets' + path.sep)) {
          res.setHeader('Cache-Control', 'public, max-age=31536000, immutable')
        }
      }
    }))

    app.use(
      '/api',
      proxy(proxyConfig.URL + ':' + proxyConfig.PORT, {
        proxyReqPathResolver: (req) => {
          return '/api' + req.url
        }
      })
    )

    app.use(
      '/cookiecloud',
      proxy(proxyConfig.URL + ':' + proxyConfig.PORT, {
        proxyReqPathResolver: (req) => {
          return '/cookiecloud' + req.url
        }
      })
    )

    app.get('/', (req, res) => {
      sendIndex(res)
    })

    app.get('*', (req, res) => {
      const requestPath = req.path
      const extension = path.extname(requestPath)

      if (!extension) {
        sendIndex(res)
        return
      }

      if (requestPath.startsWith('/assets/') && extension === '.js') {
        res.status(200)
        res.type('application/javascript; charset=UTF-8')
        res.send(staleAssetRecoveryModule)
        return
      }

      if (requestPath.startsWith('/assets/') && extension === '.css') {
        res.status(404)
        res.type('text/css; charset=UTF-8')
        res.send('/* missing asset */')
        return
      }

      res.status(404)
      res.type('text/plain; charset=UTF-8')
      res.send('Not Found')
    })

    app.listen(port, () => {
      console.log('Server is running on port ' + port)
    })
    EOF

    export SOURCE_NODE_MODULES="$PWD/node_modules"
    export DEST_NODE_MODULES="$frontend_dir/node_modules"

    ${nodejs_20}/bin/node <<'EOF'
    const fs = require('node:fs')
    const path = require('node:path')
    const { createRequire } = require('node:module')

    const sourceRoot = process.env.SOURCE_NODE_MODULES
    const destRoot = process.env.DEST_NODE_MODULES
    const runtimeRoots = ['express', 'express-http-proxy']
    const visited = new Set()

    fs.mkdirSync(destRoot, { recursive: true })

    const copyPackage = (pkgDir) => {
      const realPkgDir = fs.realpathSync(pkgDir)
      if (visited.has(realPkgDir)) {
        return
      }
      visited.add(realPkgDir)

      const manifestPath = path.join(realPkgDir, 'package.json')
      const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
      const relativeDir = path.relative(sourceRoot, realPkgDir)
      if (relativeDir.startsWith('..')) {
        throw new Error('Unexpected package outside node_modules: ' + realPkgDir)
      }

      const destDir = path.join(destRoot, relativeDir)
      fs.mkdirSync(path.dirname(destDir), { recursive: true })
      fs.cpSync(realPkgDir, destDir, { recursive: true, dereference: false })

      const localRequire = createRequire(manifestPath)
      const dependencyNames = new Set([
        ...Object.keys(manifest.dependencies ?? {}),
        ...Object.keys(manifest.optionalDependencies ?? {}),
      ])

      for (const dependencyName of Object.keys(manifest.peerDependencies ?? {})) {
        try {
          localRequire.resolve(dependencyName + '/package.json')
          dependencyNames.add(dependencyName)
        } catch {
        }
      }

      for (const dependencyName of dependencyNames) {
        const dependencyManifestPath = localRequire.resolve(dependencyName + '/package.json')
        copyPackage(path.dirname(dependencyManifestPath))
      }
    }

    for (const runtimeRoot of runtimeRoots) {
      const manifestPath = require.resolve(runtimeRoot + '/package.json', {
        paths: [sourceRoot],
      })
      copyPackage(path.dirname(manifestPath))
    }
    EOF
    runHook postInstall
  '';
}
