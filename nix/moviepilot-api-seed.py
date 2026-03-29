#!/usr/bin/env python3

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


NO_BODY = object()


class MoviePilotApiError(RuntimeError):
    pass


def read_json_stdin():
    data = sys.stdin.read().strip()
    if not data:
        return None
    return json.loads(data)


def normalize_string(value):
    if value in (None, ""):
        return None
    return value


def ensure_dict(value, context):
    if not isinstance(value, dict):
        raise MoviePilotApiError(f"{context} 必须是属性集")
    return value


def ensure_list(value, context):
    if not isinstance(value, list):
        raise MoviePilotApiError(f"{context} 必须是列表")
    return value


def normalize_url(url):
    parsed = urllib.parse.urlsplit(url)
    if not parsed.scheme or not parsed.netloc:
        raise MoviePilotApiError(f"无效的站点地址: {url}")
    return f"{parsed.scheme}://{parsed.netloc}/"


def url_domain(url):
    return urllib.parse.urlsplit(url).netloc


def quote_path(value):
    return urllib.parse.quote(str(value), safe="")


class MoviePilotApi:
    def __init__(self):
        base_url = os.environ.get("MOVIEPILOT_API_BASE_URL")
        api_token = os.environ.get("API_TOKEN")
        startup_timeout = int(os.environ.get("MOVIEPILOT_API_STARTUP_TIMEOUT", "180"))
        request_timeout = int(os.environ.get("MOVIEPILOT_API_TIMEOUT", "30"))

        if not base_url:
            raise MoviePilotApiError("缺少 MOVIEPILOT_API_BASE_URL")
        if not api_token:
            raise MoviePilotApiError("缺少 API_TOKEN，API seed 需要 API_TOKEN")

        self.base_url = base_url.rstrip("/")
        self.api_token = api_token
        self.startup_timeout = startup_timeout
        self.request_timeout = request_timeout
        self.ready = False

    def wait_until_ready(self):
        deadline = time.monotonic() + self.startup_timeout
        last_error = None

        while time.monotonic() < deadline:
            try:
                self.request_json("GET", "/user/current", require_ready=False)
                self.ready = True
                return
            except Exception as exc:  # noqa: BLE001
                last_error = exc
                time.sleep(2)

        raise MoviePilotApiError(
            f"等待 MoviePilot API 就绪超时，最后错误: {last_error}"
        )

    def password_authenticates(self, username, password):
        form = urllib.parse.urlencode(
            {
                "username": username,
                "password": password,
            }
        ).encode()

        request = urllib.request.Request(
            f"{self.base_url}/login/access-token",
            data=form,
            method="POST",
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
            },
        )

        try:
            with urllib.request.urlopen(request, timeout=self.request_timeout):
                return True
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            if exc.code == 401:
                return exc.headers.get("X-MFA-Required") == "true"
            raise MoviePilotApiError(
                f"校验 MoviePilot 管理员密码失败: HTTP {exc.code}: {body}"
            ) from exc
        except urllib.error.URLError as exc:
            raise MoviePilotApiError(f"连接 MoviePilot API 失败: {exc}") from exc

    def request_json(self, method, path, payload=NO_BODY, query=None, require_ready=True):
        if require_ready and not self.ready:
            self.wait_until_ready()

        url = f"{self.base_url}{path}"
        if query:
            query_items = {
                key: value
                for key, value in query.items()
                if value is not None
            }
            if query_items:
                url = f"{url}?{urllib.parse.urlencode(query_items, doseq=True)}"

        data = None
        headers = {
            "Accept": "application/json",
            "X-API-KEY": self.api_token,
        }

        if payload is not NO_BODY:
            data = json.dumps(payload, ensure_ascii=False).encode()
            headers["Content-Type"] = "application/json"

        request = urllib.request.Request(url, data=data, method=method, headers=headers)

        try:
            with urllib.request.urlopen(request, timeout=self.request_timeout) as response:
                raw = response.read().decode()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            raise MoviePilotApiError(
                f"请求 {method} {path} 失败: HTTP {exc.code}: {body}"
            ) from exc
        except urllib.error.URLError as exc:
            raise MoviePilotApiError(f"请求 {method} {path} 失败: {exc}") from exc

        if not raw:
            return None
        return json.loads(raw)


def get_user_by_name(users, username):
    for user in users:
        if isinstance(user, dict) and user.get("name") == username:
            return user
    return None


def expect_response_success(result, context):
    if not isinstance(result, dict):
        raise MoviePilotApiError(f"{context} 返回格式异常: {result}")
    if result.get("success") is False:
        raise MoviePilotApiError(f"{context}失败: {result.get('message')}")
    return result


