# Zig Mock Server

**English** · [简体中文](docs/README.zh-CN.md) · [日本語](docs/README.ja.md) · [Français](docs/README.fr.md) · [Deutsch](docs/README.de.md) · [繁體中文](docs/README.zh-TW.md)

A configuration-driven HTTP mock server built with Zig 0.17.0 and httpz. Define routes and response scenarios in JSON, then reload the file or apply changes through the web console.

## Build and run

Use Zig **0.17.0**. Dependency revisions and hashes are pinned in `build.zig.zon`. Pin the compiler distribution for production builds.

Run the Bash or PowerShell build script, then start the service from the project root.

```bash
bash build.sh
```

```powershell
.\build.ps1
```

```sh
zig build run
```

The build scripts check PATH and the local toolchain cache first. If needed, they download the compiler from the official Zig release index, verify its SHA-256 checksum and cache it under `.zig-cache/toolchains/`. Automatic downloads support x86_64 and ARM64 on Linux, macOS and Windows, plus x86 on Linux and Windows. The Bash download path needs `curl`, `sha256sum` or `shasum`, and a `tar` with xz support. Git Bash uses `unzip` for Windows archives. The PowerShell script runs on Windows PowerShell 5.1 or PowerShell 7. Its non-Windows download path needs a `tar` with xz support. [Official Zig release index](https://ziglang.org/download/index.json)

Both scripts run `zig build --fetch` and then `zig build` with the default `Debug` optimization level. Once the toolchain and dependencies are cached, builds can run offline. If Zig is outside PATH, run `.\zig-out\bin\test_web.exe` on Windows or `./zig-out/bin/test_web` on Linux and macOS.

The default listen address is `0.0.0.0:9080`. Use `http://127.0.0.1:9080` locally. When `MOCK_ADMIN_TOKEN` is empty or unset, startup generates a new token and prints it as `Generated admin token: …`. Set a token of at least 16 bytes before startup to reuse it across restarts. The service prints generated tokens only.

## Bundled examples

The **Examples** folder in the web console groups these routes from [the sample configuration](config/mock.json). Send JSON with `Content-Type: application/json` and XML with `Content-Type: application/xml`.

| Feature | Request | Request body | Response body |
| --- | --- | --- | --- |
| JSONPath | `POST /examples/jsonpath` | `{"orders":[{"qty":2,"status":"paid"}]}` | `{"matched":"jsonpath"}` |
| XPath | `POST /examples/xpath` | `<order xmlns="urn:orders"><status>paid</status></order>` | `{"matched":"xpath"}` |
| Query parameters | `GET /examples/query?status=paid&source=web` | — | `{"matched":"query"}` |
| Path parameters | `GET /examples/items/42` | — | `{"matched":"path","id":42}` |
| Regular expression | `POST /examples/regex` | `{"code":"AB-42"}` | `{"matched":"regex"}` |
| JSON response template | `POST /examples/template/json` | `{"name":"Ada"}` | `{"message":"Hello, Ada!"}` |
| XML response template | `POST /examples/template/xml` | `<request><name>Ada</name></request>` | `<greeting>Hello, Ada!</greeting>` |

Each matching example returns HTTP 200. For the five examples with matching conditions, a valid request that does not satisfy the rule returns 404.

```bash
curl -fsS http://127.0.0.1:9080/healthz
curl -fsS http://127.0.0.1:9080/examples/jsonpath -H 'Content-Type: application/json' -d '{"orders":[{"qty":2,"status":"paid"}]}'
curl -fsS http://127.0.0.1:9080/examples/xpath -H 'Content-Type: application/xml' -d '<order xmlns="urn:orders"><status>paid</status></order>'
curl -fsS 'http://127.0.0.1:9080/examples/query?status=paid&source=web'
curl -fsS http://127.0.0.1:9080/examples/items/42
curl -fsS http://127.0.0.1:9080/examples/regex -H 'Content-Type: application/json' -d '{"code":"AB-42"}'
curl -fsS http://127.0.0.1:9080/examples/template/json -H 'Content-Type: application/json' -d '{"name":"Ada"}'
curl -fsS http://127.0.0.1:9080/examples/template/xml -H 'Content-Type: application/xml' -d '<request><name>Ada</name></request>'
```

## Web console and read-only catalog

Open `http://127.0.0.1:9080/admin/` and enter the admin token. The console keeps it in page memory, so refreshing the browser requires reconnecting. Light is the default theme. The browser remembers your choice of Light, Dark, Cyberpunk 2077, EVA, Death Stranding or Black Myth: Wukong.

- Use the directory button to open or collapse the sidebar. On narrow screens, click the backdrop, press Esc or select a route to dismiss it.
- Create nested folders, rename or move them, or remove empty folders. Move a route from its menu or change its folder in the editor. Search by path fragment or full HTTP(S) URL. Full URLs are matched by path.
- Create, copy, edit or delete response scenarios. Set the request format per route and the response format per scenario. Configure matching, priority, status, delay, headers and templates in the scenario.
- Enter query conditions as a JSON object, a query string beginning with `?` or a URL with a query. For a route like `/orders/{id}`, enter `{"id":"42"}` as its path condition. Pick JSONPath, XPath or regular expression under the request-body matching options.
- Save to apply the entire configuration and write it to disk. Deleting a scenario changes the draft. Deleting a route requires confirmation and saves the configuration, including other edits in the draft. A route needs at least one scenario.
- Fill in a scenario example to populate the test URL, headers and body. Supply a matching body manually for expression rules. The test sends a real request to this service with the saved rules. GET and HEAD send no body. The panel supports cancellation and a 35-second timeout. It blocks redirects and sends the admin token only if you explicitly enter it as a test header.
- Refresh reads the active configuration. Reload reads the configured file. The console asks before discarding a draft and keeps it on a save conflict.

The editor preserves JSON numeric representations, including 64-bit integers. The executable embeds the web assets. Frontend source changes require rebuilding and restarting the service.

Open `http://127.0.0.1:9080/viewer` directly or from the console. The catalog allows anonymous, read-only access to route search, request details, rule conditions and response previews. `GET /viewer/api/catalog` returns the active catalog.

### Admin API

| Request | Behavior |
| --- | --- |
| `GET /admin/api/config` | Returns `config`, `generation`, `revision` and an ETag. |
| `PUT /admin/api/config` | Validates, persists and activates a complete configuration. Send `If-Match: "revision"`. |
| `POST /admin/reload` | Loads and activates the configured file. |

All three operations require `Authorization: Bearer <Token>`. PUT returns 428 without `If-Match`, 409 on a stale revision or an external file change, 400 on invalid configuration and 500 on an I/O failure. The revision is the SHA-256 of the file bytes. Saving uses a temporary file in the same directory, flushes it and atomically replaces the target before activating the new snapshot. The service user needs write access to the configuration directory.

## Configuration reference

The top-level JSON can contain `version`, `cors`, `folders`, `trusted_proxies` and `routes`. Version defaults to 1. A folder has an `id`, a `name` and an optional `parent_id`, with up to 16 levels of nesting. Routes with no `folder_id` appear at the root. Folder assignment only affects the UI.

```json
{
  "version": 1,
  "cors": {
    "origins": ["https://frontend.example.com"],
    "allow_headers": "Content-Type, Authorization, X-Scenario",
    "max_age": 600
  },
  "routes": [
    {
      "method": "GET",
      "path": "/users",
      "rules": [
        {
          "id": "unavailable",
          "priority": 100,
          "match": {
            "query": [{ "name": "scenario", "value": "error" }],
            "headers": [{ "name": "X-Scenario", "value": "test" }]
          },
          "response": { "status": 503, "delay_ms": 200, "body": { "code": 503 } }
        },
        {
          "id": "success",
          "response": { "body": { "users": [{ "id": 1, "name": "Ada" }] } }
        }
      ]
    }
  ]
}
```

`GET /users?scenario=error` with `X-Scenario: test` returns 503. Other requests to the same route use its success scenario.

### Route and rule matching

- Supported route methods are GET, POST, PUT, PATCH, DELETE and HEAD. OPTIONS handles CORS preflight. HEAD has no automatic GET fallback.
- Fixed paths take precedence over templates. Each `{name}` captures one nonempty path segment. Names start with an ASCII letter or underscore, may also contain digits and must be unique within the template. Among templates, the one with more fixed segments wins. Ties use configuration order. Route shapes must be unique per method.
- `match.path` compares the decoded captured values exactly. The server splits the raw path before percent-decoding and treats `+` literally. `match.query` compares decoded names and values. Parameter order and extra parameters do not affect matches. Duplicate query parameters use their first value. `?flag` and `?flag=` both represent an empty value. Invalid percent encoding during matching returns 400.
- `match.headers` compares header names without regard to case and compares values exactly. For duplicates, the first value is used.
- For JSON, `match.body` is an object subset. Arrays match by length and order, and scalar comparisons distinguish types such as `1`, `1.0` and `"1"`. For XML, it is a full document string. XML matching ignores the UTF-8 BOM, leading and trailing whitespace and differences in line endings.
- Every configured condition must match. The highest-priority matching rule wins, with configuration order breaking ties. The default priority is 0. Missing routes or unmatched rules return JSON 404.

### Request body expressions

Set `match.body_expression` as an alternative to `match.body`.

| Mode | Request format | Match rule |
| --- | --- | --- |
| `jsonpath` | JSON | Selects at least one value. If `expected.value` is set, at least one selected value must be exactly equal, with JSON types preserved. |
| `xpath` | XML | Uses the XPath 1.0 boolean value. With a string `expected.value`, compares the string value of any selected node or the XPath string form of a scalar. |
| `regex` | JSON or XML | Searches the original body with RE2-style syntax. Use `^` and `$` to anchor it. |

```json
{
  "match": {
    "body_expression": {
      "mode": "jsonpath",
      "expression": "$.orders[?@.qty >= 2].status",
      "expected": { "value": "paid" }
    }
  }
}
```

Use `"expected": {"value": null}` to match JSON null. JSONPath supports properties, array selectors, recursive descent and filters. Use the dedicated regex mode for regex matching because JSONPath `match()` and `search()` are disabled.

Use XPath predicates or boolean expressions such as `/order/item[@sku='paid']` or `count(/order/item) > 0`. Bind namespace prefixes with `"namespaces": [{"prefix":"o","uri":"urn:orders"}]`, then use `/o:order/o:item/@sku`. A default namespace also needs a prefix binding in the expression.

Rules compile on load or save. Expressions are limited to 1024 bytes. Empty bodies do not match expression rules. The service validates the body format before evaluating any rule. JSONPath sees JSON field defaults, while regex sees the original bytes. JSONPath and XPath use a 16 MiB evaluation workspace per request. JSONPath accepts up to 128 levels of JSON nesting. Requests that exceed evaluation limits receive 400.

### Request validation and response templates

`request.format` defaults to `json`. `request.body_required` rejects missing bodies. Without a required body, absent JSON is treated as an empty object. JSON field validation requires an object and supports `string`, `integer` (signed 64-bit), `number` and `boolean`. A field may be required or have a default. Extra fields are retained. Defaults are applied before matching and rendering. Invalid bodies or fields return 400.

Enable `response.template: true` to use `{{body.name}}`. It reads a top-level JSON field or the text of the XML root's `name` child. Referenced JSON fields must be required or have a default. XML also supports nested paths such as `{{body.customer.name}}` and attribute references such as `{{body.@id}}` or `{{body.customer.@id}}`. At each level, XML selects the first child with the matching case-sensitive name and namespace prefix. Element values include descendant text. `{{body.age|add:1}}` adds an integer constant.

Insert values in JSON strings or in XML element text and ordinary attribute values. The service escapes inserted text for the response format and validates generated XML. Missing values, non-integers for `add` and integer overflow return 400. XML-related templates have a 4 MiB dynamic-text budget. The two template routes in **Examples** demonstrate the JSON and XML variants.

### Responses and limits

`response.body` is required. The status defaults to 200. JSON is the default response format, with `application/json` and JSON encoding even for strings. XML responses send UTF-8 XML with `application/xml; charset=utf-8`. A custom Content-Type header can override the default header. The format controls the encoding.

- Status codes range from 200 to 599. Statuses 204, 205 and 304 require `body: null`. These statuses and HEAD send no body.
- `delay_ms` can range from 0 to 30000. A delay releases the configuration lock while the httpz worker waits.
- Request bodies are limited to 1 MiB and configuration files must be smaller than 4 MiB. A configuration can have up to 1000 routes, 1000 rules per route and 32 custom headers per response.
- XML must be UTF-8, contain at most 128 levels of nesting and pass well-formedness checks. Documents with a DTD are rejected.
- `/healthz`, `/admin`, `/admin/*`, `/viewer` and `/viewer/*` are reserved. Unknown fields, duplicate route shapes or rule IDs within a route, invalid templates and prohibited headers invalidate the configuration. The service controls Content-Length, Transfer-Encoding, Connection, Keep-Alive, Upgrade, Trailer, Vary and Access-Control-* headers.

## Reload, CORS and health

After atomically replacing the file identified by `MOCK_CONFIG`, call reload. For a generated token, use the value printed at startup in the Bearer header.

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

Reload reads only the configured local file and keeps the current admin token. A missing or invalid token returns 401.

A successful reload reports `status`, `generation` and `routes`. A missing file or invalid configuration returns 400 with a `reason` and leaves the previous generation active. An invalid startup configuration prevents startup. Reload and online save are serialized. Requests in progress retain their response data during a configuration switch.

CORS allows all origins by default without cross-origin credentials. Set `cors.origins` to exact origins including scheme and port, with no trailing slash. An empty array disables CORS. Use `*` on its own. Preflight validates the origin, method and headers. The management and catalog paths have a separate policy. Ordinary requests from disallowed origins can still reach the service, without CORS permission headers.

`GET /healthz` reports `status: "ok"`, the active `generation` and the number of `routes`. It continues reporting the active configuration after a failed reload. HEAD is supported. Other methods except OPTIONS return 405.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `MOCK_HOST` | `0.0.0.0` | IPv4 or IPv6 listen address. |
| `MOCK_PORT` | `9080` | Listen port from 1 to 65535. |
| `MOCK_CONFIG` | `config/mock.json` | Configuration path, relative to the process working directory if not absolute. |
| `MOCK_ADMIN_TOKEN` | Generated | Optional fixed admin token of at least 16 bytes. |

## Rate limits

In the console, open the route's rate limit section. Set the default per-client requests per second and optional per-IP overrides such as `{"192.0.2.10":20,"2001:db8::1":0}`. Values are integers from 0 to 10000. Zero means unlimited. The config uses `rate_limit.requests_per_second` and `rate_limit.clients` on each route.

Each process counts admitted requests in the last second by client IP, request method and configured route. Path and query variations and response scenarios share the route's client quota. A rate-limited request returns 429 and `Retry-After: 1`. If the limiter cannot track a new request at capacity, it returns 503 with the same header. Saving changes applies the new limits immediately and preserves active counters.

Unknown routes, health checks, admin and catalog requests, and OPTIONS do not consume the quota.

The peer address identifies the client by default. Set `trusted_proxies`, for example `["127.0.0.1"]`, to accept `X-Forwarded-For` from the listed proxy addresses. Keep the backend reachable only through trusted proxies in that setup. In a chain, the last proxy should pass a single verified client address. [Caddy reverse proxy headers](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#headers)

## Deploy on Linux

The provided systemd and Caddy examples use `Client → Caddy HTTPS → 127.0.0.1:9080 → Mock server`. Run the deployment commands on the target server with administrative privileges.

Build for the server's architecture. The second command cross-compiles a Linux x86_64 executable to `zig-out/linux/bin/test_web`. Use the matching target for ARM64 and verify the executable on the target host.

```sh
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p zig-out/linux
```

Upload the executable and project configuration. From the upload directory, create a system user with no login shell and install the files.

```sh
sudo useradd --system --no-create-home --shell /usr/sbin/nologin mock
sudo install -d -m 0755 /opt/zig-mock /etc/zig-mock
sudo install -d -o mock -g mock -m 0750 /var/lib/zig-mock
sudo install -m 0755 test_web /opt/zig-mock/test_web
sudo install -o mock -g mock -m 0640 config/mock.json /var/lib/zig-mock/mock.json
sudo install -m 0600 deploy/mock.env.example /etc/zig-mock/mock.env
sudo install -m 0644 deploy/mock.service /etc/systemd/system/zig-mock.service
```

Set a fixed token in `/etc/zig-mock/mock.env` if desired. The service can write to `/var/lib/zig-mock/`. The environment file is readable only by root.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now zig-mock
curl --fail http://127.0.0.1:9080/healthz
sudo journalctl -u zig-mock -n 50 --no-pager
```

If an existing systemd installation stores its configuration at `/etc/zig-mock/mock.json`, copy it into `/var/lib/zig-mock/`, set ownership to `mock:mock` and update `MOCK_CONFIG` before restarting.

For JSON changes, call reload. Changes to the executable or environment require `sudo systemctl restart zig-mock`. Startup output, including a generated token, is available through journald.

Replace the domain in [the Caddy example](deploy/Caddyfile) and merge the site block into the server's Caddy configuration. Point DNS at the server and open ports 80 and 443.

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

The default proxy example forwards mock requests and blocks public access to `/admin` and `/viewer`. Verify HTTPS with `/healthz` and a sample route. Access the console and catalog through `ssh -L 19080:127.0.0.1:9080 user@server` and local port 19080, or use [the alternative Caddy example](deploy/Caddyfile.admin.example) to expose them over HTTPS. On that configuration, the admin API still requires a token and any visitor who can reach the domain can read the catalog.

The service logs neither request bodies nor manually configured tokens. Use the reverse proxy to apply access controls to mock traffic when needed.

## Verification

```sh
zig fmt --check src/main.zig src/mock.zig src/app.zig src/body_match.zig src/jsonpath_regex.zig build.zig build.zig.zon
zig build test
zig build
python tests/integration.py
node --test tests/json-codec.test.cjs
```

The Python integration suite uses a temporary configuration and a random local port. You can supply an executable path, for example `python3 tests/integration.py /opt/zig-mock/test_web`.
