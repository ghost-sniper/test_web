# Zig-Mockserver

[English](../README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Deutsch** · [繁體中文](README.zh-TW.md)

Ein konfigurationsgesteuerter HTTP-Mockserver mit Zig 0.17.0 und httpz. Routen und Antwortszenarien werden in JSON definiert. Änderungen lassen sich durch erneutes Laden der Datei oder durch Speichern in der Webkonsole aktivieren.

## Bauen und starten

Verwenden Sie Zig **0.17.0**. Die Revisionen und Hashes der Abhängigkeiten sind in `build.zig.zon` festgelegt. Verwenden Sie für Produktionsbuilds ein festes Compilerpaket.

Führen Sie das Bash- oder PowerShell-Buildskript aus und starten Sie den Dienst aus dem Projektstammverzeichnis.

```bash
bash build.sh
```

```powershell
.\build.ps1
```

```sh
zig build run
```

Die Skripte prüfen zuerst den PATH und den lokalen Toolchain-Cache. Bei Bedarf laden sie den Compiler aus dem offiziellen Zig-Verzeichnis, prüfen die SHA-256-Prüfsumme und speichern ihn unter `.zig-cache/toolchains/`. Der automatische Download unterstützt x86_64 und ARM64 unter Linux, macOS und Windows sowie x86 unter Linux und Windows. Der Bash-Download benötigt `curl`, `sha256sum` oder `shasum` und ein `tar` mit xz-Unterstützung. Git Bash verwendet `unzip` für Windows-Archive. Das PowerShell-Skript läuft mit Windows PowerShell 5.1 oder PowerShell 7. Außerhalb von Windows benötigt der Download ein xz-fähiges `tar`. [Offizielles Zig-Releaseverzeichnis](https://ziglang.org/download/index.json)

Beide Skripte führen `zig build --fetch` und anschließend `zig build` mit der Standardoptimierung `Debug` aus. Sobald Toolchain und Abhängigkeiten im Cache liegen, ist der Build offline möglich. Ist Zig nicht im PATH, starten Sie unter Windows `.\zig-out\bin\test_web.exe` oder unter Linux und macOS `./zig-out/bin/test_web` direkt.

Der Dienst lauscht standardmäßig auf `0.0.0.0:9080`. Lokal erreichen Sie ihn über `http://127.0.0.1:9080`. Ist `MOCK_ADMIN_TOKEN` leer oder nicht gesetzt, erzeugt der Dienst beim Start ein Token und zeigt es als `Generated admin token: …` an. Um ein Token über Neustarts hinweg zu verwenden, setzen Sie vor dem Start einen Wert mit mindestens 16 Byte. Ausgegeben werden nur automatisch erzeugte Token.

## Mitgelieferte Beispiele

Der Ordner **Examples** in der Webkonsole enthält diese Routen aus der [Beispielkonfiguration](../config/mock.json). Senden Sie JSON mit `Content-Type: application/json` und XML mit `Content-Type: application/xml`.

| Funktion | Anfrage | Anfrageinhalt | Antwortinhalt |
| --- | --- | --- | --- |
| JSONPath | `POST /examples/jsonpath` | `{"orders":[{"qty":2,"status":"paid"}]}` | `{"matched":"jsonpath"}` |
| XPath | `POST /examples/xpath` | `<order xmlns="urn:orders"><status>paid</status></order>` | `{"matched":"xpath"}` |
| Query-Parameter | `GET /examples/query?status=paid&source=web` | — | `{"matched":"query"}` |
| Pfadparameter | `GET /examples/items/42` | — | `{"matched":"path","id":42}` |
| Regulärer Ausdruck | `POST /examples/regex` | `{"code":"AB-42"}` | `{"matched":"regex"}` |
| JSON-Antwortvorlage | `POST /examples/template/json` | `{"name":"Ada"}` | `{"message":"Hello, Ada!"}` |
| XML-Antwortvorlage | `POST /examples/template/xml` | `<request><name>Ada</name></request>` | `<greeting>Hello, Ada!</greeting>` |

Bei einem Treffer geben die Beispiele HTTP 200 zurück. Die ersten fünf Beispiele haben Bedingungen. Eine gültige Anfrage ohne Treffer erhält 404.

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

## Webkonsole und schreibgeschützter Katalog

Öffnen Sie `http://127.0.0.1:9080/admin/` und geben Sie das Admin-Token ein. Es bleibt im Speicher der Seite. Nach dem Neuladen der Seite müssen Sie die Verbindung erneut herstellen. Light ist das Standarddesign. Der Browser merkt sich die Auswahl aus Light, Dark, Cyberpunk 2077, EVA, Death Stranding und Black Myth: Wukong.

- Die Ordnerschaltfläche öffnet oder schließt die Seitenleiste. Auf schmalen Bildschirmen schließen Sie sie durch einen Klick auf den Hintergrund, mit Esc oder durch Auswahl einer Route.
- Erstellen Sie verschachtelte Ordner, benennen Sie sie um, verschieben Sie sie oder löschen Sie leere Ordner. Routen lassen sich über ihr Menü oder im Editor einem anderen Ordner zuordnen. Die Suche akzeptiert Pfadfragmente und vollständige HTTP(S)-URLs. Bei vollständigen URLs wird der Pfad verglichen.
- Erstellen, kopieren, bearbeiten oder löschen Sie Antwortszenarien. Das Anfrageformat gilt pro Route und das Antwortformat pro Szenario. Im Szenario legen Sie Bedingungen, Priorität, Status, Verzögerung, Header und Vorlage fest.
- Geben Sie Query-Bedingungen als JSON-Objekt, als mit `?` beginnende Query-Zeichenfolge oder als URL mit Query an. Für `/orders/{id}` ist `{"id":"42"}` eine mögliche Pfadbedingung. In den Optionen für den Anfrageinhalt stehen JSONPath, XPath und reguläre Ausdrücke zur Auswahl.
- Das Speichern schreibt die vollständige Konfiguration auf den Datenträger und aktiviert sie. Das Löschen eines Szenarios ändert den Entwurf. Beim Löschen einer Route werden nach Bestätigung auch die übrigen Entwurfsänderungen gespeichert. Eine Route benötigt mindestens ein Szenario.
- Laden Sie ein Szenariobeispiel, um Test-URL, Header und Anfrageinhalt zu füllen. Bei Ausdrucksregeln tragen Sie einen passenden Inhalt ein. Der Test sendet eine echte Anfrage an den Dienst und verwendet die gespeicherten Regeln. GET und HEAD senden keinen Inhalt. Ein Test lässt sich abbrechen und hat ein Zeitlimit von 35 Sekunden. Weiterleitungen werden blockiert. Das Admin-Token wird nur gesendet, wenn es ausdrücklich als Test-Header eingetragen wurde.
- Aktualisieren liest die aktive Konfiguration. Erneutes Laden liest die Datei. Vor dem Verwerfen eines Entwurfs wird nachgefragt. Bei einem Speicherkonflikt bleibt der Entwurf erhalten.

Der Editor erhält die Zahlendarstellung in JSON, einschließlich 64-Bit-Ganzzahlen. Die Webressourcen sind in der ausführbaren Datei enthalten. Änderungen am Frontend erfordern einen neuen Build und einen Neustart.

Öffnen Sie `http://127.0.0.1:9080/viewer` direkt oder aus der Konsole. Im schreibgeschützten Katalog lassen sich Routen, Anfragedetails, Bedingungen und Antwortvorschauen ohne Anmeldung ansehen. `GET /viewer/api/catalog` liefert den aktiven Katalog.

### Admin-API

| Anfrage | Verhalten |
| --- | --- |
| `GET /admin/api/config` | Gibt `config`, `generation`, `revision` und einen ETag zurück. |
| `PUT /admin/api/config` | Prüft, speichert und aktiviert eine vollständige Konfiguration. Senden Sie `If-Match: "revision"`. |
| `POST /admin/reload` | Lädt und aktiviert die konfigurierte Datei. |

Alle drei Operationen benötigen `Authorization: Bearer <Token>`. PUT gibt ohne `If-Match` 428 zurück, bei einer veralteten Revision oder einer externen Dateiänderung 409, bei einer ungültigen Konfiguration 400 und bei einem E/A-Fehler 500. Die Revision ist der SHA-256-Hash der Dateibytes. Beim Speichern wird eine temporäre Datei im selben Verzeichnis geschrieben, synchronisiert und atomar gegen die Zieldatei ausgetauscht. Danach wird die neue Konfiguration aktiv. Der Dienstbenutzer benötigt Schreibrechte für das Konfigurationsverzeichnis.

## Konfigurationsreferenz

Das JSON auf oberster Ebene kann `version`, `cors`, `folders`, `trusted_proxies` und `routes` enthalten. Die Standardversion ist 1. Ein Ordner hat `id`, `name` und optional `parent_id`. Bis zu 16 Ebenen sind möglich. Routen ohne `folder_id` erscheinen auf der obersten Ebene. Ordner dienen der Darstellung in der Oberfläche.

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

`GET /users?scenario=error` mit `X-Scenario: test` gibt 503 zurück. Andere Anfragen an dieselbe Route verwenden das Erfolgsszenario.

### Routen- und Regelauswahl

- Unterstützte Routenmethoden sind GET, POST, PUT, PATCH, DELETE und HEAD. OPTIONS verarbeitet CORS-Preflights. HEAD fällt nicht automatisch auf GET zurück.
- Feste Pfade haben Vorrang vor Pfadvorlagen. Jedes `{name}` erfasst ein nicht leeres Segment. Namen beginnen mit einem ASCII-Buchstaben oder Unterstrich, können Ziffern enthalten und sind innerhalb einer Vorlage eindeutig. Die Vorlage mit mehr festen Segmenten hat Vorrang. Bei Gleichstand zählt die Reihenfolge in der Konfiguration. Gleiche Routenformen pro Methode sind unzulässig.
- `match.path` vergleicht die dekodierten erfassten Werte exakt. Der Pfad wird vor der Prozentdekodierung segmentiert. `+` bleibt wörtlich. `match.query` vergleicht dekodierte Namen und Werte. Reihenfolge und zusätzliche Parameter sind unerheblich. Bei Duplikaten gilt der erste Wert. `?flag` und `?flag=` stehen beide für einen leeren Wert. Ungültige Prozentkodierung beim Abgleich ergibt 400.
- `match.headers` ignoriert die Groß- und Kleinschreibung von Headernamen und vergleicht die Werte exakt. Bei doppelten Headern gilt der erste Wert.
- Für JSON ist `match.body` eine Teilmenge eines Objekts. Bei Arrays werden Länge und Reihenfolge verglichen. Bei Skalaren werden Typen wie `1`, `1.0` und `"1"` unterschieden. Bei XML wird das gesamte Dokument verglichen, ohne UTF-8-BOM, äußere Leerzeichen und Unterschiede bei Zeilenenden zu berücksichtigen.
- Alle eingetragenen Bedingungen müssen zutreffen. Die passende Regel mit der höchsten Priorität gewinnt. Bei Gleichstand gilt die Reihenfolge in der Konfiguration. Standardpriorität ist 0. Fehlt die Route oder eine passende Regel, folgt eine JSON-Antwort mit 404.

### Ausdrücke für den Anfrageinhalt

`match.body_expression` ist eine Alternative zu `match.body`.

| Modus | Anfrageformat | Bedingung |
| --- | --- | --- |
| `jsonpath` | JSON | Wählt mindestens einen Wert aus. Bei gesetztem `expected.value` muss mindestens ein Wert einschließlich JSON-Typ exakt übereinstimmen. |
| `xpath` | XML | Verwendet den booleschen XPath-1.0-Wert. Mit einem String als `expected.value` wird der Stringwert eines beliebigen ausgewählten Knotens oder die XPath-Stringdarstellung eines Skalars verglichen. |
| `regex` | JSON oder XML | Sucht mit RE2-ähnlicher Syntax im ursprünglichen Anfrageinhalt. `^` und `$` verankern den Ausdruck. |

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

`"expected": {"value": null}` prüft auf JSON null. JSONPath unterstützt Eigenschaften, Arrayselektoren, rekursiven Abstieg und Filter. Die JSONPath-Funktionen `match()` und `search()` sind deaktiviert. Für reguläre Ausdrücke gibt es einen eigenen Modus.

XPath unterstützt Prädikate und boolesche Ausdrücke wie `/order/item[@sku='paid']` oder `count(/order/item) > 0`. Binden Sie Namensraumpräfixe über `"namespaces": [{"prefix":"o","uri":"urn:orders"}]` und verwenden Sie beispielsweise `/o:order/o:item/@sku`. Ein Standardnamensraum benötigt ebenfalls ein gebundenes Präfix im Ausdruck.

Ausdrücke werden beim Laden oder Speichern kompiliert. Sie dürfen höchstens 1024 Byte lang sein. Leere Inhalte treffen auf keine Ausdrucksregel zu. Der Dienst validiert vor dem Abgleich das Format. JSONPath verwendet JSON mit angewendeten Feldvorgaben, Regex die ursprünglichen Bytes. JSONPath und XPath nutzen pro Anfrage 16 MiB Arbeitsbereich. JSONPath erlaubt bis zu 128 JSON-Ebenen. Wird ein Auswertungslimit überschritten, antwortet der Dienst mit 400.

### Anfragevalidierung und Antwortvorlagen

`request.format` hat den Standardwert `json`. `request.body_required` weist Anfragen ohne Inhalt ab. Fehlender optionaler JSON-Inhalt wird als leeres Objekt behandelt. Die JSON-Feldvalidierung erfordert ein Objekt und unterstützt `string`, `integer` (vorzeichenbehaftet, 64 Bit), `number` und `boolean`. Felder können verpflichtend sein oder einen Standardwert haben. Weitere Felder bleiben erhalten. Standardwerte werden vor dem Abgleich und Rendern angewendet. Ungültige Inhalte oder Felder ergeben 400.

Mit `response.template: true` liest `{{body.name}}` ein JSON-Feld der obersten Ebene oder den Text des XML-Kindelements `name` unter dem Wurzelelement. Referenzierte JSON-Felder müssen verpflichtend sein oder einen Standardwert haben. XML unterstützt verschachtelte Pfade wie `{{body.customer.name}}` und Attributzugriffe wie `{{body.@id}}` oder `{{body.customer.@id}}`. Pro Ebene wird das erste Kind mit exakt passendem Namen und Namensraumpräfix gewählt. Der Elementwert umfasst auch den Text seiner Nachkommen. `{{body.age|add:1}}` addiert eine ganzzahlige Konstante.

Werte lassen sich in JSON-Strings sowie in XML-Elementtext und gewöhnliche XML-Attribute einsetzen. Der Dienst maskiert eingefügten Text formatgerecht und validiert das erzeugte XML. Fehlende Werte, nicht ganzzahlige Eingaben für `add` und Überläufe ergeben 400. Vorlagen mit XML haben ein Limit von 4 MiB für dynamischen Text. Die zwei Vorlagenrouten unter **Examples** zeigen die JSON- und XML-Varianten.

### Antworten und Grenzen

`response.body` ist erforderlich. Standardstatus ist 200. JSON ist das Standardformat und verwendet `application/json`. Auch Zeichenfolgen werden in JSON kodiert. XML-Antworten senden UTF-8-XML mit `application/xml; charset=utf-8`. Ein eigener Content-Type-Header kann den Standardheader überschreiben. Das Format bestimmt die Kodierung des Inhalts.

- Statuscodes liegen zwischen 200 und 599. 204, 205 und 304 benötigen `body: null`. Diese Statuscodes und HEAD senden keinen Inhalt.
- `delay_ms` liegt zwischen 0 und 30000. Während der httpz-Worker wartet, ist die Konfigurationssperre freigegeben.
- Anfrageinhalte sind auf 1 MiB begrenzt. Konfigurationsdateien müssen kleiner als 4 MiB sein. Es sind bis zu 1000 Routen, 1000 Regeln pro Route und 32 eigene Header pro Antwort zulässig.
- XML muss wohlgeformt, UTF-8-kodiert und auf 128 Verschachtelungsebenen begrenzt sein. Dokumente mit DTD werden abgelehnt.
- `/healthz`, `/admin`, `/admin/*`, `/viewer` und `/viewer/*` sind reserviert. Unbekannte Felder, doppelte Routenformen oder Regel-IDs innerhalb einer Route, ungültige Vorlagen und verbotene Header machen die Konfiguration ungültig. Der Dienst verwaltet Content-Length, Transfer-Encoding, Connection, Keep-Alive, Upgrade, Trailer, Vary und Access-Control-*.

## Neuladen, CORS und Zustandsprüfung

Ersetzen Sie die in `MOCK_CONFIG` festgelegte Datei atomar und rufen Sie dann das Neuladen auf. Verwenden Sie für ein automatisch erzeugtes Token den beim Start angezeigten Wert im Bearer-Header.

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

Beim Neuladen wird nur die konfigurierte lokale Datei gelesen. Das aktuelle Admin-Token bleibt gültig. Ein fehlendes oder ungültiges Token ergibt 401.

Ein erfolgreiches Neuladen liefert `status`, `generation` und `routes`. Fehlt die Datei oder ist die Konfiguration ungültig, liefert der Dienst 400 mit `reason`. Die bisherige Konfiguration bleibt aktiv. Mit einer ungültigen Startkonfiguration startet der Dienst nicht. Neuladen und Speichern werden nacheinander ausgeführt. Laufende Anfragen behalten beim Konfigurationswechsel ihre Antwortdaten.

CORS erlaubt standardmäßig alle Origins ohne Cross-Origin-Anmeldedaten. Tragen Sie in `cors.origins` genaue Origins mit Schema und Port, aber ohne abschließenden Schrägstrich ein. Ein leeres Array schaltet CORS ab. `*` steht allein. Der Preflight prüft Origin, Methode und Header. Admin- und Katalogpfade haben eine eigene Richtlinie. Normale Anfragen nicht erlaubter Origins können verarbeitet werden und erhalten keine CORS-Freigabeheader.

`GET /healthz` liefert `status: "ok"`, die aktive `generation` und die Anzahl der `routes`. Nach einem fehlgeschlagenen Neuladen wird weiterhin die aktive Konfiguration gemeldet. HEAD wird unterstützt. Andere Methoden außer OPTIONS geben 405 zurück.

## Umgebungsvariablen

| Variable | Standard | Zweck |
| --- | --- | --- |
| `MOCK_HOST` | `0.0.0.0` | IPv4- oder IPv6-Adresse zum Lauschen. |
| `MOCK_PORT` | `9080` | Port zwischen 1 und 65535. |
| `MOCK_CONFIG` | `config/mock.json` | Konfigurationspfad. Relative Pfade beziehen sich auf das Arbeitsverzeichnis des Prozesses. |
| `MOCK_ADMIN_TOKEN` | Erzeugt | Optionales festes Admin-Token mit mindestens 16 Byte. |

## Ratenbegrenzung

Öffnen Sie in der Konsole die Ratenbegrenzung der Route. Legen Sie die Zahl der Anfragen pro Sekunde und Client fest, bei Bedarf mit eigenen Werten pro IP, etwa `{"192.0.2.10":20,"2001:db8::1":0}`. Gültig sind Ganzzahlen von 0 bis 10000. Null bedeutet unbegrenzt. Die Routenfelder heißen `rate_limit.requests_per_second` und `rate_limit.clients`.

Jeder Prozess zählt die zugelassenen Anfragen der letzten Sekunde pro Client-IP, Methode und konfigurierter Route. Unterschiedliche Pfad- und Query-Parameter und Antwortszenarien teilen das Clientkontingent der Route. Bei Überschreitung folgt 429 mit `Retry-After: 1`. Ist die Zählerkapazität erschöpft, erhält eine nicht erfassbare neue Anfrage 503 mit demselben Header. Neue Grenzwerte gelten sofort nach dem Speichern, laufende Zähler bleiben erhalten.

Unbekannte Routen, Zustandsprüfungen, Admin- und Kataloganfragen sowie OPTIONS verbrauchen kein Kontingent.

Standardmäßig gilt die IP der Verbindung als Clientadresse. Tragen Sie in `trusted_proxies` beispielsweise `["127.0.0.1"]` ein, um `X-Forwarded-For` von den eingetragenen Proxys anzunehmen. In dieser Konfiguration sollte das Backend nur über vertrauenswürdige Proxys erreichbar sein. Bei einer Proxykette übermittelt der letzte Proxy eine einzelne geprüfte Clientadresse. [Caddy-Header für Reverse-Proxys](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#headers)

## Bereitstellung unter Linux

Die systemd- und Caddy-Beispiele verwenden `Client → Caddy HTTPS → 127.0.0.1:9080 → Mockserver`. Führen Sie die Bereitstellungsbefehle mit Administratorrechten auf dem Zielserver aus.

Bauen Sie für die Architektur des Servers. Der zweite Befehl erstellt per Cross-Compilation `zig-out/linux/bin/test_web` für Linux x86_64. Wählen Sie für ARM64 das passende Ziel und prüfen Sie das Programm auf dem Zielserver.

```sh
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p zig-out/linux
```

Übertragen Sie Programm und Konfiguration. Legen Sie im Upload-Verzeichnis einen Systembenutzer ohne Login-Shell an und installieren Sie die Dateien.

```sh
sudo useradd --system --no-create-home --shell /usr/sbin/nologin mock
sudo install -d -m 0755 /opt/zig-mock /etc/zig-mock
sudo install -d -o mock -g mock -m 0750 /var/lib/zig-mock
sudo install -m 0755 test_web /opt/zig-mock/test_web
sudo install -o mock -g mock -m 0640 config/mock.json /var/lib/zig-mock/mock.json
sudo install -m 0600 deploy/mock.env.example /etc/zig-mock/mock.env
sudo install -m 0644 deploy/mock.service /etc/systemd/system/zig-mock.service
```

Ein festes Token lässt sich in `/etc/zig-mock/mock.env` eintragen. Der Dienst kann in `/var/lib/zig-mock/` schreiben. Die Umgebungsdatei ist nur für root lesbar.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now zig-mock
curl --fail http://127.0.0.1:9080/healthz
sudo journalctl -u zig-mock -n 50 --no-pager
```

Verwendet ein bestehender systemd-Dienst `/etc/zig-mock/mock.json`, kopieren Sie die Datei nach `/var/lib/zig-mock/`, setzen den Eigentümer auf `mock:mock` und aktualisieren `MOCK_CONFIG` vor dem Neustart.

Laden Sie die Konfiguration nach JSON-Änderungen neu. Änderungen am Programm oder an der Umgebung erfordern `sudo systemctl restart zig-mock`. Startmeldungen und das erzeugte Token sind über journald verfügbar.

Ersetzen Sie die Domain im [Caddy-Beispiel](../deploy/Caddyfile) und übernehmen Sie den Site-Block in die Caddy-Konfiguration des Servers. Lassen Sie DNS auf den Server zeigen und öffnen Sie die Ports 80 und 443.

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Das Standardbeispiel leitet Mock-Anfragen weiter und sperrt öffentlichen Zugriff auf `/admin` und `/viewer`. Prüfen Sie HTTPS mit `/healthz` und einer Beispielroute. Verwenden Sie `ssh -L 19080:127.0.0.1:9080 user@server` und den lokalen Port 19080 für Konsole und Katalog oder das [alternative Caddy-Beispiel](../deploy/Caddyfile.admin.example), um beide über HTTPS bereitzustellen. Die Admin-API benötigt dann weiterhin ein Token. Besucher mit Zugriff auf die Domain können den Katalog lesen.

Der Dienst protokolliert keine Anfrageinhalte oder manuell gesetzten Token. Bei Bedarf lassen sich Zugriffsregeln für Mock-Anfragen am Reverse-Proxy einrichten.

## Überprüfung

```sh
zig fmt --check src/main.zig src/mock.zig src/app.zig src/body_match.zig src/jsonpath_regex.zig build.zig build.zig.zon
zig build test
zig build
python tests/integration.py
node --test tests/json-codec.test.cjs
```

Die Python-Integrationstests nutzen eine temporäre Konfiguration und einen zufälligen lokalen Port. Sie können den Programmpfad angeben, etwa mit `python3 tests/integration.py /opt/zig-mock/test_web`.
