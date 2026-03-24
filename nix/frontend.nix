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
    mkdir -p "$out/share/moviepilot/frontend"
    cp -r dist "$out/share/moviepilot/frontend/"
    runHook postInstall
  '';
}
