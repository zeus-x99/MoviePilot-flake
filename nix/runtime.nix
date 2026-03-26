{
  symlinkJoin,
  version,
  backendPackage,
  pluginsPackage,
  resourcesPackage,
  frontendPackage,
}:

symlinkJoin {
  name = "moviepilot-runtime-${version}";
  paths = [
    backendPackage
    pluginsPackage
    resourcesPackage
    frontendPackage
  ];
}