def resolve_nested_config_env(entries, context):
    resolved = []
    for entry in ensure_list(entries, context):
        current = dict(ensure_dict(entry, context))
        config_from_environment = current.pop("configFromEnvironment", None) or {}
        if config_from_environment:
            config = dict(current.get("config") or {})
            for key, env_name in ensure_dict(
                config_from_environment,
                f"{context}.configFromEnvironment",
            ).items():
                if env_name not in os.environ:
                    name = current.get("name") or current.get("type") or "unknown"
                    raise MoviePilotApiError(
                        f"缺少环境变量 {env_name}，用于 {name}.{key}"
                    )
                config[key] = os.environ[env_name]
            current["config"] = config
        resolved.append(current)
    return resolved


def handle_system_setting(api, payload, key, updated_message, unchanged_message, *, empty_as_null=False, resolve_config_env=False):
    desired = payload
    if resolve_config_env:
        desired = resolve_nested_config_env(desired, key)
    if empty_as_null and desired in ([], {}):
        desired = None

    current_response = api.request_json("GET", f"/system/setting/{quote_path(key)}")
    current_value = (
        current_response.get("data", {}).get("value")
        if isinstance(current_response, dict)
        else None
    )

    if current_value != desired:
        expect_response_success(
            api.request_json(
                "POST",
                f"/system/setting/{quote_path(key)}",
                payload=desired,
            ),
            f"更新系统设置 {key}",
        )
        print(updated_message)
    else:
        print(unchanged_message)


def handle_site_auth(api, payload):
    desired = dict(ensure_dict(payload, "siteAuth"))
    params = dict(desired.get("params") or {})
    params_from_environment = desired.pop("paramsFromEnvironment", None) or {}

    for key, env_name in ensure_dict(
        params_from_environment,
        "siteAuth.paramsFromEnvironment",
    ).items():
        if env_name not in os.environ:
            raise MoviePilotApiError(
                f"缺少环境变量 {env_name}，用于 siteAuth.params.{key}"
            )
        params[key] = os.environ[env_name]

    desired["params"] = params
    current_response = api.request_json(
        "GET",
        "/system/setting/UserSiteAuthParams",
    )
    current_value = (
        current_response.get("data", {}).get("value")
        if isinstance(current_response, dict)
        else None
    )

    if current_value != desired:
        expect_response_success(
            api.request_json("POST", "/site/auth", payload=desired),
            "同步站点认证",
        )
        print("MoviePilot site auth config updated")
    else:
        print("MoviePilot site auth config already up to date")


def resolve_site_entry(entry):
    current = dict(ensure_dict(entry, "site"))
    from_environment = current.pop("fromEnvironment", None) or {}

    for key, env_name in ensure_dict(from_environment, "site.fromEnvironment").items():
        if env_name not in os.environ:
            raise MoviePilotApiError(
                f"缺少环境变量 {env_name}，用于站点 {current.get('domain', 'unknown')}.{key}"
            )
        current[key] = os.environ[env_name]

    domain = current.get("domain")
    if not domain:
        raise MoviePilotApiError("MoviePilot site entry requires domain")

    current["url"] = normalize_url(current.get("url") or f"https://{domain}/")

    if current.get("name") is None:
        current["name"] = domain
    if current.get("public") is None:
        current["public"] = 0

    managed_fields = [
        "name",
        "domain",
        "url",
        "pri",
        "rss",
        "cookie",
        "ua",
        "apikey",
        "token",
        "proxy",
        "filter",
        "render",
        "public",
        "timeout",
        "limit_interval",
        "limit_count",
        "limit_seconds",
        "is_active",
        "downloader",
    ]
    return {
        key: current.get(key)
        for key in managed_fields
        if key in current and current.get(key) is not None
    }


def normalize_site_value(value):
    if value == "":
        return None
    return value


