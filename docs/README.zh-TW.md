# Zig Mock 伺服器

[English](../README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **繁體中文**

以 Zig 0.17.0 和 httpz 建構的設定驅動 HTTP Mock 伺服器。透過 JSON 定義路由與回應情境，可重新載入設定檔，或在網頁管理介面儲存並套用。

## 建置與執行

請使用 Zig **0.17.0**。相依套件的版本與雜湊值固定於 `build.zig.zon`。正式環境建置應固定編譯器的發行套件。

執行 Bash 或 PowerShell 建置指令碼，再從專案根目錄啟動服務。

```bash
bash build.sh
```

```powershell
.\build.ps1
```

```sh
zig build run
```

指令碼先檢查 PATH 和本機工具鏈快取，必要時從 Zig 官方發行目錄下載編譯器、驗證 SHA-256，並快取於 `.zig-cache/toolchains/`。自動下載支援 Linux、macOS 和 Windows 的 x86_64、ARM64，以及 Linux 和 Windows 的 x86。Bash 下載需要 `curl`、`sha256sum` 或 `shasum`，以及支援 xz 的 `tar`。Git Bash 使用 `unzip` 解壓縮 Windows 發行套件。PowerShell 指令碼支援 Windows PowerShell 5.1 和 PowerShell 7，非 Windows 平台下載需要支援 xz 的 `tar`。[Zig 官方發行目錄](https://ziglang.org/download/index.json)

兩種指令碼都會執行 `zig build --fetch`，再以預設的 `Debug` 最佳化層級執行 `zig build`。工具鏈和相依套件快取後，即可離線建置。Zig 尚未加入 PATH 時，可在 Windows 執行 `.\zig-out\bin\test_web.exe`，或在 Linux 和 macOS 執行 `./zig-out/bin/test_web`。

服務預設監聽 `0.0.0.0:9080`，本機可透過 `http://127.0.0.1:9080` 存取。`MOCK_ADMIN_TOKEN` 為空或未設定時，服務啟動會產生新權杖，並顯示為 `Generated admin token: …`。若要在重新啟動後使用相同權杖，請在啟動前設定至少 16 位元組的值。服務僅顯示自動產生的權杖。

## 內建範例

管理介面的 **Examples** 資料夾包含以下[範例設定](../config/mock.json)中的路由。JSON 請求使用 `Content-Type: application/json`，XML 請求使用 `Content-Type: application/xml`。

| 功能 | 請求 | 請求本文 | 回應本文 |
| --- | --- | --- | --- |
| JSONPath | `POST /examples/jsonpath` | `{"orders":[{"qty":2,"status":"paid"}]}` | `{"matched":"jsonpath"}` |
| XPath | `POST /examples/xpath` | `<order xmlns="urn:orders"><status>paid</status></order>` | `{"matched":"xpath"}` |
| 查詢參數 | `GET /examples/query?status=paid&source=web` | — | `{"matched":"query"}` |
| 路徑參數 | `GET /examples/items/42` | — | `{"matched":"path","id":42}` |
| 正規表示式 | `POST /examples/regex` | `{"code":"AB-42"}` | `{"matched":"regex"}` |
| JSON 回應範本 | `POST /examples/template/json` | `{"name":"Ada"}` | `{"message":"Hello, Ada!"}` |
| XML 回應範本 | `POST /examples/template/xml` | `<request><name>Ada</name></request>` | `<greeting>Hello, Ada!</greeting>` |

符合範例時會收到 HTTP 200。前五個範例有比對條件，格式正確但不符合條件的請求會收到 404。

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

## 網頁管理介面與唯讀目錄

開啟 `http://127.0.0.1:9080/admin/` 並輸入管理權杖。權杖保留於頁面記憶體，重新整理後需再次連線。預設主題為 Light。瀏覽器會記住 Light、Dark、Cyberpunk 2077、EVA、死亡擱淺或黑神話：悟空的主題選擇。

- 點選目錄按鈕開啟或摺疊側邊欄。窄螢幕下可點選背景、按 Esc 或選取路由來關閉側邊欄。
- 可建立巢狀資料夾、重新命名、移動或刪除空資料夾。透過路由選單或編輯區修改所屬資料夾。搜尋支援路徑片段與完整 HTTP(S) URL，完整 URL 依路徑比對。
- 可新增、複製、編輯或刪除回應情境。請求格式依路由設定，回應格式依情境設定。在情境中設定比對條件、優先順序、狀態碼、延遲、標頭與範本。
- 查詢參數條件接受 JSON 物件、以 `?` 開頭的查詢字串，或含查詢參數的 URL。對於 `/orders/{id}`，可用 `{"id":"42"}` 作為路徑條件。請求本文比對方式可選擇 JSONPath、XPath 或正規表示式。
- 儲存時會將整份設定寫入磁碟並套用。刪除情境會先修改草稿。刪除路由需確認並儲存，也會一併儲存其他草稿變更。每個路由至少需要一個情境。
- 填入情境範例可產生測試 URL、標頭和本文。使用表示式時，請手動填入符合條件的本文。測試會向服務送出真實請求並使用已儲存的規則。GET 和 HEAD 不會傳送本文。測試可取消，逾時為 35 秒，並會阻擋重新導向。只有手動填入測試標頭時才會送出管理權杖。
- 重新整理設定會讀取目前生效的設定，重新載入檔案會讀取設定檔。捨棄草稿前會確認，儲存發生衝突時會保留草稿。

編輯器保留 64 位元整數等 JSON 數值表示方式。網頁資源內嵌在執行檔中，修改前端原始碼後需重新建置並啟動服務。

可直接開啟 `http://127.0.0.1:9080/viewer`，或從管理介面進入。唯讀目錄無須登入，可搜尋路由，查看請求詳細資料、比對條件與回應預覽。`GET /viewer/api/catalog` 會傳回目前生效的目錄。

### 管理 API

| 請求 | 行為 |
| --- | --- |
| `GET /admin/api/config` | 傳回 `config`、`generation`、`revision` 和 ETag。 |
| `PUT /admin/api/config` | 驗證、儲存並套用完整設定。請求需帶 `If-Match: "revision"`。 |
| `POST /admin/reload` | 讀取設定檔並套用。 |

三種操作均需要 `Authorization: Bearer <Token>`。PUT 缺少 `If-Match` 時回傳 428，版本過期或偵測到外部檔案變更時回傳 409，設定無效時回傳 400，I/O 失敗時回傳 500。revision 為檔案原始位元組的 SHA-256。儲存時先寫入同一目錄的暫存檔並將資料同步至磁碟，再以不可分割的操作取代目標檔案，之後切換生效中的設定。服務使用者需要設定目錄的寫入權限。

## 設定參考

最外層 JSON 可包含 `version`、`cors`、`folders`、`trusted_proxies` 和 `routes`。預設版本為 1。資料夾包含 `id`、`name` 和選用的 `parent_id`，最多 16 層。未設定 `folder_id` 的路由顯示於根目錄。資料夾僅影響介面呈現。

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

`GET /users?scenario=error` 帶有 `X-Scenario: test` 時回傳 503。同一路由的其他請求採用成功情境。

### 路由與規則比對

- 路由支援 GET、POST、PUT、PATCH、DELETE 和 HEAD。OPTIONS 處理 CORS 預檢。HEAD 不會自動改用 GET。
- 固定路徑優先於路徑範本。每個 `{name}` 擷取一個非空的路徑片段。名稱以英文字母或底線開頭，可包含數字，同一範本內需唯一。固定片段較多的範本優先，數量相同則依設定順序。同一 HTTP 方法下的路由形狀需唯一。
- `match.path` 會精確比對解碼後的擷取值。服務先依原始斜線分段，再進行百分比解碼。`+` 保留原義。`match.query` 比對解碼後的名稱與值，順序與額外參數不影響結果。同名參數取第一個值。`?flag` 和 `?flag=` 均表示空值。比對時遇到無效的百分比編碼會回傳 400。
- `match.headers` 比對標頭名稱時不區分大小寫，值則精確比對。同名標頭取第一個值。
- JSON 的 `match.body` 依物件子集比對。陣列比較長度和順序，純量區分 `1`、`1.0` 和 `"1"` 等型別。XML 的 `match.body` 是完整文件字串，比對時忽略 UTF-8 BOM、首尾空白與換行符號差異。
- 所有已設定的條件都需符合。優先順序最高的符合規則生效，同順位依設定順序。預設優先順序為 0。找不到路由或符合的規則時，回傳 JSON 404。

### 請求本文表示式

`match.body_expression` 可替代 `match.body`。

| 模式 | 請求格式 | 比對規則 |
| --- | --- | --- |
| `jsonpath` | JSON | 至少選到一個值。設定 `expected.value` 時，至少一個選到的值需完全相等，包含 JSON 型別。 |
| `xpath` | XML | 依 XPath 1.0 的布林值判斷。設定字串型別的 `expected.value` 時，比對任一節點的字串值或純量的 XPath 字串表示。 |
| `regex` | JSON 或 XML | 使用 RE2 風格語法搜尋原始請求本文，`^` 與 `$` 可限制起訖位置。 |

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

用 `"expected": {"value": null}` 比對 JSON null。JSONPath 支援屬性、陣列選擇器、遞迴搜尋和篩選。JSONPath 的 `match()` 和 `search()` 已停用，請使用獨立的正規表示式模式。

XPath 支援述詞與布林表示式，例如 `/order/item[@sku='paid']` 或 `count(/order/item) > 0`。使用 `"namespaces": [{"prefix":"o","uri":"urn:orders"}]` 綁定前綴，再寫 `/o:order/o:item/@sku`。預設命名空間也需在表示式中使用已綁定的前綴。

表示式會在載入或儲存時編譯，長度上限為 1024 位元組。空本文不符合表示式。服務先驗證本文格式，再執行比對。JSONPath 使用已套用欄位預設值的 JSON，正規表示式使用原始位元組。JSONPath 和 XPath 每次請求使用 16 MiB 的求值工作區。JSONPath 支援最多 128 層 JSON 巢狀結構。超出求值限制時回傳 400。

### 請求驗證與回應範本

`request.format` 預設為 `json`。`request.body_required` 會拒絕沒有本文的請求。可省略的 JSON 本文視為空物件。JSON 欄位驗證需要物件，支援 `string`、`integer`（帶正負號的 64 位元整數）、`number` 和 `boolean`。欄位可設為必填或提供預設值。額外欄位會保留，預設值在比對和產生回應前套用。本文或欄位無效時回傳 400。

啟用 `response.template: true` 後，`{{body.name}}` 會讀取 JSON 最外層欄位，或 XML 根元素下 `name` 子元素的文字。引用的 JSON 欄位需為必填或有預設值。XML 支援 `{{body.customer.name}}` 等巢狀路徑，以及 `{{body.@id}}` 和 `{{body.customer.@id}}` 等屬性引用。每一層選取名稱與命名空間前綴完全符合的第一個子元素，並區分大小寫。元素值包含所有後代的文字。`{{body.age|add:1}}` 會加上整數常數。

可在 JSON 字串、XML 元素文字或一般 XML 屬性值中插入資料。服務依回應格式跳脫插入內容，並驗證產生的 XML。缺少引用值、`add` 遇到非整數或整數溢位時回傳 400。涉及 XML 的範本動態文字上限為 4 MiB。**Examples** 資料夾的兩個範本路由分別示範 JSON 和 XML。

### 回應與限制

`response.body` 為必填，預設狀態碼是 200。回應預設為 JSON，使用 `application/json`，字串也以 JSON 編碼。XML 回應傳送 UTF-8 XML，使用 `application/xml; charset=utf-8`。可用自訂 Content-Type 標頭覆寫預設值，本文編碼由回應格式決定。

- 狀態碼為 200 至 599。204、205 和 304 需要 `body: null`，與 HEAD 一樣不傳送本文。
- `delay_ms` 為 0 至 30000。延遲時會釋放設定鎖定，由 httpz 工作執行緒等待。
- 請求本文最多 1 MiB，設定檔需小於 4 MiB。最多 1000 個路由、每路由 1000 條規則，以及每個回應 32 個自訂標頭。
- XML 必須是格式正確的 UTF-8 XML，最多巢狀 128 層。含 DTD 的文件會遭拒絕。
- `/healthz`、`/admin`、`/admin/*`、`/viewer` 和 `/viewer/*` 為保留路徑。未知欄位、重複的路由形狀或路由內的規則 ID、無效範本或禁止的標頭都會讓設定失效。Content-Length、Transfer-Encoding、Connection、Keep-Alive、Upgrade、Trailer、Vary 和 Access-Control-* 由服務管理。

## 重新載入、CORS 與健康檢查

以不可分割的操作取代 `MOCK_CONFIG` 所指的檔案後呼叫重新載入。若使用自動產生的權杖，請將啟動時顯示的值填入 Bearer 標頭。

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

重新載入僅讀取已設定的本機檔案，目前管理權杖繼續有效。權杖缺少或無效時回傳 401。

重新載入成功會回傳 `status`、`generation` 和 `routes`。檔案不存在或設定無效時回傳 400 和 `reason`，目前設定繼續生效。啟動時設定無效會結束服務。重新載入和線上儲存依序執行，正在處理的請求在切換設定期間會保留其回應資料。

預設允許所有 Origin，服務不啟用跨來源憑證模式。`cors.origins` 可填入包含通訊協定與連接埠、且不含尾端斜線的精確 Origin 清單。空陣列停用 CORS。`*` 必須單獨使用。預檢會驗證 Origin、方法和標頭。管理與目錄路徑採用個別原則。來自未獲允許 Origin 的一般請求仍可送達，但回應不含 CORS 許可標頭。

`GET /healthz` 會回報 `status: "ok"`、目前生效的 `generation` 和 `routes` 數量。重新載入失敗時仍回報目前的有效設定。支援 HEAD，其他方法除 OPTIONS 外回傳 405。

## 環境變數

| 變數 | 預設值 | 用途 |
| --- | --- | --- |
| `MOCK_HOST` | `0.0.0.0` | IPv4 或 IPv6 監聽位址。 |
| `MOCK_PORT` | `9080` | 監聽連接埠 1 至 65535。 |
| `MOCK_CONFIG` | `config/mock.json` | 設定檔路徑。相對路徑以程序的工作目錄為準。 |
| `MOCK_ADMIN_TOKEN` | 自動產生 | 選用的固定管理權杖，至少 16 位元組。 |

## 請求速率限制

在管理介面展開路由的請求速率限制。設定每個用戶端每秒可發出的請求數，也可指定各 IP 的限制，例如 `{"192.0.2.10":20,"2001:db8::1":0}`。值為 0 至 10000 的整數，0 代表無上限。路由設定欄位為 `rate_limit.requests_per_second` 和 `rate_limit.clients`。

每個程序依用戶端 IP、HTTP 方法和設定中的路由，統計最近一秒內允許的請求。同一路由的路徑與查詢參數變化及回應情境會共用用戶端配額。超出上限時回傳 429 和 `Retry-After: 1`。計數容量不足以記錄新請求時，回傳 503 和相同標頭。儲存後新限制立即生效，仍在計算視窗內的計數會保留。

未知路由、健康檢查、管理及唯讀目錄請求與 OPTIONS 均不消耗配額。

預設用連線來源 IP 識別用戶端。設定 `trusted_proxies`，例如 `["127.0.0.1"]`，可接受指定代理的 `X-Forwarded-For`。此設定下，後端應僅允許信任的代理存取。多層代理中，最後一個代理應轉送唯一且已驗證的用戶端位址。[Caddy 反向代理標頭](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#headers)

## 使用 Docker 部署

使用 Docker 建置 Linux 映像檔。映像檔以 Nginx 作為 HTTP 入口，Zig Mock 監聽容器內的回送位址。

```sh
docker build -t zig-mock .
docker run -d --name zig-mock -p 127.0.0.1:18080:8080 -e MOCK_ADMIN_TOKEN -v zig-mock-data:/var/lib/zig-mock zig-mock
```

- 修改 `18080` 可指定主機連接埠。Nginx 在容器內監聽 `8080`。若要將 Mock 的內部連接埠從 `9080` 改成其他值，可加入 `-e MOCK_PORT=19080`。
- `-e MOCK_ADMIN_TOKEN` 會傳入目前終端機環境中的權杖，也可以改用 `--env-file`。自訂權杖至少需要 16 位元組。權杖未設定或為空時，服務會自動產生，可透過 `docker logs zig-mock` 查看。
- 資料卷缺少 `mock.json` 時，服務會從 `config/mock.json` 初始化。更換容器時沿用該資料卷即可保留已儲存的規則。若要依 Nginx 看到的用戶端 IP 個別限制速率，請在管理介面的**信任的代理 IP**中加入 `127.0.0.1` 並儲存。

可開啟[管理介面](http://127.0.0.1:18080/admin)、[唯讀目錄](http://127.0.0.1:18080/viewer)及[健康檢查](http://127.0.0.1:18080/healthz)。範例將 HTTP 連接埠繫結至主機的回送位址。若要對外提供 HTTPS，可使用下方的反向代理範例，並將上游指向主機上對應的連接埠。

## 部署到 Linux

部署範例採用 `用戶端 → Caddy 或 Nginx（HTTPS）→ 127.0.0.1:9080 → Mock 伺服器`。請在目標伺服器上以管理員權限執行部署指令。

依伺服器的架構建置。第二條指令會交叉編譯 Linux x86_64 執行檔至 `zig-out/linux/bin/test_web`。ARM64 需選擇對應目標，並在目標主機驗證執行檔。

```sh
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p zig-out/linux
```

上傳執行檔與專案設定。從上傳目錄建立無登入權限的系統使用者並安裝檔案。

```sh
sudo useradd --system --no-create-home --shell /usr/sbin/nologin mock
sudo install -d -m 0755 /opt/zig-mock /etc/zig-mock
sudo install -d -o mock -g mock -m 0750 /var/lib/zig-mock
sudo install -m 0755 test_web /opt/zig-mock/test_web
sudo install -o mock -g mock -m 0640 config/mock.json /var/lib/zig-mock/mock.json
sudo install -m 0600 deploy/mock.env.example /etc/zig-mock/mock.env
sudo install -m 0644 deploy/mock.service /etc/systemd/system/zig-mock.service
```

如需固定權杖，可在 `/etc/zig-mock/mock.env` 設定。服務可寫入 `/var/lib/zig-mock/`，環境變數檔僅 root 可讀。

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now zig-mock
curl --fail http://127.0.0.1:9080/healthz
sudo journalctl -u zig-mock -n 50 --no-pager
```

若現有 systemd 服務使用 `/etc/zig-mock/mock.json`，請將檔案複製至 `/var/lib/zig-mock/`、將擁有者設為 `mock:mock` 並更新 `MOCK_CONFIG`，再重新啟動。

修改 JSON 後可呼叫重新載入。修改執行檔或環境變數後執行 `sudo systemctl restart zig-mock`。啟動訊息與自動產生的權杖可從 journald 查看。

### Caddy

替換 [Caddy 範例](../deploy/Caddyfile)中的網域，並將站台區塊加入伺服器的 Caddy 設定。將 DNS 指向伺服器，開放 80 和 443 連接埠。

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

預設反向代理會轉送 Mock 請求並封鎖外部對 `/admin` 和 `/viewer` 的存取。使用 `/healthz` 和一個範例路由檢查 HTTPS。可透過 `ssh -L 19080:127.0.0.1:9080 user@server` 從本機 19080 連接埠存取管理介面與目錄，或使用[替代 Caddy 範例](../deploy/Caddyfile.admin.example)透過 HTTPS 提供存取。管理 API 仍需要權杖，可連上網域的訪客能檢視目錄。

### Nginx

對外提供 Mock 端點時，使用[預設 Nginx 設定](../deploy/nginx.conf.example)。此設定會封鎖 `/admin`、`/viewer` 及其子路徑。若要透過 HTTPS 存取這兩個頁面，請改用[管理版設定](../deploy/nginx.admin.conf.example)。管理 API 需要權杖，唯讀目錄無須登入。

將網域 DNS 指向伺服器，開放 80 和 443 連接埠，並取得該網域的 TLS 憑證。只安裝其中一份設定，放在 Nginx 的 `http` 區塊所包含的目錄中，例如 `/etc/nginx/conf.d/`。修改兩處 `server_name mock.example.com`，將 `ssl_certificate` 和 `ssl_certificate_key` 指向實際憑證鏈與私密金鑰。

```sh
# Use deploy/nginx.admin.conf.example as the source for the admin variant.
sudo install -m 0644 deploy/nginx.conf.example /etc/nginx/conf.d/zig-mock.conf
sudoedit /etc/nginx/conf.d/zig-mock.conf
sudo nginx -t
sudo systemctl reload nginx
curl --fail https://mock.example.com/healthz
```

兩份設定都將 HTTP 重新導向至 HTTPS，轉送時保留原始路徑編碼與查詢字串。Nginx 會以觀察到的用戶端位址覆寫傳入的 `X-Forwarded-For`。若要在本機代理後依用戶端限流，請在 Mock 設定加入 `"trusted_proxies": ["127.0.0.1"]` 並重新載入。[Nginx 代理模組](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)

服務不會記錄請求本文或手動設定的權杖。如需限制 Mock 存取，可在反向代理設定存取控制。

## 驗證

```sh
zig fmt --check src/main.zig src/mock.zig src/app.zig src/body_match.zig src/jsonpath_regex.zig build.zig build.zig.zon
zig build test
zig build
python tests/integration.py
node --test tests/json-codec.test.cjs
```

Python 整合測試使用暫存設定與隨機本機連接埠。可提供執行檔路徑，例如 `python3 tests/integration.py /opt/zig-mock/test_web`。
