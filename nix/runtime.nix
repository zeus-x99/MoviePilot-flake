{
  runCommand,
  version,
  backendSrc,
  pluginsSrc,
  resourcesSrc,
  frontendPackage,
}:

runCommand "moviepilot-runtime-${version}" { } ''
  set -euo pipefail

  mkdir -p "$out/share/moviepilot/backend" "$out/share/moviepilot/frontend"

  cp -r ${backendSrc}/. "$out/share/moviepilot/backend/"
  chmod -R u+w "$out/share/moviepilot/backend"

  substituteInPlace "$out/share/moviepilot/backend/app/helper/plugin.py" \
    --replace-fail 'import json' $'import json\nimport os' \
    --replace-fail '        wheels_dir = requirements_file.parent / "wheels"' $'        if os.environ.get("MOVIEPILOT_NIX_PURE") == "1":\n            return False, "[Nix] 纯 Nix 模式已禁用运行时 pip 安装，请把插件依赖声明到 flake 中"\n\n        wheels_dir = requirements_file.parent / "wheels"'

  substituteInPlace "$out/share/moviepilot/backend/app/helper/resource.py" \
    --replace-fail 'import json' $'import json\nimport os' \
    --replace-fail '        if not settings.AUTO_UPDATE_RESOURCE:' $'        if os.environ.get("MOVIEPILOT_NIX_PURE") == "1":\n            return None\n        if not settings.AUTO_UPDATE_RESOURCE:'

  rm -rf "$out/share/moviepilot/backend/app/plugins"
  mkdir -p "$out/share/moviepilot/backend/app/plugins" "$out/share/moviepilot/backend/app/helper"
  cp ${backendSrc}/app/plugins/__init__.py "$out/share/moviepilot/backend/app/plugins/__init__.py"

  if [ -d ${pluginsSrc}/plugins.v2 ]; then
    cp -r ${pluginsSrc}/plugins.v2/. "$out/share/moviepilot/backend/app/plugins/"
  fi

  if [ -d ${pluginsSrc}/plugins ]; then
    for plugin_dir in ${pluginsSrc}/plugins/*; do
      [ -d "$plugin_dir" ] || continue
      plugin_name="$(basename "$plugin_dir")"
      if [ ! -e "$out/share/moviepilot/backend/app/plugins/$plugin_name" ]; then
        cp -r "$plugin_dir" "$out/share/moviepilot/backend/app/plugins/$plugin_name"
      fi
    done
  fi

  if [ -d ${resourcesSrc}/resources.v2 ]; then
    cp -r ${resourcesSrc}/resources.v2/. "$out/share/moviepilot/backend/app/helper/"
  fi

  if [ -d ${resourcesSrc}/resources ]; then
    for resource_file in ${resourcesSrc}/resources/*; do
      [ -e "$resource_file" ] || continue
      resource_name="$(basename "$resource_file")"
      if [ ! -e "$out/share/moviepilot/backend/app/helper/$resource_name" ]; then
        cp "$resource_file" "$out/share/moviepilot/backend/app/helper/$resource_name"
      fi
    done
  fi

  cp -r ${frontendPackage}/share/moviepilot/frontend/. "$out/share/moviepilot/frontend/"
''