def handle_sites(api, payload):
    desired_sites = [resolve_site_entry(entry) for entry in ensure_list(payload, "sites")]
    current_sites = api.request_json("GET", "/site/") or []
    current_by_domain = {
        site.get("domain"): site
        for site in current_sites
        if isinstance(site, dict) and site.get("domain")
    }
    managed_fields = [
        "name",
        "domain",
        "url",
        "pri",
        "rss",
        "cookie",
        "ua",
        "apikey",
        "token",
        "proxy",
        "filter",
        "render",
        "public",
        "timeout",
        "limit_interval",
        "limit_count",
        "limit_seconds",
        "is_active",
        "downloader",
    ]
    created = 0
    updated = 0

    for desired in desired_sites:
        domain = desired["domain"]
        existing = current_by_domain.get(domain)

        if not existing:
            expect_response_success(
                api.request_json("POST", "/site/", payload=desired),
                f"创建站点 {domain}",
            )
            existing = api.request_json("GET", f"/site/domain/{quote_path(domain)}")
            current_by_domain[domain] = existing
            created += 1

        current_managed = {
            key: normalize_site_value(existing.get(key))
            for key in managed_fields
        }
        desired_managed = {
            key: normalize_site_value(desired.get(key))
            for key in managed_fields
        }

        if current_managed != desired_managed:
            merged = dict(existing)
            merged.update(desired)
            expect_response_success(
                api.request_json("PUT", "/site/", payload=merged),
                f"更新站点 {domain}",
            )
            updated += 1

    if created or updated:
        print("MoviePilot sites config updated")
    else:
        print("MoviePilot sites config already up to date")


def handle_site_selection(api, payload, key, updated_message, unchanged_message):
    desired_domains = ensure_list(payload, key)
    current_sites = api.request_json("GET", "/site/") or []
    site_ids = {}
    for site in current_sites:
        if isinstance(site, dict) and site.get("domain") and site.get("id") is not None:
            site_ids[site["domain"]] = site["id"]

    resolved_ids = []
    missing = []
    for domain in desired_domains:
        site_id = site_ids.get(domain)
        if site_id is None:
            missing.append(domain)
        else:
            resolved_ids.append(site_id)

    if missing:
        raise MoviePilotApiError(
            f"{key} 引用了不存在的站点域名: {', '.join(missing)}"
        )

    handle_system_setting(
        api,
        resolved_ids,
        key,
        updated_message,
        unchanged_message,
    )


def subscription_identity(entry):
    season = entry.get("season")
    tmdbid = entry.get("tmdbid")
    doubanid = normalize_string(entry.get("doubanid"))
    bangumiid = entry.get("bangumiid")
    mediaid = normalize_string(entry.get("mediaid"))

    if tmdbid is not None:
        return {"tmdbid": int(tmdbid), "season": season}
    if doubanid:
        return {"doubanid": doubanid, "season": season}
    if bangumiid is not None:
        return {"bangumiid": int(bangumiid), "season": season}
    if mediaid:
        return {"mediaid": mediaid, "season": season}
    raise MoviePilotApiError(
        f"MoviePilot subscription {entry.get('name', 'unknown')} 需要 tmdbid/doubanid/bangumiid/mediaid 之一"
    )


def subscription_identity_key(entry):
    return json.dumps(subscription_identity(entry), sort_keys=True, ensure_ascii=False)


def normalize_subscription_payload(payload, keys):
    normalized = {}
    for key in keys:
        value = payload.get(key)
        if key in ("sites", "filter_groups"):
            normalized[key] = sorted(value or [])
        elif isinstance(value, str) and value == "":
            normalized[key] = None
        else:
            normalized[key] = value
    return normalized


def resolve_subscription_entry(entry, site_id_map):
    current = dict(ensure_dict(entry, "subscription"))
    site_domains = current.get("sites") or []
    site_ids = []
    missing_domains = []

    for domain in site_domains:
        site_id = site_id_map.get(domain)
        if site_id is None:
            missing_domains.append(domain)
        else:
            site_ids.append(site_id)

    if missing_domains:
        raise MoviePilotApiError(
            f"订阅 {current.get('name', 'unknown')} 引用了不存在的站点域名: {', '.join(missing_domains)}"
        )

    payload = {}
    for key, value in current.items():
        if key == "sites":
            payload["sites"] = site_ids
        elif key == "filter_groups":
            payload["filter_groups"] = value or []
        elif key in (
            "year",
            "keyword",
            "doubanid",
            "mediaid",
            "filter",
            "include",
            "exclude",
            "quality",
            "resolution",
            "effect",
            "downloader",
            "save_path",
            "custom_words",
            "media_category",
            "episode_group",
            "username",
        ):
            payload[key] = normalize_string(value)
        else:
            payload[key] = value

    if "username" not in payload:
        payload["username"] = "admin"
    return payload


