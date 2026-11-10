# Zig 在线 Mock 服务

基于 Zig 0.17.0 + httpz 的配置驱动 HTTP Mock 服务。修改 JSON 并调用重载接口，即可增加、修改或删除接口，无需重新编译。

已迁移原有 `POST /hello/test` 和 `POST /order`，保留姓名/年龄动态响应、默认字段、订单必填字段校验和银联失败场景。业务规则位于 `config/mock.json`，不再注册原来的硬编码 handler。

## 本地运行

使用与本项目兼容的 Zig **0.17.0** 工具链；依赖提交和 hash 已固定在 `build.zig.zon`。生产构建应固定同一份编译器发行包，不要在部署时自动升级。

可以先用对应脚本编译：

```bash
bash build.sh
```

```powershell
.\build.ps1
```

脚本会优先使用 PATH 上的 Zig 0.17.0，再检查项目内的工具链缓存。都没有时，会从 [Zig 官方发行目录](https://ziglang.org/download/index.json) 下载、校验 SHA-256，并缓存到 `.zig-cache/toolchains/`。自动下载支持 Linux、macOS 和 Windows 的 x86_64、ARM64，以及 Linux 和 Windows 的 x86。Bash 下载分支需要 `curl`、`sha256sum` 或 `shasum`，以及支持 xz 的 `tar`（Git Bash 下使用 `unzip`）。PowerShell 脚本可在 Windows PowerShell 5.1 或 PowerShell 7 运行；非 Windows 平台的下载分支需要支持 xz 的 `tar`。

两个脚本都先运行 `zig build --fetch` 检查和获取项目依赖，再直接运行 `zig build`，使用默认优化级别 `Debug`。首次下载工具链或缺失依赖时需要网络；工具链和依赖齐备后可离线构建。产物位于 `zig-out/bin/`。

启动服务时，在项目根目录运行：

```powershell
zig build run
```

如果 Zig 由脚本下载且尚未加入 PATH，可以直接运行产物：Windows 执行 `.\zig-out\bin\test_web.exe`，Linux 或 macOS 执行 `./zig-out/bin/test_web`。

默认监听 `0.0.0.0:9080`，本机通过 `http://127.0.0.1:9080` 调用。

未设置 `MOCK_ADMIN_TOKEN` 或其值为空时，每次启动会生成新的管理 Token，在终端打印为 `Generated admin token: …`。如果需要在重启之间使用同一个 Token，可在启动前设置 `MOCK_ADMIN_TOKEN`（至少 16 字符）；手动设置的 Token 不会打印。

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

启动后打开 `http://127.0.0.1:9080/admin/`，输入终端生成的 Token，或启动前设置的 `MOCK_ADMIN_TOKEN`。管理页通过 Bearer Token 调用管理 API。Token 只保留在当前页面内存中，不写入浏览器存储；刷新页面需重新连接。

右上角可切换 Light、Dark、Cyberpunk 2077、EVA、死亡搁浅和黑神话：悟空主题。偏好保存在当前浏览器，刷新后仍可使用。首次打开默认为 Light。

点击顶部的 **目录** 可展开或折叠接口侧栏。窄屏会从左侧弹出侧栏，点击遮罩、按 Esc 或选择接口即可收起。

- 左侧可新建目录并选择上级目录，点击目录名称展开或折叠。通过目录旁的「⋯」重命名、移动目录或删除空目录。点击接口旁的 **移动** 可选择目标目录或移回根目录，也可以在编辑区修改 **所属目录**。点击 **保存并生效** 后保存目录结构和接口归属。
- 搜索框支持 URL 路径片段或完整 HTTP(S) URL。完整 URL 按路径匹配，忽略域名、查询参数和片段。结果显示接口所在目录，清空搜索框可返回目录树。
- 每个接口可新增、复制、修改或删除响应场景，设置优先级、匹配条件、状态码、延迟、模板、响应体和响应头。**请求体格式** 按接口设置，**响应体格式** 按场景设置，均支持 JSON 和 XML。
- 在响应场景的 **匹配条件 → URL 查询参数匹配** 中填写 `?status=paid&source=web`、带查询参数的 URL 或 JSON 对象。粘贴 URL 时只提取查询参数，接口路径在上方单独设置。测试面板的 **填入场景示例** 会生成相应的查询字符串。
- 在 **接口路径** 填写 `/orders/{id}`，然后在 **匹配条件 → URL 路径参数匹配** 填写 `{"id":"42"}`。测试面板的 **填入场景示例** 会把占位符替换为匹配值，未限制的参数填入 `demo`。
- 点击 **保存并生效** 后整份配置写入 `MOCK_CONFIG` 文件并立即生效。JSON 请求体匹配填写 `null` 表示不限，`{}` 表示必须是对象但不限字段。XML 请求体匹配填写完整文档，留空表示不限。
- 删除场景先修改草稿，需点击保存；删除接口会二次确认并立即保存，也会保存其他接口已经编辑的草稿。每个接口至少一个场景，可删除最后一个接口得到空配置。
- 右侧 **填入场景示例** 会根据 JSON 字段和匹配条件构造请求，或填入 XML 文档及对应的 Content-Type。**发送请求** 调用当前服务真实接口，显示 HTTP 状态码、耗时、响应头和响应体；不自动保存草稿。
- 测试只允许当前服务的非管理路径；管理 Token 不自动加入测试请求。可以手动填写业务 Authorization 请求头。GET/HEAD 不发送请求体；请求支持取消及 35 秒超时；不自动跟随重定向。
- **刷新配置** 读取当前内存配置，**重载文件** 从磁盘加载。存在草稿时会确认；保存冲突时保留草稿，不覆盖其他人的修改。

浏览器编辑器保留 64 位整数、浮点数和科学计数法的 JSON 表示，避免 JavaScript 数值舍入改变 Mock 数据和匹配类型。页面资源编译进 Zig 可执行文件，无需 Node.js 或单独前端服务；修改 `src/web/` 后需要重新构建并重启。

可直接打开 `http://127.0.0.1:9080/viewer`，或点击管理页顶部的 **只读视图**。页面无需登录，可按路径搜索接口，查看请求体字段、规则匹配条件、HTTP 状态码、响应头和响应体预览。页面通过 `GET /viewer/api/catalog` 读取当前生效的接口目录。

### 管理 API

| 请求 | 行为 |
| --- | --- |
| GET /admin/api/config | 返回 `config`、`generation`、`revision`，响应头包含 ETag |
| PUT /admin/api/config | 请求体为完整配置；必须带 `If-Match: "revision"`，校验、保存并激活 |
| POST /admin/reload | 读取磁盘配置并激活 |

三个接口都使用 `Authorization: Bearer <Token>`。PUT 缺少 If-Match 返回 428，版本过期或发现文件在服务外被修改返回 409，配置无效返回 400，读写文件失败返回 500。失败时不替换内存快照；写入使用同目录临时文件、flush 和原子替换，文件保存成功才切换内存配置。revision 是配置原始字节的 SHA-256，重启后仍能检测内容变化。

在线保存与重载共用串行写锁，普通 Mock 请求在文件 I/O 期间继续使用旧快照。配置目录必须允许服务用户创建临时文件和替换目标文件。手动编辑文件时请先停止在线编辑，原子替换后重载，再刷新页面；外部编辑器不参与服务内的写锁。该机制不承诺断电时文件系统目录元数据的持久性。

## 配置规则

顶层格式包含 `version`、`cors` 和 `routes`。可选的 `folders` 数组用于管理界面，每项包含 `id`、`name` 和可选的 `parent_id`。路由通过可选的 `folder_id` 指定目录，旧配置中的接口直接显示在根目录。目录最多支持 16 层。目录归属只影响界面展示，接口仍按原有请求方法和路径匹配。同一个方法和路径只定义一次，在该路由的 `rules` 中描述多个场景。

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
- 路径按 HTTP URL 的 path 匹配，查询字符串由 `match.query` 单独处理。路径支持固定段和 `{name}` 参数段。每个参数匹配一个非空路径段，名称以英文字母或下划线开头，可包含英文字母、数字和下划线，同一模板内名称唯一。固定路径优先，其次选固定段最多的模板，同等具体程度按配置顺序选择。同一方法下形状相同的模板不能重复定义。HEAD 无自动 GET 回退。
- `match.path` 按捕获参数的解码值精确比较，例如 `[{"name":"id","value":"42"}]`。可只限制部分参数。路径先按原始斜线分段，再对捕获值做百分号解码，`+` 保留原义。非法参数编码返回 400。
- JSON 请求的 `match.body` 是 JSON 对象：对象递归按子集匹配，数组按长度及元素顺序匹配，标量按 JSON 类型和值比较；数字 `1`、`1.0` 和字符串 `"1"` 不视为同一类型。XML 请求的 `match.body` 是 XML 文档字符串，使用全文匹配。
- `match.query` 按解码后的参数名和值精确比较。列出的参数须全部匹配，顺序无关，额外参数允许存在。重复参数取首个值，`?flag` 与 `?flag=` 均表示空值。匹配时遇到非法百分号编码返回 400。
- `match.headers` 的名称忽略大小写，值精确匹配；重复同名头使用首个值。
- 所有条件为 AND；省略 `match` 即匹配任意请求。
- 选择优先级最高的匹配规则，默认 `priority: 0`；同优先级选择配置中靠前的规则。
- 不存在路由或没有匹配规则时返回 JSON 404；方法不匹配也返回 404。

### 请求校验和动态文本

路由可定义 `request.body_required` 以及 `request.fields`。字段类型支持 `string`、`integer`（有符号 64 位）、`number`、`boolean`；`required` 与 `default` 不能同时设置。额外的请求字段被保留，不导致校验失败。

默认 `request.format` 为 `json`。有请求体时必须是有效 JSON；未提供请求体时，按空对象处理，除非 `body_required: true`。定义字段校验时，请求体必须是对象。缺少必填字段或类型不符返回 400。字段默认值在规则匹配和模板渲染之前应用。

设置 `response.template: true` 后，可在 JSON 响应的字符串值或 XML 响应的元素文本和属性值中引用请求数据：

- `{{body.name}}`：插入 JSON 顶层字段值，或 XML 根元素下 `name` 元素的文本。
- `{{body.age|add:1}}`：对整数加上常量后插入文本；支持负常量。

JSON 请求字段需声明为必填或有默认值，且字段名按原样匹配。XML 请求可用点号访问嵌套元素，例如 `{{body.customer.name}}`，用末尾的 `@属性名` 访问属性，例如 `{{body.@id}}` 或 `{{body.customer.@id}}`。每一级同名子元素取第一个，元素值为其中的文本，包含其子元素的文本。XML 元素名和属性名区分大小写，使用文档中的命名空间前缀。

JSON 响应通过 JSON 序列化转义插入值。XML 响应自动转义 XML 特殊字符，并检查生成的文档。XML 模板占位符可出现在元素文本或普通属性值中。请求缺少被引用的值、`add` 遇到非整数或溢出时返回 400。关闭 `template` 时保留原始文本。

### 响应与限制

`response.body` 必填，默认状态码为 200。默认 `response.format` 为 `json`，响应体可以是任意 JSON 值，字符串也按 JSON 编码，默认 Content-Type 为 `application/json`。设为 `xml` 后，响应体按原始 XML 字符串发送，默认 Content-Type 为 `application/xml; charset=utf-8`。可以通过 `response.headers` 覆盖 Content-Type，正文编码由 `response.format` 决定。

- 状态码范围 200–599；204、205、304 必须配置 `body: null`，实际不发送响应体；HEAD 同样不发送响应体。
- `delay_ms` 范围 0–30000；延迟期间不持有配置锁，但会占用一个 httpz 请求处理线程。
- 请求体最多 1 MiB；配置文件小于 4 MiB；最多 1000 路由、每路由 1000 规则、每响应 32 自定义头。
- `/healthz`、`/admin`、`/admin/*`、`/viewer`、`/viewer/*` 为保留路径。
- 未知配置字段、重复路由、重复规则 ID（同一路由内）、错误模板、非法头和协议控制头会使整份配置校验失败。
- Content-Length、Transfer-Encoding、Connection、Keep-Alive、Upgrade、Trailer、Vary 和 Access-Control-* 由服务管理，不允许规则覆盖。

### XML 请求与响应示例

配置文件依然使用 JSON。请求和响应的格式可独立选择，以下路由接收 XML 并返回 XML。

```json
{
  "routes": [
    {
      "method": "POST",
      "path": "/xml/order",
      "request": { "format": "xml", "body_required": true },
      "rules": [
        {
          "id": "accepted",
          "response": {
            "format": "xml",
            "template": true,
            "body": "<result id=\"{{body.@id}}\">{{body.customer.name}}</result>"
          }
        }
      ]
    }
  ]
}
```

发送 `<order id="7"><customer><name>小明</name></customer></order>`，服务返回 `<result id="7">小明</result>`。在管理页选择 XML 响应格式后，勾选 **启用动态模板**，再在测试面板填入包含对应元素或属性的 XML 请求。

XML 使用 UTF-8，最多嵌套 128 层。请求体和配置中的 XML 都会检查文档格式，含 DTD 的文档会被拒绝。全文匹配忽略 UTF-8 BOM、首尾空白和换行符差异，文档内的其他文本须一致。XML 请求可设置 `body_required`。涉及 XML 的模板渲染有 4 MiB 的动态文本预算。

## 热重载

编辑 `MOCK_CONFIG` 指定的文件后调用：

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post `
  -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

成功示例：`{"status":"reloaded","generation":2,"routes":2}`。

重载只读取启动时指定的本地文件，不接受请求上传的配置或文件路径。网页保存使用独立的 PUT 管理接口，也只能写入启动时指定的配置文件。读文件及校验在当前快照之外执行，成功后短暂加锁切换配置。响应体和响应头在释放快照锁前复制到请求内存；旧快照随后释放，正在发送或延迟的响应保持一致。并发重载及在线保存按顺序执行。

文件缺失、JSON 损坏或语义校验失败时返回 400，含 `reason`，旧配置及 generation 保持不变。首次启动加载失败则直接退出。建议先写入同一目录的临时文件，再以原子重命名替换配置，随后调用重载。

若使用自动生成的 Token，请将终端输出的值填入上述命令的 Bearer 请求头。Token 错误或缺失时返回 401；配置文件重载不会更换当前 Token。

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
| MOCK_ADMIN_TOKEN | 自动生成 | 可选固定管理 Token，至少 16 字符；未设置或为空时，每次启动生成并打印新值 |

## 在线配置请求限流

打开 `/admin/`，选中接口并展开 **请求限流**。填写每个客户端的默认每秒上限；需要为个别 IP 设置不同额度时，在 **客户端 IP 单独上限** 中填写 JSON 对象，例如 `{"192.0.2.10": 20, "2001:db8::1": 0}`。上限为 0–10000 的整数，0 表示不限。点击 **保存并生效** 后，配置写入磁盘，新额度立即用于后续请求。旧配置未设限流时仍为不限。

每个服务进程按 **客户端 IP + 请求方法 + 配置中的路由路径** 分别计算最近一秒内已放行的请求。属于同一路由的查询参数、路径参数和响应场景共用该客户端的额度。超限直接返回 JSON `429` 和 `Retry-After: 1`。未知路径、健康检查、管理接口和 OPTIONS 不消耗额度。配置保存不会清空仍在窗口内的计数；降低上限时，已有请求会继续计入，直到过期。

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

   如需固定 Token，可使用 `sudoedit /etc/zig-mock/mock.env` 设置；留空时从 systemd 启动日志查看生成的 Token。配置放在服务可写的 `/var/lib/zig-mock/` 中，密钥环境文件仍放在仅 root 可读的 `/etc/zig-mock/mock.env`。systemd 仅允许服务写入配置数据目录。

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

   示例通过 HTTPS 反向代理业务请求，并在公网入口屏蔽 `/admin`、`/viewer` 及其子路径。管理员在服务器本机调用重载，或通过 SSH 隧道访问。后端仅绑定回环地址，9080 无需对公网开放。检查 `https://你的域名/healthz` 和原有两个 POST 接口。

   要通过域名访问管理页和只读页，改用 `deploy/Caddyfile.admin.example` 的站点块。该示例将两者一并代理到 Zig 服务，管理 API 校验 Token，只读视图向可访问该域名的访客提供 Mock 接口和规则。保留默认屏蔽策略时，可执行 `ssh -L 19080:127.0.0.1:9080 user@server`，再打开本机 `http://127.0.0.1:19080/admin/` 或 `http://127.0.0.1:19080/viewer`。

服务不记录请求体或手动设置的 Token；自动生成的 Token 只在启动时打印一次。systemd 会收集启动输出，日志轮转和保留期限由 journald 管理。Mock 调用端没有用户账户、项目隔离、请求记录或调用 Token。需要限制业务访问时可在反向代理层加访问控制。

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
