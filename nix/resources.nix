{
  runCommand,
  version,
  resourcesSrc,
}:

runCommand "moviepilot-resources-${version}" { } ''
  set -euo pipefail

  resources_dir="$out/share/moviepilot/resources"
  manifest="$out/share/moviepilot/resources-manifest"
  manifest_tmp="$TMPDIR/resources-manifest"
  mkdir -p "$resources_dir"
  : > "$manifest_tmp"

  if [ -d ${resourcesSrc}/resources.v2 ]; then
    for resource_entry in ${resourcesSrc}/resources.v2/*; do
      [ -e "$resource_entry" ] || continue
      resource_name="$(basename "$resource_entry")"
      cp -r "$resource_entry" "$resources_dir/$resource_name"
      printf '%s\n' "$resource_name" >> "$manifest_tmp"
    done
  fi

  if [ -d ${resourcesSrc}/resources ]; then
    for resource_entry in ${resourcesSrc}/resources/*; do
      [ -e "$resource_entry" ] || continue
      resource_name="$(basename "$resource_entry")"
      if [ ! -e "$resources_dir/$resource_name" ]; then
        cp -r "$resource_entry" "$resources_dir/$resource_name"
      fi
      printf '%s\n' "$resource_name" >> "$manifest_tmp"
    done
  fi

  sort -u "$manifest_tmp" > "$manifest"
''
