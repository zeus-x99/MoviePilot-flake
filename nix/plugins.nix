{
  runCommand,
  version,
  backendSrc,
  pluginsSrc,
}:

runCommand "moviepilot-plugins-${version}" { } ''
  set -euo pipefail

  plugins_dir="$out/share/moviepilot/plugins"
  manifest="$out/share/moviepilot/plugins-manifest"
  manifest_tmp="$TMPDIR/plugins-manifest"
  mkdir -p "$plugins_dir"
  : > "$manifest_tmp"

  cp ${backendSrc}/app/plugins/__init__.py "$plugins_dir/__init__.py"
  printf '%s\n' "__init__.py" >> "$manifest_tmp"

  if [ -d ${pluginsSrc}/plugins.v2 ]; then
    for plugin_entry in ${pluginsSrc}/plugins.v2/*; do
      [ -e "$plugin_entry" ] || continue
      plugin_name="$(basename "$plugin_entry")"
      cp -r "$plugin_entry" "$plugins_dir/$plugin_name"
      printf '%s\n' "$plugin_name" >> "$manifest_tmp"
    done
  fi

  if [ -d ${pluginsSrc}/plugins ]; then
    for plugin_dir in ${pluginsSrc}/plugins/*; do
      [ -d "$plugin_dir" ] || continue
      plugin_name="$(basename "$plugin_dir")"
      if [ ! -e "$plugins_dir/$plugin_name" ]; then
        cp -r "$plugin_dir" "$plugins_dir/$plugin_name"
      fi
      printf '%s\n' "$plugin_name" >> "$manifest_tmp"
    done
  fi

  sort -u "$manifest_tmp" > "$manifest"
''
