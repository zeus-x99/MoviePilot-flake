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