def handle_subscriptions(api, payload):
    desired_entries = ensure_list(payload, "subscriptions")
    managed_file = Path(os.environ["MOVIEPILOT_MANAGED_SUBSCRIPTIONS_FILE"])
    managed_file.parent.mkdir(parents=True, exist_ok=True)

    current_sites = api.request_json("GET", "/site/") or []
    site_id_map = {
        site["domain"]: site["id"]
        for site in current_sites
        if isinstance(site, dict) and site.get("domain") and site.get("id") is not None
    }

    current_subscriptions = api.request_json("GET", "/subscribe/") or []
    current_by_identity = {}
    for subscription in current_subscriptions:
        if not isinstance(subscription, dict):
            continue
        try:
            current_by_identity[subscription_identity_key(subscription)] = subscription
        except MoviePilotApiError:
            continue

    previous_identities = []
    if managed_file.exists():
        previous_identities = json.loads(managed_file.read_text() or "[]")

    desired_identities = []
    desired_keys = set()
    created = 0
    updated = 0
    deleted = 0

    for entry in desired_entries:
        identity = subscription_identity(entry)
        key = json.dumps(identity, sort_keys=True, ensure_ascii=False)
        if key in desired_keys:
            raise MoviePilotApiError(f"重复的订阅标识: {key}")
        desired_keys.add(key)
        desired_identities.append(identity)

        desired_payload = resolve_subscription_entry(entry, site_id_map)
        existing = current_by_identity.get(key)

        if not existing:
            response = expect_response_success(
                api.request_json("POST", "/subscribe/", payload=desired_payload),
                f"创建订阅 {desired_payload.get('name', key)}",
            )
            subscription_id = response.get("data", {}).get("id")
            if not subscription_id:
                raise MoviePilotApiError(
                    f"创建订阅 {desired_payload.get('name', key)} 后未返回 id"
                )
            existing = api.request_json(
                "GET",
                f"/subscribe/{quote_path(subscription_id)}",
            )
            current_by_identity[key] = existing
            created += 1

        comparison_keys = list(desired_payload.keys())
        current_managed = normalize_subscription_payload(existing, comparison_keys)
        desired_managed = normalize_subscription_payload(desired_payload, comparison_keys)

        if current_managed != desired_managed:
            merged = dict(existing)
            merged.update(desired_payload)
            expect_response_success(
                api.request_json("PUT", "/subscribe/", payload=merged),
                f"更新订阅 {desired_payload.get('name', key)}",
            )
            updated += 1

    previous_keys = {
        json.dumps(identity, sort_keys=True, ensure_ascii=False): identity
        for identity in previous_identities
    }
    for key in sorted(set(previous_keys) - desired_keys):
        existing = current_by_identity.get(key)
        if not existing or existing.get("id") is None:
            continue
        expect_response_success(
            api.request_json(
                "DELETE",
                f"/subscribe/{quote_path(existing['id'])}",
            ),
            f"删除订阅 {existing.get('name', key)}",
        )
        deleted += 1

    current_managed = json.dumps(
        desired_identities,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n"
    previous_managed = managed_file.read_text() if managed_file.exists() else ""
    if current_managed != previous_managed:
        managed_file.write_text(current_managed)

    if created or updated or deleted or current_managed != previous_managed:
        print("MoviePilot subscriptions updated")
    else:
        print("MoviePilot subscriptions already up to date")


def handle_installed_plugins(api, payload):
    desired = []
    for plugin_id in ensure_list(payload, "installedPlugins"):
        if plugin_id not in desired:
            desired.append(plugin_id)

    current = api.request_json("GET", "/plugin/installed") or []
    changed = False

    for plugin_id in desired:
        if plugin_id in current:
            continue
        expect_response_success(
            api.request_json("GET", f"/plugin/install/{quote_path(plugin_id)}"),
            f"安装插件 {plugin_id}",
        )
        changed = True

    for plugin_id in current:
        if plugin_id in desired:
            continue
        expect_response_success(
            api.request_json("DELETE", f"/plugin/{quote_path(plugin_id)}"),
            f"卸载插件 {plugin_id}",
        )
        changed = True

    if changed:
        print("MoviePilot installed plugin selection updated")
    else:
        print("MoviePilot installed plugin selection already up to date")


def handle_plugin_configs(api, payload):
    desired = ensure_dict(payload, "pluginConfigs")
    managed_file = Path(os.environ["MOVIEPILOT_MANAGED_PLUGIN_CONFIGS_FILE"])
    managed_file.parent.mkdir(parents=True, exist_ok=True)

    resolved = {}
    for plugin_id, entry in desired.items():
        plugin_config = dict(ensure_dict(entry, f"pluginConfigs.{plugin_id}"))
        from_environment = plugin_config.pop("fromEnvironment", None) or {}

        for key, env_name in ensure_dict(
            from_environment,
            f"pluginConfigs.{plugin_id}.fromEnvironment",
        ).items():
            if env_name not in os.environ:
                raise MoviePilotApiError(
                    f"缺少环境变量 {env_name}，用于 pluginConfigs.{plugin_id}.{key}"
                )
            plugin_config[key] = os.environ[env_name]

        resolved[plugin_id] = plugin_config

    previous_managed = []
    if managed_file.exists():
        previous_managed = json.loads(managed_file.read_text() or "[]")

    changed = False
    for plugin_id, plugin_config in resolved.items():
        current = api.request_json("GET", f"/plugin/{quote_path(plugin_id)}") or {}
        if current != plugin_config:
            expect_response_success(
                api.request_json("PUT", f"/plugin/{quote_path(plugin_id)}", payload=plugin_config),
                f"更新插件配置 {plugin_id}",
            )
            changed = True

    for plugin_id in previous_managed:
        if plugin_id in resolved:
            continue
        current = api.request_json("GET", f"/plugin/{quote_path(plugin_id)}")
        if current in (None, {}):
            continue
        expect_response_success(
            api.request_json("PUT", f"/plugin/{quote_path(plugin_id)}", payload={}),
            f"清空插件配置 {plugin_id}",
        )
        changed = True

    current_managed = sorted(resolved.keys())
    previous_serialized = json.dumps(previous_managed, ensure_ascii=False, indent=2, sort_keys=True) + "\n" if previous_managed else ""
    current_serialized = json.dumps(current_managed, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if current_serialized != previous_serialized:
        managed_file.write_text(current_serialized)
        changed = True

    if changed:
        print("MoviePilot plugin configs updated")
    else:
        print("MoviePilot plugin configs already up to date")


def handle_superuser_password(api, _payload):
    desired_password = os.environ.get("SUPERUSER_PASSWORD")
    if not desired_password:
        print("MoviePilot superuser password sync skipped")
        return

    superuser_name = os.environ.get("SUPERUSER", "admin")
    if api.password_authenticates(superuser_name, desired_password):
        print("MoviePilot superuser password already up to date")
        return

    users = api.request_json("GET", "/user/") or []
    user = get_user_by_name(users, superuser_name)
    if not user:
        raise MoviePilotApiError(f"找不到超级管理员用户: {superuser_name}")

    payload = dict(user)
    payload["password"] = desired_password
    expect_response_success(
        api.request_json("PUT", "/user/", payload=payload),
        f"同步管理员密码 {superuser_name}",
    )
    print("MoviePilot superuser password updated")


def main():
    if len(sys.argv) != 2:
        raise MoviePilotApiError("用法: moviepilot-api-seed.py <mode>")

    mode = sys.argv[1]
    payload = read_json_stdin()
    api = MoviePilotApi()

    if mode == "superuser-password":
        handle_superuser_password(api, payload)
    elif mode == "downloaders":
        handle_system_setting(
            api,
            payload,
            "Downloaders",
            "MoviePilot downloaders config updated",
            "MoviePilot downloaders config already up to date",
            resolve_config_env=True,
        )
    elif mode == "directories":
        handle_system_setting(
            api,
            payload,
            "Directories",
            "MoviePilot directories config updated",
            "MoviePilot directories config already up to date",
        )
    elif mode == "media-servers":
        handle_system_setting(
            api,
            payload,
            "MediaServers",
            "MoviePilot media servers config updated",
            "MoviePilot media servers config already up to date",
            resolve_config_env=True,
        )
    elif mode == "storages":
        handle_system_setting(
            api,
            payload,
            "Storages",
            "MoviePilot storages config updated",
            "MoviePilot storages config already up to date",
        )
    elif mode == "installed-plugins":
        handle_installed_plugins(api, payload)
    elif mode == "plugin-configs":
        handle_plugin_configs(api, payload)
    elif mode == "plugin-folders":
        handle_system_setting(
            api,
            payload,
            "PluginFolders",
            "MoviePilot plugin folders updated",
            "MoviePilot plugin folders already up to date",
            empty_as_null=True,
        )
    elif mode == "sites":
        handle_sites(api, payload)
    elif mode == "site-auth":
        handle_site_auth(api, payload)
    elif mode == "subscriptions":
        handle_subscriptions(api, payload)
    elif mode == "indexer-sites":
        handle_site_selection(
            api,
            payload,
            "IndexerSites",
            "MoviePilot indexer site selection updated",
            "MoviePilot indexer site selection already up to date",
        )
    elif mode == "rss-sites":
        handle_site_selection(
            api,
            payload,
            "RssSites",
            "MoviePilot RSS site selection updated",
            "MoviePilot RSS site selection already up to date",
        )
    else:
        raise MoviePilotApiError(f"不支持的 mode: {mode}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(str(exc), file=sys.stderr)
        sys.exit(1)
