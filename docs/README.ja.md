# Zig モックサーバー

[English](../README.md) · [简体中文](README.zh-CN.md) · **日本語** · [Français](README.fr.md) · [Deutsch](README.de.md) · [繁體中文](README.zh-TW.md)

Zig 0.17.0 と httpz で構築した、設定駆動の HTTP モックサーバーです。JSON でルートとレスポンスシナリオを定義し、設定ファイルの再読み込みや Web 管理画面からの保存で反映できます。

## ビルドと起動

Zig **0.17.0** を使用します。依存パッケージのリビジョンとハッシュは `build.zig.zon` に固定されています。本番用ビルドではコンパイラーの配布パッケージも固定してください。

Bash または PowerShell のビルドスクリプトを実行し、プロジェクトのルートから起動します。

```bash
bash build.sh
```

```powershell
.\build.ps1
```

```sh
zig build run
```

スクリプトは PATH とローカルのツールチェーンキャッシュを確認します。必要に応じて Zig 公式の配布先からダウンロードし、SHA-256 を検証して `.zig-cache/toolchains/` に保存します。自動ダウンロードは Linux、macOS、Windows の x86_64 と ARM64、および Linux と Windows の x86 に対応します。Bash でのダウンロードには `curl`、`sha256sum` または `shasum`、xz 対応の `tar` が必要です。Git Bash では Windows 向けアーカイブに `unzip` を使用します。PowerShell スクリプトは Windows PowerShell 5.1 または PowerShell 7 で動作し、Windows 以外でのダウンロードには xz 対応の `tar` が必要です。[Zig 公式リリース一覧](https://ziglang.org/download/index.json)

両スクリプトは `zig build --fetch` の後、既定の最適化レベル `Debug` で `zig build` を実行します。ツールチェーンと依存パッケージをキャッシュした後はオフラインでビルドできます。Zig が PATH にない場合は、Windows では `.\zig-out\bin\test_web.exe`、Linux と macOS では `./zig-out/bin/test_web` を直接実行できます。

既定の待ち受けアドレスは `0.0.0.0:9080` です。ローカルでは `http://127.0.0.1:9080` を使用します。`MOCK_ADMIN_TOKEN` が空または未設定の場合、起動時に新しい管理トークンが生成され、`Generated admin token: …` として表示されます。再起動後も同じトークンを使うには、起動前に 16 バイト以上の値を設定します。表示されるのは自動生成したトークンのみです。

## 同梱のサンプル

[サンプル設定](../config/mock.json)の以下のルートは、管理画面の **Examples** フォルダーにまとまっています。JSON には `Content-Type: application/json`、XML には `Content-Type: application/xml` を指定します。

| 機能 | リクエスト | リクエストボディ | レスポンスボディ |
| --- | --- | --- | --- |
| JSONPath | `POST /examples/jsonpath` | `{"orders":[{"qty":2,"status":"paid"}]}` | `{"matched":"jsonpath"}` |
| XPath | `POST /examples/xpath` | `<order xmlns="urn:orders"><status>paid</status></order>` | `{"matched":"xpath"}` |
| クエリパラメーター | `GET /examples/query?status=paid&source=web` | — | `{"matched":"query"}` |
| パスパラメーター | `GET /examples/items/42` | — | `{"matched":"path","id":42}` |
| 正規表現 | `POST /examples/regex` | `{"code":"AB-42"}` | `{"matched":"regex"}` |
| JSON レスポンステンプレート | `POST /examples/template/json` | `{"name":"Ada"}` | `{"message":"Hello, Ada!"}` |
| XML レスポンステンプレート | `POST /examples/template/xml` | `<request><name>Ada</name></request>` | `<greeting>Hello, Ada!</greeting>` |

サンプルに一致すると HTTP 200 が返ります。最初の 5 件にはマッチ条件があり、正常なリクエストでも条件に一致しない場合は 404 が返ります。

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

## Web 管理画面と読み取り専用カタログ

`http://127.0.0.1:9080/admin/` を開き、管理トークンを入力します。トークンはページのメモリーに保持されるため、ブラウザーで再読み込みした後は再接続が必要です。既定のテーマは Light です。Light、Dark、Cyberpunk 2077、EVA、DEATH STRANDING、黒神話：悟空から選択でき、ブラウザーが設定を記憶します。

- フォルダーボタンでサイドバーを開閉します。狭い画面では、背景をクリックするか、Esc を押すか、ルートを選択すると閉じます。
- フォルダーの階層化、名前変更、移動、空フォルダーの削除ができます。ルートはメニューまたは編集欄から所属フォルダーを変更できます。パスの一部や完全な HTTP(S) URL で検索でき、完全な URL はパスで照合されます。
- レスポンスシナリオを作成、複製、編集、削除できます。リクエスト形式はルートごとに、レスポンス形式はシナリオごとに設定します。マッチ条件、優先順位、ステータス、遅延、ヘッダー、テンプレートはシナリオ内で設定します。
- クエリ条件は JSON オブジェクト、`?` で始まるクエリ文字列、またはクエリ付き URL で入力できます。`/orders/{id}` のようなルートでは、`{"id":"42"}` をパスの条件に指定できます。ボディの照合方式には JSONPath、XPath、正規表現を選択できます。
- 保存すると設定全体がディスクに書き込まれ、適用されます。シナリオの削除は下書きに反映されます。ルートの削除では確認後に、下書きのほかの変更も含めて保存します。各ルートには少なくとも 1 件のシナリオが必要です。
- シナリオのサンプルを入力すると、テスト用 URL、ヘッダー、ボディが設定されます。式を使用するルールでは条件に合うボディを入力してください。テストは保存済みのルールで実際のリクエストを処理します。GET と HEAD はボディを送信しません。リクエストはキャンセルでき、タイムアウトは 35 秒です。リダイレクトはブロックされ、管理トークンはテストヘッダーに明示的に入力した場合に送信されます。
- 更新は有効な設定を読み取り、ファイルの再読み込みは設定ファイルを読み込みます。下書きの破棄前に確認があり、保存が競合した場合は下書きが残ります。

エディターは 64 ビット整数などの JSON 数値表現を保持します。Web リソースは実行ファイルに組み込まれます。フロントエンドのソースを変更した場合は再ビルドと再起動が必要です。

`http://127.0.0.1:9080/viewer` を直接開くか、管理画面から移動します。読み取り専用カタログではログインなしで、ルート検索、リクエスト詳細、マッチ条件、レスポンスのプレビューを利用できます。`GET /viewer/api/catalog` は有効なカタログを返します。

### 管理 API

| リクエスト | 動作 |
| --- | --- |
| `GET /admin/api/config` | `config`、`generation`、`revision` と ETag を返します。 |
| `PUT /admin/api/config` | 設定全体を検証、保存、適用します。`If-Match: "revision"` が必要です。 |
| `POST /admin/reload` | 設定ファイルを読み込み、適用します。 |

3 つの操作には `Authorization: Bearer <Token>` が必要です。PUT は `If-Match` がなければ 428、古いリビジョンや外部からのファイル変更を検出すると 409、設定が無効なら 400、I/O エラーなら 500 を返します。リビジョンはファイルのバイト列の SHA-256 です。保存時は同一ディレクトリーの一時ファイルに書き込み、フラッシュ後にアトミックに置換してから設定を切り替えます。サービスユーザーには設定ディレクトリーへの書き込み権限が必要です。

## 設定リファレンス

トップレベルの JSON には `version`、`cors`、`folders`、`trusted_proxies`、`routes` を指定できます。バージョンの既定値は 1 です。フォルダーには `id`、`name`、任意の `parent_id` を指定でき、最大 16 階層です。`folder_id` のないルートはルート階層に表示されます。フォルダーは UI 上の整理に使います。

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

`GET /users?scenario=error` に `X-Scenario: test` を付けると 503 が返ります。同じルートのほかのリクエストには成功シナリオが使われます。

### ルートとルールの照合

- ルートは GET、POST、PUT、PATCH、DELETE、HEAD に対応します。OPTIONS は CORS プリフライト用です。HEAD は自動で GET にフォールバックしません。
- 固定パスはテンプレートより優先されます。各 `{name}` は空でないパスセグメントを 1 つ取得します。名前は英字またはアンダースコアで始まり、数字も使用でき、同一テンプレート内で一意とします。固定セグメントが多いテンプレートが優先され、同数なら設定順です。同じメソッドで同一形状のルートは定義できません。
- `match.path` は取得したデコード済みの値を完全一致で比較します。パスはパーセントデコード前に区切り、`+` はそのまま扱います。`match.query` はデコードした名前と値を比較します。パラメーターの順序や追加項目は照合に影響しません。同名のクエリは最初の値を使い、`?flag` と `?flag=` はどちらも空の値です。照合時の不正なパーセントエンコーディングは 400 になります。
- `match.headers` はヘッダー名の大文字と小文字を区別せず、値を完全一致で比較します。同名ヘッダーは最初の値を使います。
- JSON の `match.body` はオブジェクトの部分集合で照合します。配列は長さと順序を比較し、スカラーでは `1`、`1.0`、`"1"` などの型を区別します。XML は文書全体を比較します。UTF-8 BOM、前後の空白、改行コードの違いは無視されます。
- 設定したすべての条件に一致する必要があります。最も優先順位の高いルールが選ばれ、同順位なら設定順です。既定の優先順位は 0 です。ルートやルールに一致しなければ JSON の 404 が返ります。

### リクエストボディの式

`match.body_expression` は `match.body` の代わりに指定します。

| モード | リクエスト形式 | マッチ条件 |
| --- | --- | --- |
| `jsonpath` | JSON | 値を 1 件以上選択すると一致します。`expected.value` を指定した場合は、型を含めて完全に等しい値が必要です。 |
| `xpath` | XML | XPath 1.0 の真偽値で判定します。文字列の `expected.value` を指定すると、選択したノードのいずれかの文字列値、またはスカラーの XPath 文字列表現と比較します。 |
| `regex` | JSON または XML | RE2 形式の正規表現で元のボディを検索します。`^` と `$` で範囲を限定できます。 |

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

`"expected": {"value": null}` は JSON null に一致します。JSONPath はプロパティ、配列セレクター、再帰探索、フィルターに対応します。JSONPath の `match()` と `search()` は無効のため、正規表現は専用モードを使います。

XPath では `/order/item[@sku='paid']` や `count(/order/item) > 0` などの述語や真偽式を使えます。`"namespaces": [{"prefix":"o","uri":"urn:orders"}]` でプレフィックスを割り当て、`/o:order/o:item/@sku` と指定します。デフォルト名前空間にも式内で使用するプレフィックスの割り当てが必要です。

式は設定の読み込み時または保存時にコンパイルされ、上限は 1024 バイトです。空のボディは式に一致しません。照合前にボディ形式を検証します。JSONPath は既定値を適用した JSON を、正規表現は元のバイト列を使います。JSONPath と XPath の作業領域は 1 リクエストあたり 16 MiB です。JSONPath の JSON のネスト上限は 128 階層で、評価の制限を超えると 400 が返ります。

### リクエストの検証とレスポンステンプレート

`request.format` の既定値は `json` です。`request.body_required` を有効にするとボディがないリクエストを拒否します。省略可能な JSON ボディは空のオブジェクトとして扱います。JSON フィールドの検証にはオブジェクトが必要で、`string`、`integer`（符号付き 64 ビット）、`number`、`boolean` が使えます。フィールドを必須にするか、既定値を設定できます。追加フィールドは保持し、既定値は照合とレンダリングの前に適用します。不正なボディやフィールドは 400 になります。

`response.template: true` を設定すると、`{{body.name}}` は JSON のトップレベルフィールド、または XML ルート直下の `name` 要素のテキストを取得します。参照する JSON フィールドは必須か既定値付きにします。XML は `{{body.customer.name}}` のような階層パスと、`{{body.@id}}` や `{{body.customer.@id}}` のような属性参照にも対応します。各階層では、大文字と小文字および名前空間プレフィックスが一致する最初の子要素を選びます。要素の値には子孫のテキストも含まれます。`{{body.age|add:1}}` は整数の定数を加えます。

値は JSON 文字列、XML 要素のテキスト、または通常の XML 属性値に挿入できます。レスポンス形式に応じてエスケープし、生成した XML を検証します。参照値の不足、`add` への非整数、整数オーバーフローは 400 になります。XML を含むテンプレートの動的テキストの上限は 4 MiB です。**Examples** のテンプレートルートで JSON と XML の両方を試せます。

### レスポンスと制限

`response.body` は必須で、ステータスの既定値は 200 です。既定の JSON レスポンスは `application/json` を使用し、文字列も JSON でエンコードします。XML レスポンスは UTF-8 の XML を `application/xml; charset=utf-8` で送信します。Content-Type はカスタムヘッダーで上書きできます。ボディのエンコードは形式で決まります。

- ステータスコードは 200〜599 です。204、205、304 では `body: null` が必要です。これらのステータスと HEAD はボディを送信しません。
- `delay_ms` は 0〜30000 です。遅延中は設定ロックを解放し、httpz のワーカーが待機します。
- リクエストボディは最大 1 MiB、設定ファイルは 4 MiB 未満です。最大 1000 ルート、ルートごとに 1000 ルール、レスポンスごとに 32 個のカスタムヘッダーを設定できます。
- XML は整形式の UTF-8 で、ネストは最大 128 階層です。DTD を含む文書は拒否します。
- `/healthz`、`/admin`、`/admin/*`、`/viewer`、`/viewer/*` は予約済みです。不明なフィールド、重複するルート形状やルート内のルール ID、不正なテンプレートやヘッダーは設定エラーになります。Content-Length、Transfer-Encoding、Connection、Keep-Alive、Upgrade、Trailer、Vary、Access-Control-* はサービスが管理します。

## 再読み込み、CORS、ヘルスチェック

`MOCK_CONFIG` のファイルをアトミックに置換してから再読み込みを呼び出します。自動生成のトークンを使用する場合は、起動時に表示された値を Bearer ヘッダーに指定します。

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

再読み込みは設定済みのローカルファイルを読み込み、現在の管理トークンを保持します。トークンがないか無効な場合は 401 が返ります。

再読み込みが成功すると `status`、`generation`、`routes` が返ります。ファイルが存在しない場合や設定が無効な場合は `reason` とともに 400 を返し、現在の設定を維持します。起動時の設定が無効なら起動しません。再読み込みとオンライン保存は順に実行され、処理中のリクエストは設定切り替え中も自身のレスポンスデータを保持します。

既定の CORS はすべての Origin を許可し、クロスオリジンの認証情報は許可しません。`cors.origins` にはスキームとポートを含み、末尾にスラッシュのない Origin を指定します。空配列は CORS を無効にします。`*` は単独で使います。プリフライトは Origin、メソッド、ヘッダーを検証します。管理とカタログのパスは別のポリシーを使います。許可されていない Origin の通常リクエストもサービスに届きますが、CORS 許可ヘッダーは返しません。

`GET /healthz` は `status: "ok"`、有効な `generation`、`routes` の件数を返します。再読み込みが失敗しても有効な設定を報告します。HEAD に対応し、OPTIONS を除くほかのメソッドは 405 を返します。

## 環境変数

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `MOCK_HOST` | `0.0.0.0` | IPv4 または IPv6 の待ち受けアドレス。 |
| `MOCK_PORT` | `9080` | 1〜65535 の待ち受けポート。 |
| `MOCK_CONFIG` | `config/mock.json` | 設定ファイルのパス。相対パスはプロセスの作業ディレクトリーを基準にします。 |
| `MOCK_ADMIN_TOKEN` | 自動生成 | 任意の固定管理トークン。16 バイト以上。 |

## レート制限

管理画面でルートのレート制限を開き、クライアントごとの毎秒リクエスト数と、必要に応じて IP 別の値を指定します。例は `{"192.0.2.10":20,"2001:db8::1":0}` です。0〜10000 の整数を使用し、0 は無制限です。ルート設定では `rate_limit.requests_per_second` と `rate_limit.clients` を使います。

各プロセスは、クライアント IP、メソッド、設定上のルートごとに直近 1 秒の許可済みリクエストを数えます。同じルートのパスやクエリの違いとレスポンスシナリオは枠を共有します。上限を超えると 429 と `Retry-After: 1` を返します。カウンターの容量上限で新しいリクエストを記録できない場合は 503 と同じヘッダーを返します。保存すると新しい上限がすぐに有効になり、計測中のカウンターは保持されます。

不明なルート、ヘルスチェック、管理とカタログへのリクエスト、OPTIONS は枠を消費しません。

既定では接続元 IP をクライアントとします。`trusted_proxies` に `["127.0.0.1"]` などを設定すると、指定したプロキシからの `X-Forwarded-For` を使用します。この構成では、バックエンドへのアクセスを信頼済みプロキシに限定してください。多段構成では、最後のプロキシが検証済みのクライアント IP を 1 つ渡します。[Caddy のリバースプロキシヘッダー](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#headers)

## Linux へのデプロイ

systemd と Caddy のサンプルは `クライアント → Caddy HTTPS → 127.0.0.1:9080 → モックサーバー` の構成を想定しています。デプロイコマンドは対象サーバーで管理者権限を使って実行します。

サーバーのアーキテクチャ向けにビルドします。2 番目のコマンドは Linux x86_64 向けにクロスコンパイルし、`zig-out/linux/bin/test_web` を作成します。ARM64 では対応するターゲットを指定し、実行ファイルを対象サーバーで検証します。

```sh
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p zig-out/linux
```

実行ファイルとプロジェクトの設定を転送します。転送先でログインできないシステムユーザーを作成し、ファイルを配置します。

```sh
sudo useradd --system --no-create-home --shell /usr/sbin/nologin mock
sudo install -d -m 0755 /opt/zig-mock /etc/zig-mock
sudo install -d -o mock -g mock -m 0750 /var/lib/zig-mock
sudo install -m 0755 test_web /opt/zig-mock/test_web
sudo install -o mock -g mock -m 0640 config/mock.json /var/lib/zig-mock/mock.json
sudo install -m 0600 deploy/mock.env.example /etc/zig-mock/mock.env
sudo install -m 0644 deploy/mock.service /etc/systemd/system/zig-mock.service
```

固定トークンが必要な場合は `/etc/zig-mock/mock.env` に設定します。サービスは `/var/lib/zig-mock/` に書き込めます。環境ファイルを読めるのは root のみです。

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now zig-mock
curl --fail http://127.0.0.1:9080/healthz
sudo journalctl -u zig-mock -n 50 --no-pager
```

既存の systemd サービスが `/etc/zig-mock/mock.json` を使用している場合は、`/var/lib/zig-mock/` にコピーし、所有者を `mock:mock` に設定して `MOCK_CONFIG` を更新してから再起動します。

JSON の変更は再読み込みで反映します。実行ファイルまたは環境変数の変更時は `sudo systemctl restart zig-mock` を実行します。自動生成トークンなどの起動ログは journald で確認できます。

[Caddy のサンプル](../deploy/Caddyfile)のドメインを変更し、サーバーの Caddy 設定にサイトブロックを追加します。DNS をサーバーに向け、80 と 443 ポートを開きます。

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

既定のプロキシ例はモックリクエストを転送し、`/admin` と `/viewer` への外部アクセスを遮断します。`/healthz` とサンプルルートで HTTPS を確認します。`ssh -L 19080:127.0.0.1:9080 user@server` でローカルの 19080 ポートから管理画面とカタログに接続するか、[別の Caddy サンプル](../deploy/Caddyfile.admin.example)で HTTPS 公開できます。公開する場合も管理 API にはトークンが必要で、ドメインにアクセスできる利用者はカタログを閲覧できます。

サービスはリクエストボディや手動設定したトークンをログに残しません。モックへのアクセス制限が必要な場合はリバースプロキシで設定します。

## 検証

```sh
zig fmt --check src/main.zig src/mock.zig src/app.zig src/body_match.zig src/jsonpath_regex.zig build.zig build.zig.zon
zig build test
zig build
python tests/integration.py
node --test tests/json-codec.test.cjs
```

Python の統合テストは一時設定とランダムなローカルポートを使います。`python3 tests/integration.py /opt/zig-mock/test_web` のように実行ファイルを指定できます。
