# Zig 在线 Mock 服务

基于 Zig 0.17.0 + httpz 的配置驱动 HTTP Mock 服务。修改 JSON 并调用重载接口，即可增加、修改或删除接口，无需重新编译。

已迁移原有 `POST /hello/test` 和 `POST /order`，保留姓名/年龄动态响应、默认字段、订单必填字段校验和银联失败场景。业务规则位于 `config/mock.json`，不再注册原来的硬编码 handler。

## 本地运行

使用与本项目兼容的 Zig **0.17.0** 工具链；依赖提交和 hash 已固定在 `build.zig.zon`。生产构建应固定同一份编译器发行包，不要在部署时自动升级。

在项目根目录运行：

```powershell
# 网页管理需要设置此变量。请替换为至少 16 字符的随机密钥。
$env:MOCK_ADMIN_TOKEN = 'replace-with-your-own-random-secret'
zig build run
```

默认监听 `0.0.0.0:9080`，本机通过 `http://127.0.0.1:9080` 调用。

```powershell
Invoke-RestMethod http://127.0.0.1:9080/healthz

$body = @{ name = '小明'; age = 20 } | ConvertTo-Json
Invoke-RestMethod http://127.0.0.1:9080/hello/test -Method Post `
  -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))

$order = @{
  product_name = '测试商品'; product_id = 1; order_id = 'demo-001'
  count = 1; buyer_account = 'demo'; pay_method = 'UnionPay'
} | ConvertTo-Json
# 此场景预期 HTTP 400，PowerShell 会将其作为 HTTP 错误显示。
Invoke-RestMethod http://127.0.0.1:9080/order -Method Post `
  -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($order))
```

## 网页管理界面

启动后打开 `http://127.0.0.1:9080/admin/`，输入 `MOCK_ADMIN_TOKEN` 即可连接。未设置 Token 时整个 `/admin` 区域返回 404。静态登录页面不包含配置或密钥，所有配置读写与重载都需要 Bearer Token。Token 只保留在当前页面内存中，不写入浏览器存储；刷新页面需重新连接。

- 左侧搜索、选择或新建接口，编辑请求方法、路径及请求字段校验。
- 每个接口可新增、复制、修改或删除响应场景，设置优先级、匹配条件、状态码、延迟、模板、响应体和响应头。
- 点击 **保存并生效** 后整份配置写入 `MOCK_CONFIG` 文件并立即生效。请求体匹配填写 `null` 表示不限，`{}` 表示必须是对象但不限字段。
- 删除场景先修改草稿，需点击保存；删除接口会二次确认并立即保存，也会保存其他接口已经编辑的草稿。每个接口至少一个场景，可删除最后一个接口得到空配置。
- 右侧 **填入场景示例** 会根据字段默认值和匹配条件构造请求。**发送请求** 调用当前服务真实接口，显示 HTTP 状态码、耗时、响应头和响应体；不自动保存草稿。
- 测试只允许当前服务的非管理路径；管理 Token 不自动加入测试请求。可以手动填写业务 Authorization 请求头。GET/HEAD 不发送请求体；请求支持取消及 35 秒超时；不自动跟随重定向。
- **刷新配置** 读取当前内存配置，**重载文件** 从磁盘加载。存在草稿时会确认；保存冲突时保留草稿，不覆盖其他人的修改。

浏览器编辑器保留 64 位整数、浮点数和科学计数法的 JSON 表示，避免 JavaScript 数值舍入改变 Mock 数据和匹配类型。页面资源编译进 Zig 可执行文件，无需 Node.js 或单独前端服务；修改 `src/web/` 后需要重新构建并重启。

### 管理 API

| 请求 | 行为 |
| --- | --- |
| GET /admin/api/config | 返回 `config`、`generation`、`revision`，响应头包含 ETag |
| PUT /admin/api/config | 请求体为完整配置；必须带 `If-Match: "revision"`，校验、保存并激活 |
| POST /admin/reload | 读取磁盘配置并激活 |

三个接口都使用 `Authorization: Bearer <Token>`。PUT 缺少 If-Match 返回 428，版本过期或发现文件在服务外被修改返回 409，配置无效返回 400，读写文件失败返回 500。失败时不替换内存快照；写入使用同目录临时文件、flush 和原子替换，文件保存成功才切换内存配置。revision 是配置原始字节的 SHA-256，重启后仍能检测内容变化。

