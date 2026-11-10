# Zig Mock 服务

[English](../README.md) · **简体中文** · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [繁體中文](README.zh-TW.md)

基于 Zig 0.17.0 和 httpz 的配置驱动 HTTP Mock 服务。通过 JSON 定义接口和响应场景，可重载文件或在网页管理台保存并生效。

## 构建与运行

使用 Zig **0.17.0**。依赖版本和哈希固定在 `build.zig.zon` 中，生产构建应使用同一份编译器发行包。

运行 Bash 或 PowerShell 构建脚本，再从项目根目录启动服务。

```bash
bash build.sh
```

```powershell
.\build.ps1
```

```sh
zig build run
```

脚本先检查 PATH 和本地工具链缓存，必要时从 Zig 官方发行目录下载编译器、校验 SHA-256，并缓存到 `.zig-cache/toolchains/`。自动下载支持 Linux、macOS 和 Windows 的 x86_64、ARM64，以及 Linux 和 Windows 的 x86。Bash 下载需要 `curl`、`sha256sum` 或 `shasum` 及支持 xz 的 `tar`，Git Bash 解压 Windows 发行包使用 `unzip`。PowerShell 脚本支持 Windows PowerShell 5.1 和 PowerShell 7，非 Windows 平台下载需要支持 xz 的 `tar`。[Zig 官方发行目录](https://ziglang.org/download/index.json)

两个脚本依次运行 `zig build --fetch` 和 `zig build`，采用默认的 `Debug` 优化级别。工具链和依赖缓存后可离线构建。Zig 尚未加入 PATH 时，可在 Windows 运行 `.\zig-out\bin\test_web.exe`，或在 Linux 和 macOS 运行 `./zig-out/bin/test_web`。

服务默认监听 `0.0.0.0:9080`，本机可访问 `http://127.0.0.1:9080`。`MOCK_ADMIN_TOKEN` 为空或未设置时，启动会生成新 Token 并打印为 `Generated admin token: …`。如需跨重启复用，启动前设置至少 16 字节的 Token。服务只打印自动生成的 Token。

## 内置示例

网页管理台的 **Examples** 目录包含以下[示例配置](../config/mock.json)中的路由。JSON 请求使用 `Content-Type: application/json`，XML 请求使用 `Content-Type: application/xml`。

| 功能 | 请求 | 请求体 | 响应体 |
| --- | --- | --- | --- |
| JSONPath | `POST /examples/jsonpath` | `{"orders":[{"qty":2,"status":"paid"}]}` | `{"matched":"jsonpath"}` |
| XPath | `POST /examples/xpath` | `<order xmlns="urn:orders"><status>paid</status></order>` | `{"matched":"xpath"}` |
| 查询参数 | `GET /examples/query?status=paid&source=web` | — | `{"matched":"query"}` |
| 路径参数 | `GET /examples/items/42` | — | `{"matched":"path","id":42}` |
| 正则表达式 | `POST /examples/regex` | `{"code":"AB-42"}` | `{"matched":"regex"}` |
| JSON 响应模板 | `POST /examples/template/json` | `{"name":"Ada"}` | `{"message":"Hello, Ada!"}` |
| XML 响应模板 | `POST /examples/template/xml` | `<request><name>Ada</name></request>` | `<greeting>Hello, Ada!</greeting>` |

命中示例时返回 HTTP 200。前五个示例配置了匹配条件，合法请求未命中时返回 404。

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

## 网页管理台和只读目录

打开 `http://127.0.0.1:9080/admin/` 并输入管理 Token。Token 保留在页面内存中，刷新后需要重新连接。默认主题为 Light，浏览器会记住 Light、Dark、Cyberpunk 2077、EVA、死亡搁浅或黑神话：悟空主题的选择。

- 点击 **目录** 展开或折叠侧栏。窄屏下可点击遮罩、按 Esc 或选择接口来收起侧栏。
- 可创建嵌套目录、重命名、移动或删除空目录。通过接口菜单或编辑区修改所属目录。搜索支持路径片段和完整 HTTP(S) URL，完整 URL 按路径匹配。
- 可新增、复制、编辑或删除响应场景。请求格式按接口设置，响应格式按场景设置。场景内配置匹配条件、优先级、状态码、延迟、响应头及模板。
- 查询参数条件支持 JSON 对象、以 `?` 开头的查询字符串或带查询参数的 URL。对 `/orders/{id}` 这类接口，可填写 `{"id":"42"}` 作为路径条件。通过 **请求体匹配方式** 选择 JSONPath、XPath 或正则表达式。
- 点击 **保存并生效** 会把整份配置写入磁盘并生效。删除场景先修改草稿，删除接口需确认并保存配置，同时保存草稿中的其他修改。每个接口至少保留一个场景。
- 点击 **填入场景示例** 可生成测试 URL、请求头和请求体。表达式规则需要手动填入满足条件的请求体。**发送请求** 调用本服务已保存的规则。GET 和 HEAD 不发送请求体。可取消请求，超时为 35 秒。测试面板阻止重定向，管理 Token 只有手动填入请求头时才会发送。
- **刷新配置** 读取当前生效配置，**重载文件** 读取配置文件。丢弃草稿前会确认，保存冲突时会保留草稿。

编辑器保留 64 位整数等 JSON 数值表示。网页资源嵌入可执行文件，修改前端源码后需重新构建和启动服务。

可直接打开 `http://127.0.0.1:9080/viewer`，也可从管理台进入。只读目录无需登录，可搜索路由并查看请求详情、匹配规则和响应预览。`GET /viewer/api/catalog` 返回当前生效的目录。

### 管理 API

| 请求 | 行为 |
| --- | --- |
| `GET /admin/api/config` | 返回 `config`、`generation`、`revision` 和 ETag。 |
| `PUT /admin/api/config` | 校验、保存并生效整份配置。请求需带 `If-Match: "revision"`。 |
| `POST /admin/reload` | 读取配置文件并生效。 |

三个操作均需 `Authorization: Bearer <Token>`。PUT 缺少 `If-Match` 时返回 428，版本过期或检测到外部文件改动时返回 409，配置无效时返回 400，I/O 失败时返回 500。revision 是文件字节的 SHA-256。保存先写入同目录临时文件并刷新，再原子替换目标文件，随后切换内存快照。服务用户需要配置目录的写权限。

## 配置参考

顶层 JSON 可包含 `version`、`cors`、`folders`、`trusted_proxies` 和 `routes`，版本默认 1。目录包含 `id`、`name` 和可选的 `parent_id`，最多嵌套 16 层。未设 `folder_id` 的路由显示在根目录。目录归属只影响界面展示。

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

`GET /users?scenario=error` 携带 `X-Scenario: test` 时返回 503。该路由的其他请求使用成功场景。

### 路由和规则匹配

- 路由支持 GET、POST、PUT、PATCH、DELETE 和 HEAD。OPTIONS 处理跨域预检。HEAD 无自动 GET 回退。
- 固定路径优先于模板。每个 `{name}` 捕获一个非空路径段。名称以英文字母或下划线开头，可包含数字，同一模板中需唯一。多个模板匹配时，固定段更多的优先，同等具体程度按配置顺序。同一方法下的路由形状需唯一。
- `match.path` 精确比较解码后的捕获值。服务先按原始斜线分段，再进行百分号解码，`+` 保留原义。`match.query` 比较解码后的名称和值，顺序和额外参数不影响匹配。重复参数取第一个值，`?flag` 和 `?flag=` 均表示空值。匹配时遇到非法百分号编码返回 400。
- `match.headers` 的名称忽略大小写，值精确比较。同名头取第一个值。
- JSON 的 `match.body` 按对象子集匹配。数组比较长度和顺序，标量区分 `1`、`1.0` 和 `"1"` 等类型。XML 的 `match.body` 是完整文档字符串，忽略 UTF-8 BOM、首尾空白和换行符差异。
- 所有已配置条件都要满足。优先级最高的匹配规则生效，同级按配置顺序，默认优先级为 0。没有路由或规则命中时返回 JSON 404。

### 请求体表达式

`match.body_expression` 与 `match.body` 二选一。

| 模式 | 请求格式 | 匹配规则 |
| --- | --- | --- |
| `jsonpath` | JSON | 至少选中一个值。填写 `expected.value` 时，任一选中值须完全相等，比较区分 JSON 类型。 |
| `xpath` | XML | 按 XPath 1.0 布尔规则判断。设置字符串 `expected.value` 时，比较任一选中节点的字符串值，或标量的 XPath 字符串表示。 |
| `regex` | JSON 或 XML | 用 RE2 风格语法在原始请求体中搜索，`^` 和 `$` 可限制起止位置。 |

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

可用 `"expected": {"value": null}` 匹配 JSON null。JSONPath 支持属性、数组选择、递归下降和筛选。JSONPath 的 `match()` 和 `search()` 禁用，正则请使用独立模式。

XPath 可用谓词或布尔表达式，例如 `/order/item[@sku='paid']` 或 `count(/order/item) > 0`。用 `"namespaces": [{"prefix":"o","uri":"urn:orders"}]` 绑定前缀后，可写 `/o:order/o:item/@sku`。默认命名空间也需要在表达式中用绑定后的前缀。

表达式在加载或保存配置时编译，最多 1024 字节。空请求体不命中表达式。服务先校验请求体格式，再判断规则。JSONPath 使用已应用字段默认值的 JSON，正则使用原始字节。JSONPath 和 XPath 每次请求使用 16 MiB 的求值工作区。JSONPath 的 JSON 嵌套上限为 128 层。超过求值限制时返回 400。

### 请求校验和响应模板

`request.format` 默认为 `json`。启用 `request.body_required` 后，缺少请求体时会被拒绝。可省略的 JSON 请求体按空对象处理。JSON 字段校验要求对象，支持 `string`、`integer`（有符号 64 位）、`number` 和 `boolean`。字段可设为必填或设置默认值。额外字段会保留，默认值在匹配和渲染前应用。请求体或字段无效时返回 400。

设置 `response.template: true` 后，`{{body.name}}` 可读取 JSON 顶层字段或 XML 根元素下 `name` 子元素的文本。引用的 JSON 字段需为必填或有默认值。XML 支持 `{{body.customer.name}}` 等嵌套路径，以及 `{{body.@id}}` 和 `{{body.customer.@id}}` 等属性引用。每一级取名称和命名空间前缀精确匹配的第一个子元素，区分大小写。元素值包含其后代文本。`{{body.age|add:1}}` 可加上整数常量。

值可插入 JSON 字符串或 XML 元素文本及普通属性值。服务按响应格式转义插入内容，并校验生成的 XML。缺少引用值、`add` 遇到非整数或整数溢出时返回 400。涉及 XML 的模板动态文本预算为 4 MiB。**Examples** 目录的两个模板路由分别演示 JSON 和 XML。

### 响应和限制

`response.body` 必填，默认状态码为 200。响应格式默认为 JSON，Content-Type 为 `application/json`，字符串也按 JSON 编码。XML 响应发送 UTF-8 XML，Content-Type 为 `application/xml; charset=utf-8`。可用自定义 Content-Type 覆盖默认响应头，正文编码由响应格式决定。

- 状态码范围为 200 至 599。204、205 和 304 需配置 `body: null`，与 HEAD 一样不发送响应体。
- `delay_ms` 范围为 0 至 30000。延迟期间释放配置锁，httpz 工作线程继续等待。
- 请求体最多 1 MiB，配置文件须小于 4 MiB。最多配置 1000 个路由、每路由 1000 条规则和每个响应 32 个自定义头。
- XML 须为有效的 UTF-8 XML，最多嵌套 128 层。含 DTD 的文档会被拒绝。
- `/healthz`、`/admin`、`/admin/*`、`/viewer` 和 `/viewer/*` 是保留路径。未知字段、重复路由形状、同路由重复规则 ID、无效模板或受限响应头会使配置无效。Content-Length、Transfer-Encoding、Connection、Keep-Alive、Upgrade、Trailer、Vary 和 Access-Control-* 由服务管理。

## 重载、跨域和健康检查

原子替换 `MOCK_CONFIG` 指定的文件后调用重载。若使用自动生成的 Token，请将启动时打印的值填入 Bearer 请求头。

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

重载只读取已配置的本地文件，当前管理 Token 继续有效。Token 缺失或无效时返回 401。

重载成功时返回 `status`、`generation` 和 `routes`。文件缺失或配置无效时返回 400 和 `reason`，上一代配置继续生效。启动时配置无效会退出。重载和在线保存串行执行。配置切换期间，在途请求保留其响应数据。

默认允许所有 Origin，服务不启用跨域凭据模式。`cors.origins` 可填写包含协议和端口、无末尾斜线的精确 Origin 列表。空数组关闭跨域，`*` 需单独使用。预检校验 Origin、方法和请求头。管理页和只读目录使用独立策略。来自不允许 Origin 的普通请求仍可被服务处理，响应没有跨域许可头。

`GET /healthz` 返回 `status: "ok"`、当前 `generation` 和 `routes` 数量。重载失败后仍报告当前有效配置。支持 HEAD。其他方法除 OPTIONS 外返回 405。

## 环境变量

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `MOCK_HOST` | `0.0.0.0` | IPv4 或 IPv6 监听地址。 |
| `MOCK_PORT` | `9080` | 监听端口 1 至 65535。 |
| `MOCK_CONFIG` | `config/mock.json` | 配置路径，相对路径以进程工作目录为准。 |
| `MOCK_ADMIN_TOKEN` | 自动生成 | 可选固定管理 Token，至少 16 字节。 |

## 请求限流

在管理台展开接口的 **请求限流**。设置每个客户端默认每秒上限，也可按 IP 单独设置，例如 `{"192.0.2.10":20,"2001:db8::1":0}`。值为 0 至 10000 的整数，0 表示不限。路由配置字段为 `rate_limit.requests_per_second` 和 `rate_limit.clients`。

每个进程按客户端 IP、请求方法和配置中的路由统计过去一秒内已放行的请求。路径和查询参数变化及响应场景共用该路由的客户端额度。超限返回 429 和 `Retry-After: 1`。计数存储达到容量上限时，新请求返回 503 和相同响应头。保存后新限额立即生效，在窗口内的计数会保留。

未知路由、健康检查、管理和只读目录请求以及 OPTIONS 不消耗额度。

默认以连接对端 IP 识别客户端。配置 `trusted_proxies`，例如 `["127.0.0.1"]`，可接收来自指定代理的 `X-Forwarded-For`。此时后端应只允许可信代理访问。多级代理中的最后一跳应传递唯一且已核实的客户端地址。[Caddy 反向代理请求头](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#headers)

## 部署到 Linux

随附的 systemd 和 Caddy 示例采用 `客户端 → Caddy HTTPS → 127.0.0.1:9080 → Mock 服务`。请在目标服务器上使用管理员权限执行部署命令。

按目标服务器架构构建。第二条命令交叉编译 Linux x86_64 程序到 `zig-out/linux/bin/test_web`。ARM64 使用对应目标，产物需在目标服务器验证。

```sh
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p zig-out/linux
```

上传可执行文件和项目配置。从上传目录创建无登录权限的系统用户并安装文件。

```sh
sudo useradd --system --no-create-home --shell /usr/sbin/nologin mock
sudo install -d -m 0755 /opt/zig-mock /etc/zig-mock
sudo install -d -o mock -g mock -m 0750 /var/lib/zig-mock
sudo install -m 0755 test_web /opt/zig-mock/test_web
sudo install -o mock -g mock -m 0640 config/mock.json /var/lib/zig-mock/mock.json
sudo install -m 0600 deploy/mock.env.example /etc/zig-mock/mock.env
sudo install -m 0644 deploy/mock.service /etc/systemd/system/zig-mock.service
```

如需固定 Token，可在 `/etc/zig-mock/mock.env` 中设置。服务可以写入 `/var/lib/zig-mock/`，环境文件仅 root 可读。

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now zig-mock
curl --fail http://127.0.0.1:9080/healthz
sudo journalctl -u zig-mock -n 50 --no-pager
```

如果现有 systemd 服务将配置放在 `/etc/zig-mock/mock.json`，请复制到 `/var/lib/zig-mock/`，将所有者设为 `mock:mock` 并更新 `MOCK_CONFIG`，然后重启。

修改 JSON 后可调用重载。修改可执行文件或环境变量后执行 `sudo systemctl restart zig-mock`。启动输出及生成的 Token 可通过 journald 查看。

替换 [Caddy 示例](../deploy/Caddyfile)中的域名，将站点块合并到服务器的 Caddy 配置。将 DNS 指向服务器，开放 80 和 443 端口。

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

默认反向代理转发 Mock 请求，并屏蔽公网对 `/admin` 和 `/viewer` 的访问。可通过 `/healthz` 和一个示例路由检查 HTTPS。管理台和目录可通过 `ssh -L 19080:127.0.0.1:9080 user@server` 后访问本地 19080 端口，也可通过[备用 Caddy 示例](../deploy/Caddyfile.admin.example)在 HTTPS 下访问。此时管理 API 仍需 Token，能访问域名的访客可以读取目录。

服务不记录请求体和手动设置的 Token。需要限制 Mock 调用时，可在反向代理层设置访问控制。

## 验证

```sh
zig fmt --check src/main.zig src/mock.zig src/app.zig src/body_match.zig src/jsonpath_regex.zig build.zig build.zig.zon
zig build test
zig build
python tests/integration.py
node --test tests/json-codec.test.cjs
```

Python 集成测试使用临时配置和随机本机端口。可传入可执行文件路径，例如 `python3 tests/integration.py /opt/zig-mock/test_web`。
