{
  applyPatches,
  runCommand,
  version,
  backendSrc,
}:

let
  patchedBackendSrc = applyPatches {
    name = "moviepilot-backend-source-${version}";
    src = backendSrc;
    patches = [ ./patches/moviepilot-nix-pure.patch ];
  };
in
runCommand "moviepilot-backend-${version}" { } ''
  set -euo pipefail

  backend_dir="$out/share/moviepilot/backend"
  mkdir -p "$backend_dir"

  cp -r ${patchedBackendSrc}/. "$backend_dir/"
  chmod -R u+w "$backend_dir"

  rm -rf "$backend_dir/app/plugins"
  mkdir -p "$backend_dir/app/plugins"
  cp ${patchedBackendSrc}/app/plugins/__init__.py "$backend_dir/app/plugins/__init__.py"
''