在线保存与重载共用串行写锁，普通 Mock 请求在文件 I/O 期间继续使用旧快照。配置目录必须允许服务用户创建临时文件和替换目标文件。手动编辑文件时请先停止在线编辑，原子替换后重载，再刷新页面；外部编辑器不参与服务内的写锁。该机制不承诺断电时文件系统目录元数据的持久性。

## 配置规则

顶层格式为 `version`、`cors`、`routes`。同一个方法和路径只定义一次，在该路由的 `rules` 中描述多个场景，避免重复定义请求校验。

以下是一个独立的最小配置示例：

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
            "query": [{"name": "scenario", "value": "error"}],
            "headers": [{"name": "X-Scenario", "value": "test"}]
          },
          "response": {
            "status": 503,
            "delay_ms": 200,
            "headers": [{"name": "X-Mock", "value": "unavailable"}],
            "body": {"code": 503, "message": "服务暂时不可用"}
          }
        },
        {
          "id": "success",
          "response": {"body": {"users": [{"id": 1, "name": "小明"}]}}
        }
      ]
    }
  ]
}
```

`GET /users?scenario=error` 同时携带 `X-Scenario: test` 时返回 503，否则命中成功规则。

### 匹配语义

- `method` 大写，支持 GET、POST、PUT、PATCH、DELETE、HEAD。OPTIONS 统一用于跨域预检。
- 路径按 httpz 解析后的 URL path 精确比较，不包含查询字符串，不支持通配符、路径参数和自动 HEAD → GET 回退。
- `match.body` 是 JSON 对象：对象递归按子集匹配，数组按长度及元素顺序匹配，标量按 JSON 类型和值比较；数字 `1`、`1.0` 和字符串 `"1"` 不视为同一类型。
- `match.query` 按解码后的参数名和值比较；重复参数使用 httpz 返回的首个值。
- `match.headers` 的名称忽略大小写，值精确匹配；重复同名头使用首个值。
- 所有条件为 AND；省略 `match` 即匹配任意请求。
- 选择优先级最高的匹配规则，默认 `priority: 0`；同优先级选择配置中靠前的规则。
- 不存在路由或没有匹配规则时返回 JSON 404；方法不匹配也返回 404。

### 请求校验和动态文本

路由可定义 `request.body_required` 以及 `request.fields`。字段类型支持 `string`、`integer`（有符号 64 位）、`number`、`boolean`；`required` 与 `default` 不能同时设置。额外的请求字段被保留，不导致校验失败。

有请求体时必须是有效 JSON；未提供请求体时，按空对象处理，除非 `body_required: true`。定义字段校验时，请求体必须是对象。缺少必填字段或类型不符返回 400。字段默认值在规则匹配和模板渲染之前应用。

设置 `response.template: true` 后，在响应 JSON 的字符串值中支持：

- `{{body.name}}`：插入请求中顶层字段值。
- `{{body.age|add:1}}`：对整数加上常量后插入文本；支持负常量。

模板只能引用已声明且必填或有默认值的字段。只替换字符串值，不替换键名；替换结果仍为字符串。插入的文本会经过 JSON 序列化转义，不执行脚本，也不会二次解释请求值中的模板语法。整数运算溢出返回 400，不会使服务崩溃。关闭 `template` 时保留原始文本。

### 响应与限制

`response.body` 必填，可以是任意 JSON 值；默认状态码为 200，默认 Content-Type 为 application/json。字符串响应也按 JSON 字符串编码，第一版不支持原始文本/二进制响应。可以通过 `response.headers` 设置 Content-Type 和自定义响应头，但这不会改变响应体的 JSON 编码方式。

- 状态码范围 200–599；204、205、304 必须配置 `body: null`，实际不发送响应体；HEAD 同样不发送响应体。
- `delay_ms` 范围 0–30000；延迟期间不持有配置锁，但会占用一个 httpz 请求处理线程。
- 请求体最多 1 MiB；配置文件小于 4 MiB；最多 1000 路由、每路由 1000 规则、每响应 32 自定义头。
- `/healthz`、`/admin`、`/admin/*` 为保留路径。
- 未知配置字段、重复路由、重复规则 ID（同一路由内）、错误模板、非法头和协议控制头会使整份配置校验失败。
- Content-Length、Transfer-Encoding、Connection、Keep-Alive、Upgrade、Trailer、Vary 和 Access-Control-* 由服务管理，不允许规则覆盖。

## 热重载

编辑 `MOCK_CONFIG` 指定的文件后调用：

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post `
  -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

成功示例：`{"status":"reloaded","generation":2,"routes":2}`。

重载只读取启动时指定的本地文件，不接受请求上传的配置或文件路径。网页保存使用独立的 PUT 管理接口，也只能写入启动时指定的配置文件。读文件及校验在当前快照之外执行，成功后短暂加锁切换配置。响应体和响应头在释放快照锁前复制到请求内存；旧快照随后释放，正在发送或延迟的响应保持一致。并发重载及在线保存按顺序执行。

文件缺失、JSON 损坏或语义校验失败时返回 400，含 `reason`，旧配置及 generation 保持不变。首次启动加载失败则直接退出。建议先写入同一目录的临时文件，再以原子重命名替换配置，随后调用重载。

`MOCK_ADMIN_TOKEN` 为空时重载接口返回 404；非空但不足 16 字符时拒绝启动；Token 错误返回 401。Token 通过环境变量设置，修改后需要重启，不能通过 JSON 修改。

## 跨域与健康检查

默认允许任意 Origin，不启用携带 Cookie 的跨域凭据模式。可将 `cors.origins` 改为精确 Origin 列表（包含协议和端口，不带末尾斜杠）；空数组关闭跨域，`*` 必须单独使用。

Mock 路径和健康检查的正常/错误响应均按策略添加 CORS 头。OPTIONS 预检验证 Origin、请求方法、请求头，不要求 `Sec-Fetch-Mode`。管理接口不继承公开 CORS 策略。未允许的普通 Origin 请求仍会被服务处理，但没有允许跨域响应头；CORS 是浏览器访问策略，不是 API 鉴权。

`GET /healthz` 返回 `{"status":"ok","generation":1,"routes":2}`。它表示进程可响应且已有有效配置；重载失败后继续报告旧配置健康。支持 HEAD，其他非 OPTIONS 方法返回 405。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| MOCK_HOST | 0.0.0.0 | 监听 IP 地址，支持 IPv4/IPv6，不接受域名 |
| MOCK_PORT | 9080 | 端口 1–65535 |
| MOCK_CONFIG | config/mock.json | 配置路径，相对路径以进程工作目录为准 |
| MOCK_ADMIN_TOKEN | 空 | 管理 Token；为空关闭网页管理及全部管理 API |

## 在线配置请求限流

打开 `/admin/`，选中接口并展开 **请求限流**。填写每个客户端的默认每秒上限；需要为个别 IP 设置不同额度时，在 **客户端 IP 单独上限** 中填写 JSON 对象，例如 `{"192.0.2.10": 20, "2001:db8::1": 0}`。上限为 0–10000 的整数，0 表示不限。点击 **保存并生效** 后，配置写入磁盘，新额度立即用于后续请求。旧配置未设限流时仍为不限。

每个服务进程按 **客户端 IP + 请求方法 + 路径** 分别计算最近一秒内已放行的请求，查询参数不会产生新额度。所有响应场景共用所属路由中该客户端的额度。超限直接返回 JSON `429` 和 `Retry-After: 1`。未知路径、健康检查、管理接口和 OPTIONS 不消耗额度。配置保存不会清空仍在窗口内的计数；降低上限时，已有请求会继续计入，直到过期。

客户端默认使用连接来源 IP。经本仓库示例 Caddy 代理访问时，在同一面板的 **可信代理 IP（所有接口）** 填入 `127.0.0.1`（若使用其他上游连接地址，填写代理实际来源 IP），保存后服务才会读取来自该代理的 `X-Forwarded-For`。部署时保持 Mock 后端仅对代理可达。对于多层代理，最后一层代理应将确认的客户端 IP 作为唯一的 `X-Forwarded-For` 值。详见 [Caddy 反向代理请求头说明](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#headers)。

管理 API 使用同一个 JSON 配置：顶层可选 `"trusted_proxies": ["127.0.0.1"]`，每条路由可选 `"rate_limit": {"requests_per_second": 100, "clients": [{"ip": "192.0.2.10", "requests_per_second": 20}]}`。服务会回收已过期的计数；当计数存储达到容量上限时，无法记录的新请求返回 `503` 和 `Retry-After: 1`。

## 部署到 Linux

推荐结构：`客户端 → Caddy HTTPS → 127.0.0.1:9080 → Mock 服务`。本仓库提供 `deploy/mock.service`、`deploy/Caddyfile`、`deploy/Caddyfile.admin.example` 和 `deploy/mock.env.example`。部署操作在目标服务器执行，需具备管理员权限；这些文件不会自动发布服务。

1. 在匹配服务器架构的构建环境中构建：

   ```sh
   zig build -Doptimize=ReleaseSafe
   ```

   也可从 Windows 交叉编译 Linux x86_64：

   ```powershell
   zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p zig-out/linux
   ```

   此时 Linux 程序为 `zig-out/linux/bin/test_web`。ARM64 服务器需要改用对应目标架构。交叉编译成功不等于已验证目标平台运行，部署前仍需在目标服务器运行测试。

2. 在服务器创建无登录权限的 `mock` 系统用户，安装程序和配置：

   ```sh
   sudo useradd --system --no-create-home --shell /usr/sbin/nologin mock
   sudo install -d -m 0755 /opt/zig-mock /etc/zig-mock
   sudo install -d -o mock -g mock -m 0750 /var/lib/zig-mock
   # 从上传目录执行；交叉编译产物上传后也可命名为 test_web。
   sudo install -m 0755 test_web /opt/zig-mock/test_web
   sudo install -o mock -g mock -m 0640 config/mock.json /var/lib/zig-mock/mock.json
   sudo install -m 0600 deploy/mock.env.example /etc/zig-mock/mock.env
   sudo install -m 0644 deploy/mock.service /etc/systemd/system/zig-mock.service
   ```

   使用 `sudoedit /etc/zig-mock/mock.env` 设置随机 Token；示例留空，默认关闭管理界面。配置放在服务可写的 `/var/lib/zig-mock/` 中，密钥环境文件仍放在仅 root 可读的 `/etc/zig-mock/mock.env`。systemd 仅允许服务写入配置数据目录。

   从上一版部署升级时，将原 `/etc/zig-mock/mock.json` 复制到新数据目录并设置 `mock:mock` 所有权，更新环境文件中的 `MOCK_CONFIG`，安装新的 unit，再执行 daemon-reload 和 restart。

3. 启用服务并检查：

   ```sh
   sudo systemctl daemon-reload
   sudo systemctl enable --now zig-mock
   curl --fail http://127.0.0.1:9080/healthz
   sudo journalctl -u zig-mock -n 50 --no-pager
   ```

   JSON 更新调用 `/admin/reload`；可执行文件或环境变量更新需要 `systemctl restart zig-mock`。第一版重启会中断在途请求，热重载不会。

4. 安装 Caddy 后，将 `deploy/Caddyfile` 中域名替换为实际域名，并将站点块合并到现有 Caddy 配置。将域名 DNS 指向服务器，开放公网 80/443，验证并重载 Caddy：

   ```sh
   sudo caddy validate --config /etc/caddy/Caddyfile
   sudo systemctl reload caddy
   ```

   示例通过 HTTPS 反向代理业务请求，并在公网入口屏蔽 `/admin` 和 `/admin/*`。管理员在服务器本机调用重载，或通过 SSH 隧道访问。后端仅绑定回环地址，9080 无需对公网开放。检查 `https://你的域名/healthz` 和原有两个 POST 接口。

   要通过域名访问网页管理界面，改用 `deploy/Caddyfile.admin.example` 的站点块，该配置也将 `/admin/` 代理到 Zig 服务；浏览器通过 HTTPS 登录，所有管理 API 仍校验 Token。保留默认屏蔽策略时，可执行 `ssh -L 19080:127.0.0.1:9080 user@server`，再打开本机 `http://127.0.0.1:19080/admin/`。

服务不记录请求体和管理 Token，只记录启动、异常和重载失败信息；日志轮转/保留期限由 journald 管理。Mock 调用端没有用户账户、项目隔离、请求记录或调用 Token；管理 Token 保护配置读取、修改和重载。需要限制业务访问时可在反向代理层加访问控制。

## 验证

```powershell
zig fmt --check src/main.zig src/mock.zig src/app.zig build.zig build.zig.zon
zig build test
zig build
python tests/integration.py
node --test tests/json-codec.test.cjs
```

集成测试只使用 Python 标准库，在随机本机端口启动独立进程，使用临时配置并在结束后停止服务，不修改项目的示例配置。可传入可执行文件路径，例如 Linux：`python3 tests/integration.py /opt/zig-mock/test_web`。

## 文件职责

- `src/main.zig`：环境变量、配置启动加载和 HTTP 服务。
- `src/mock.zig`：配置结构与校验、JSON 匹配、请求校验、文本模板。
- `src/app.zig`：请求分发、CORS、健康检查、鉴权和并发重载。
- `src/web/`：无构建依赖的管理页面、规则编辑、无损 JSON 编解码和接口测试面板。
- `config/mock.json`：迁移后的两个接口及其场景。
- `tests/integration.py`：通过真实 HTTP 验证接口、匹配器和重载行为。
