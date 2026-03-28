{
  pkgs,
  module,
  frontend ? true,
  exerciseOwnershipRepair ? false,
}:

let
  fakePlaywrightBrowsers = pkgs.runCommand "moviepilot-playwright-test-browsers" { } ''
    mkdir -p "$out/chromium"
  '';
  frontendConfig =
    if frontend then
      { }
    else
      {
        frontend.enable = false;
      };
in
pkgs.testers.runNixOSTest {
  name = if frontend then "moviepilot" else "moviepilot-no-frontend";

  nodes.machine = { pkgs, lib, ... }: {
    imports = [ module ];

    environment.systemPackages = [ pkgs.curl ];
    environment.etc."moviepilot.env".text = ''
      TEST_ONLY_SECRET=backend-only
    '';

    virtualisation.diskSize = 4096;

    services.moviepilot = {
      enable = true;
      environmentFile = "/etc/moviepilot.env";
      playwrightBrowsersPath = fakePlaywrightBrowsers;
      settings = {
        SUPERUSER = "admin";
        SUPERUSER_PASSWORD = "test-password";
        API_TOKEN = "integration-test-token";
        DB_TYPE = "sqlite";
        TMDB_API_KEY = "test-tmdb-api-key";
      };
    }
    // frontendConfig;

    system.stateVersion = "25.05";
  };

  testScript = ''
    start_all()
    check = machine.succeed

    machine.wait_for_unit("moviepilot-backend.service")
    machine.wait_for_open_port(3001)

    ${if frontend then ''
      machine.wait_for_unit("moviepilot-frontend.service")
      machine.wait_for_open_port(3000)

      machine.wait_until_succeeds(
          "curl --fail --silent http://127.0.0.1:3000/ | grep -q '<title>MoviePilot</title>'"
      )
    '' else ''
      machine.wait_until_succeeds(
          "systemctl show -p LoadState --value moviepilot-frontend.service | grep -qx 'not-found'"
      )
      machine.fail("curl --max-time 2 --fail --silent http://127.0.0.1:3000/")
    ''}
    machine.wait_until_succeeds(
        "curl --fail --silent 'http://127.0.0.1:3001/api/v1/system/global?token=moviepilot' | grep -q '\"success\":true'"
    )
    machine.wait_until_succeeds(
        "curl --fail --silent 'http://127.0.0.1:3001/api/v1/system/global?token=moviepilot' | grep -q '\"BACKEND_VERSION\"'"
    )
    check(
        "test -f /var/lib/moviepilot/runtime/backend/app/main.py"
    )
    check(
        "systemctl show -p User --value moviepilot-prepare.service | grep -qx moviepilot"
    )
    check(
        "systemctl show -p PrivateIPC --value moviepilot-prepare.service | grep -qx yes"
    )
    check(
        "systemctl show -p KeyringMode --value moviepilot-prepare.service | grep -qx private"
    )
    check(
        "systemctl show -p MemoryDenyWriteExecute --value moviepilot-prepare.service | grep -qx yes"
    )
    check(
        "systemctl show -p ProtectHome --value moviepilot-prepare.service | grep -qx yes"
    )
    check(
        "systemctl show -p PrivateDevices --value moviepilot-prepare.service | grep -qx yes"
    )
    check(
        "systemctl show -p ProcSubset --value moviepilot-prepare.service | grep -qx pid"
    )
    check(
        "systemctl show -p ProtectProc --value moviepilot-prepare.service | grep -qx invisible"
    )
    check(
        "systemctl show -p RemoveIPC --value moviepilot-prepare.service | grep -qx yes"
    )
    check(
        "systemctl show -p ReadWritePaths --value moviepilot-prepare.service | tr ' ' '\\n' | grep -Fqx '/var/lib/moviepilot/config'"
    )
    check(
        "systemctl show -p ReadWritePaths --value moviepilot-prepare.service | tr ' ' '\\n' | grep -Fqx '/var/lib/moviepilot/runtime'"
    )
    check(
        "systemctl show -p ReadWritePaths --value moviepilot-backend.service | tr ' ' '\\n' | grep -Fqx '/var/lib/moviepilot/config'"
    )
    check(
        "test \"$(systemctl show -p ReadWritePaths --value moviepilot-backend.service)\" = '/var/lib/moviepilot/config'"
    )
    check(
        "systemctl show -p PrivateIPC --value moviepilot-backend.service | grep -qx yes"
    )
    check(
        "systemctl show -p KeyringMode --value moviepilot-backend.service | grep -qx private"
    )
    check(
        "systemctl show -p PrivateDevices --value moviepilot-backend.service | grep -qx yes"
    )
    check(
        "systemctl show -p ProcSubset --value moviepilot-backend.service | grep -qx all"
    )
    check(
        "systemctl show -p ProtectHome --value moviepilot-backend.service | grep -qx yes"
    )
    check(
        "systemctl show -p ProtectProc --value moviepilot-backend.service | grep -qx invisible"
    )
    check(
        "systemctl show -p RemoveIPC --value moviepilot-backend.service | grep -qx yes"
    )
    check(
        "systemctl show -p RestrictAddressFamilies --value moviepilot-backend.service | tr ' ' '\\n' | grep -Fqx 'AF_INET'"
    )
    check(
        "systemctl show -p RestrictAddressFamilies --value moviepilot-backend.service | tr ' ' '\\n' | grep -Fqx 'AF_INET6'"
    )
    check(
        "systemctl show -p RestrictAddressFamilies --value moviepilot-backend.service | tr ' ' '\\n' | grep -Fqx 'AF_UNIX'"
    )
    ${if frontend then ''
      check(
          "systemctl show -p Environment --value moviepilot-backend.service | tr ' ' '\\n' | grep -qx 'NGINX_PORT=3000'"
      )
    '' else ''
      check(
          "systemctl show -p Environment --value moviepilot-backend.service | tr ' ' '\\n' | grep -qx 'NGINX_PORT=3001'"
      )
    ''}
    check(
        "test -z \"$(systemctl show -p ReadWritePaths --value moviepilot-frontend.service)\""
    )
    check(
        "systemctl show -p EnvironmentFiles --value moviepilot-backend.service | grep -Fq '/etc/moviepilot.env'"
    )
    check(
        "test -z \"$(systemctl show -p EnvironmentFiles --value moviepilot-prepare.service)\""
    )
    ${if frontend then ''
      check(
          "test -z \"$(systemctl show -p EnvironmentFiles --value moviepilot-frontend.service)\""
      )
      check(
          "systemctl show -p Environment --value moviepilot-frontend.service | tr ' ' '\\n' | grep -qx 'PORT=3001'"
      )
      check(
          "systemctl show -p Environment --value moviepilot-frontend.service | tr ' ' '\\n' | grep -qx 'NGINX_PORT=3000'"
      )
      check(
          "systemctl show -p PrivateIPC --value moviepilot-frontend.service | grep -qx yes"
      )
      check(
          "systemctl show -p KeyringMode --value moviepilot-frontend.service | grep -qx private"
      )
      check(
          "systemctl show -p PrivateDevices --value moviepilot-frontend.service | grep -qx yes"
      )
      check(
          "systemctl show -p ProcSubset --value moviepilot-frontend.service | grep -qx pid"
      )
      check(
          "systemctl show -p ProtectHome --value moviepilot-frontend.service | grep -qx yes"
      )
      check(
          "systemctl show -p ProtectProc --value moviepilot-frontend.service | grep -qx invisible"
      )
      check(
          "systemctl show -p RemoveIPC --value moviepilot-frontend.service | grep -qx yes"
      )
      check(
          "systemctl show -p RestrictAddressFamilies --value moviepilot-frontend.service | tr ' ' '\\n' | grep -Fqx 'AF_INET'"
      )
      check(
          "systemctl show -p RestrictAddressFamilies --value moviepilot-frontend.service | tr ' ' '\\n' | grep -Fqx 'AF_INET6'"
      )
      check(
          "systemctl show -p RestrictAddressFamilies --value moviepilot-frontend.service | tr ' ' '\\n' | grep -Fqx 'AF_UNIX'"
      )
      check(
          "! systemctl show -p Environment --value moviepilot-frontend.service | tr ' ' '\\n' | grep -q '^SUPERUSER='"
      )
    '' else ''
      check(
          "test ! -e /var/lib/moviepilot/runtime/frontend"
      )
    ''}
    check(
        "test -L /var/lib/moviepilot/runtime/backend/app/plugins"
    )
    check(
        "test \"$(readlink /var/lib/moviepilot/runtime/backend/app/plugins)\" = '/var/lib/moviepilot/config/plugins'"
    )
    check(
        "test -f /var/lib/moviepilot/config/plugins/__init__.py"
    )
    check(
        "test -f /var/lib/moviepilot/runtime/.backend-package"
    )
    check(
        "test -f /var/lib/moviepilot/config/.plugins-package"
    )
    check(
        "test -f /var/lib/moviepilot/config/.resources-package"
    )
    check(
        "test -f /var/lib/moviepilot/config/.packaged-resources"
    )
    ${if frontend then ''
      check(
          "test -L /var/lib/moviepilot/runtime/frontend"
      )
      check(
          "test ! -e /var/lib/moviepilot/runtime/frontend/node_modules/vite"
      )
      check(
          "test -f /var/lib/moviepilot/runtime/frontend/dist/service.js"
      )
      check(
          "test -f /var/lib/moviepilot/runtime/frontend/node_modules/express/package.json"
      )
    '' else ""}
    check(
        "test -f /var/lib/moviepilot/runtime/backend/app/helper/user.sites.v2.bin"
    )
    ${if exerciseOwnershipRepair then ''
      ${if frontend then ''
        machine.succeed("systemctl stop moviepilot-frontend.service")
      '' else ""}
      machine.succeed("systemctl stop moviepilot-backend.service")
      machine.succeed("install -d -o root -g root -m 0700 /var/lib/moviepilot/config/root-owned-dir")
      machine.succeed("install -o root -g root -m 0600 /dev/null /var/lib/moviepilot/config/root-owned-dir/file")
      machine.succeed("install -d -o root -g root -m 0700 /var/lib/moviepilot/runtime/backend/root-owned-dir")
      machine.succeed("install -o root -g root -m 0600 /dev/null /var/lib/moviepilot/runtime/backend/root-owned-dir/file")
      machine.succeed("chown root:root /var/lib/moviepilot /var/lib/moviepilot/config /var/lib/moviepilot/runtime /var/lib/moviepilot/runtime/backend")
      machine.succeed("find /var/lib/moviepilot/config -maxdepth 1 -type f -exec chown root:root {} +")
      machine.succeed("find /var/lib/moviepilot/runtime -maxdepth 1 -type f -exec chown root:root {} +")
      machine.succeed("systemd-tmpfiles --create --prefix /var/lib/moviepilot")
      check(
          "stat -c '%U:%G' /var/lib/moviepilot | grep -qx 'moviepilot:moviepilot'"
      )
      check(
          "stat -c '%U:%G' /var/lib/moviepilot/config | grep -qx 'moviepilot:moviepilot'"
      )
      check(
          "stat -c '%U:%G' /var/lib/moviepilot/runtime | grep -qx 'moviepilot:moviepilot'"
      )
      check(
          "stat -c '%U:%G' /var/lib/moviepilot/config/root-owned-dir/file | grep -qx 'moviepilot:moviepilot'"
      )
      check(
          "stat -c '%U:%G' /var/lib/moviepilot/runtime/backend/root-owned-dir/file | grep -qx 'moviepilot:moviepilot'"
      )
      machine.succeed("systemctl start moviepilot-backend.service")
      machine.wait_for_unit("moviepilot-backend.service")
      machine.wait_for_open_port(3001)
      machine.wait_until_succeeds(
          "curl --fail --silent 'http://127.0.0.1:3001/api/v1/system/global?token=moviepilot' | grep -q '\"success\":true'"
      )
      ${if frontend then ''
        machine.succeed("systemctl start moviepilot-frontend.service")
        machine.wait_for_unit("moviepilot-frontend.service")
        machine.wait_for_open_port(3000)
        machine.wait_until_succeeds(
            "curl --fail --silent http://127.0.0.1:3000/ | grep -q '<title>MoviePilot</title>'"
        )
      '' else ""}
    '' else ""}
  '';
}
