# Serveur Mock Zig

[English](../README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · **Français** · [Deutsch](README.de.md) · [繁體中文](README.zh-TW.md)

Serveur de simulation HTTP piloté par une configuration JSON, construit avec Zig 0.17.0 et httpz. Définissez les routes et les scénarios de réponse, puis rechargez le fichier ou appliquez les changements dans la console web.

## Compilation et démarrage

Utilisez Zig **0.17.0**. Les révisions et les empreintes des dépendances sont fixées dans `build.zig.zon`. Utilisez la même distribution du compilateur pour les compilations de production.

Exécutez le script Bash ou PowerShell, puis démarrez le service à la racine du projet.

```bash
bash build.sh
```

```powershell
.\build.ps1
```

```sh
zig build run
```

Les scripts cherchent d’abord Zig dans le PATH et le cache local. Si nécessaire, ils téléchargent le compilateur depuis le catalogue officiel, vérifient son empreinte SHA-256 et le mettent en cache dans `.zig-cache/toolchains/`. Le téléchargement automatique prend en charge x86_64 et ARM64 sur Linux, macOS et Windows, ainsi que x86 sur Linux et Windows. Le script Bash utilise `curl`, `sha256sum` ou `shasum` et un `tar` compatible xz. Git Bash utilise `unzip` pour les archives Windows. Le script PowerShell fonctionne avec Windows PowerShell 5.1 ou PowerShell 7. Sur les autres systèmes, le téléchargement nécessite un `tar` compatible xz. [Catalogue officiel de Zig](https://ziglang.org/download/index.json)

Les deux scripts exécutent `zig build --fetch`, puis `zig build` avec le niveau d’optimisation par défaut `Debug`. Une fois le compilateur et les dépendances mis en cache, la compilation peut se faire hors ligne. Si Zig n’est pas dans le PATH, exécutez `.\zig-out\bin\test_web.exe` sous Windows ou `./zig-out/bin/test_web` sous Linux et macOS.

Le service écoute par défaut sur `0.0.0.0:9080`. Utilisez `http://127.0.0.1:9080` en local. Si `MOCK_ADMIN_TOKEN` est vide ou absent, le service crée un jeton au démarrage et l’affiche sous la forme `Generated admin token: …`. Pour réutiliser un jeton après un redémarrage, définissez une valeur d’au moins 16 octets avant le lancement. Seuls les jetons générés sont affichés.

## Exemples fournis

Le dossier **Examples** de la console regroupe les routes suivantes de la [configuration d’exemple](../config/mock.json). Utilisez `Content-Type: application/json` pour JSON et `Content-Type: application/xml` pour XML.

| Fonction | Requête | Corps de la requête | Corps de la réponse |
| --- | --- | --- | --- |
| JSONPath | `POST /examples/jsonpath` | `{"orders":[{"qty":2,"status":"paid"}]}` | `{"matched":"jsonpath"}` |
| XPath | `POST /examples/xpath` | `<order xmlns="urn:orders"><status>paid</status></order>` | `{"matched":"xpath"}` |
| Paramètres de requête | `GET /examples/query?status=paid&source=web` | — | `{"matched":"query"}` |
| Paramètres de chemin | `GET /examples/items/42` | — | `{"matched":"path","id":42}` |
| Expression régulière | `POST /examples/regex` | `{"code":"AB-42"}` | `{"matched":"regex"}` |
| Modèle de réponse JSON | `POST /examples/template/json` | `{"name":"Ada"}` | `{"message":"Hello, Ada!"}` |
| Modèle de réponse XML | `POST /examples/template/xml` | `<request><name>Ada</name></request>` | `<greeting>Hello, Ada!</greeting>` |

Les exemples renvoient HTTP 200 lorsque la règle s’applique. Les cinq premiers ont des conditions et renvoient 404 si une requête valide ne les satisfait pas.

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

## Console web et catalogue en lecture seule

Ouvrez `http://127.0.0.1:9080/admin/` et saisissez le jeton d’administration. La console conserve le jeton dans la mémoire de la page, ce qui impose une reconnexion après une actualisation. Light est le thème par défaut. Le navigateur mémorise le choix parmi Light, Dark, Cyberpunk 2077, EVA, Death Stranding et Black Myth: Wukong.

- Le bouton des dossiers ouvre ou replie le volet. Sur un écran étroit, cliquez sur l’arrière-plan, appuyez sur Échap ou choisissez une route pour le fermer.
- Créez des dossiers imbriqués, renommez-les, déplacez-les ou supprimez les dossiers vides. Déplacez une route par son menu ou modifiez son dossier dans l’éditeur. La recherche accepte un fragment de chemin ou une URL HTTP(S) complète, dont seul le chemin sert à la recherche.
- Créez, copiez, modifiez ou supprimez des scénarios de réponse. Le format de requête se définit par route, celui de réponse par scénario. Réglez les conditions, la priorité, le statut, le délai, les en-têtes et le modèle dans le scénario.
- Saisissez les paramètres de requête sous forme d’objet JSON, de chaîne commençant par `?` ou d’URL avec une chaîne de requête. Pour `/orders/{id}`, utilisez `{"id":"42"}` comme condition sur le chemin. Choisissez JSONPath, XPath ou une expression régulière dans les options du corps de requête.
- L’enregistrement applique la configuration complète et l’écrit sur disque. La suppression d’un scénario modifie le brouillon. La suppression d’une route demande confirmation, puis enregistre aussi les autres changements du brouillon. Une route doit avoir au moins un scénario.
- Chargez l’exemple d’un scénario pour renseigner l’URL, les en-têtes et le corps du test. Pour une règle à expression, fournissez un corps qui satisfait la condition. Le test envoie une requête réelle au service et utilise les règles enregistrées. GET et HEAD n’envoient pas de corps. Le test peut être annulé et expire après 35 secondes. Les redirections sont bloquées. Le jeton d’administration est envoyé uniquement s’il est saisi dans un en-tête de test.
- L’actualisation lit la configuration active. Le rechargement lit le fichier. La console demande confirmation avant d’abandonner un brouillon et le conserve en cas de conflit d’enregistrement.

L’éditeur préserve la représentation des nombres JSON, y compris les entiers sur 64 bits. Les ressources web sont intégrées à l’exécutable. Après une modification du code de l’interface, recompilez et redémarrez le service.

Ouvrez `http://127.0.0.1:9080/viewer` directement ou depuis la console. Le catalogue permet à tout visiteur de rechercher des routes et de consulter les détails des requêtes, les conditions et les aperçus des réponses. `GET /viewer/api/catalog` renvoie le catalogue actif.

### API d’administration

| Requête | Comportement |
| --- | --- |
| `GET /admin/api/config` | Renvoie `config`, `generation`, `revision` et un ETag. |
| `PUT /admin/api/config` | Valide, enregistre et applique une configuration complète. Fournissez `If-Match: "revision"`. |
| `POST /admin/reload` | Charge et applique le fichier configuré. |

Les trois opérations exigent `Authorization: Bearer <Token>`. PUT renvoie 428 sans `If-Match`, 409 si la révision est périmée ou le fichier a changé en dehors du service, 400 pour une configuration invalide et 500 en cas d’erreur d’E/S. La révision est l’empreinte SHA-256 des octets du fichier. L’enregistrement écrit un fichier temporaire dans le même répertoire, le synchronise et remplace la cible de manière atomique avant d’activer la nouvelle configuration. L’utilisateur du service doit pouvoir écrire dans le répertoire de configuration.

## Référence de configuration

Le JSON de premier niveau accepte `version`, `cors`, `folders`, `trusted_proxies` et `routes`. La version par défaut est 1. Un dossier possède un `id`, un `name` et éventuellement un `parent_id`. La profondeur maximale est de 16 niveaux. Les routes sans `folder_id` apparaissent à la racine. L’affectation à un dossier concerne uniquement l’interface.

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

`GET /users?scenario=error` avec `X-Scenario: test` renvoie 503. Les autres requêtes sur la même route utilisent le scénario de succès.

### Sélection des routes et des règles

- Les routes acceptent GET, POST, PUT, PATCH, DELETE et HEAD. OPTIONS traite les requêtes CORS préliminaires. HEAD ne se rabat pas automatiquement sur GET.
- Les chemins fixes sont prioritaires sur les modèles. Chaque `{name}` capture un segment non vide. Les noms commencent par une lettre ASCII ou un trait de soulignement, peuvent contenir des chiffres et sont uniques dans un modèle. Le modèle ayant le plus de segments fixes l’emporte. L’ordre de configuration départage les ex æquo. La forme des routes doit être unique pour une méthode donnée.
- `match.path` compare exactement les valeurs capturées après décodage. Le chemin est découpé avant le décodage des pourcentages et `+` reste littéral. `match.query` compare les noms et valeurs décodés. L’ordre et les paramètres supplémentaires n’influencent pas la sélection. Pour un nom répété, la première valeur est utilisée. `?flag` et `?flag=` indiquent une valeur vide. Un encodage par pourcentage invalide rencontré pendant la comparaison renvoie 400.
- `match.headers` ignore la casse des noms d’en-tête et compare les valeurs exactement. En cas de répétition, la première valeur est utilisée.
- Pour JSON, `match.body` correspond à un sous-ensemble d’objet. Les tableaux sont comparés par longueur et ordre, et les scalaires distinguent `1`, `1.0` et `"1"`. Pour XML, le corps est comparé au document entier, en ignorant le BOM UTF-8, les espaces en début et fin et les différences de fins de ligne.
- Toutes les conditions doivent être satisfaites. La règle correspondante la plus prioritaire l’emporte, puis l’ordre de configuration en cas d’égalité. La priorité par défaut est 0. Une route absente ou aucune règle applicable donne une réponse JSON 404.

### Expressions sur le corps de requête

Définissez `match.body_expression` à la place de `match.body`.

| Mode | Format de requête | Critère de correspondance |
| --- | --- | --- |
| `jsonpath` | JSON | Sélectionne au moins une valeur. Si `expected.value` est défini, au moins une valeur sélectionnée doit lui être strictement égale, type JSON compris. |
| `xpath` | XML | Utilise la valeur booléenne XPath 1.0. Avec une chaîne `expected.value`, compare la valeur textuelle de chaque nœud ou la représentation XPath d’une valeur scalaire. |
| `regex` | JSON ou XML | Recherche dans le corps d’origine avec une syntaxe de type RE2. `^` et `$` permettent d’ancrer la recherche. |

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

Utilisez `"expected": {"value": null}` pour reconnaître JSON null. JSONPath gère les propriétés, les sélecteurs de tableau, la descente récursive et les filtres. Les fonctions JSONPath `match()` et `search()` sont désactivées. Utilisez le mode dédié pour les expressions régulières.

XPath accepte les prédicats et expressions booléennes tels que `/order/item[@sku='paid']` ou `count(/order/item) > 0`. Associez les préfixes aux espaces de noms avec `"namespaces": [{"prefix":"o","uri":"urn:orders"}]`, puis écrivez `/o:order/o:item/@sku`. Un espace de noms par défaut doit également être associé à un préfixe utilisé dans l’expression.

Les expressions sont compilées au chargement ou à l’enregistrement de la configuration et limitées à 1024 octets. Un corps vide ne correspond à aucune expression. Le service valide le format du corps avant l’évaluation. JSONPath utilise les valeurs JSON par défaut déjà appliquées et le mode regex utilise les octets d’origine. JSONPath et XPath disposent d’un espace de travail de 16 Mio par requête. JSONPath accepte 128 niveaux JSON. Le dépassement d’une limite d’évaluation renvoie 400.

### Validation des requêtes et modèles de réponse

`request.format` vaut `json` par défaut. `request.body_required` rejette les requêtes sans corps. Un corps JSON facultatif absent est traité comme un objet vide. La validation des champs exige un objet et accepte `string`, `integer` (64 bits signé), `number` et `boolean`. Un champ peut être obligatoire ou avoir une valeur par défaut. Les champs supplémentaires sont conservés. Les valeurs par défaut sont appliquées avant la sélection et le rendu. Un corps ou un champ invalide renvoie 400.

Avec `response.template: true`, `{{body.name}}` lit un champ JSON de premier niveau ou le texte de l’enfant `name` de la racine XML. Les champs JSON référencés doivent être obligatoires ou avoir une valeur par défaut. XML accepte les chemins imbriqués comme `{{body.customer.name}}` et les attributs comme `{{body.@id}}` ou `{{body.customer.@id}}`. À chaque niveau, le premier enfant dont le nom et le préfixe correspondent, avec respect de la casse, est sélectionné. La valeur d’un élément inclut le texte de ses descendants. `{{body.age|add:1}}` ajoute une constante entière.

Insérez les valeurs dans des chaînes JSON, dans le texte des éléments XML ou dans des attributs XML ordinaires. Le service échappe le texte inséré selon le format et valide le XML généré. Une valeur absente, un argument non entier pour `add` ou un dépassement d’entier renvoie 400. Les modèles qui utilisent XML ont une limite de 4 Mio de texte dynamique. Les deux routes de modèles du dossier **Examples** illustrent JSON et XML.

### Réponses et limites

`response.body` est obligatoire et le statut par défaut est 200. Le format JSON par défaut utilise `application/json` et encode aussi les chaînes en JSON. Les réponses XML contiennent du XML UTF-8 avec `application/xml; charset=utf-8`. Un en-tête Content-Type personnalisé peut remplacer la valeur par défaut. L’encodage du corps dépend du format.

- Les statuts vont de 200 à 599. Les statuts 204, 205 et 304 exigent `body: null`. Ces statuts et HEAD n’envoient aucun corps.
- `delay_ms` va de 0 à 30000. Le verrou de configuration est relâché pendant l’attente du processus de traitement httpz.
- Le corps de requête est limité à 1 Mio et le fichier de configuration doit faire moins de 4 Mio. La configuration accepte au plus 1000 routes, 1000 règles par route et 32 en-têtes personnalisés par réponse.
- Le XML doit être bien formé, en UTF-8 et limité à 128 niveaux. Les documents avec une DTD sont rejetés.
- `/healthz`, `/admin`, `/admin/*`, `/viewer` et `/viewer/*` sont réservés. Un champ inconnu, une forme de route ou un identifiant de règle en double, un modèle invalide ou un en-tête interdit invalide la configuration. Le service gère Content-Length, Transfer-Encoding, Connection, Keep-Alive, Upgrade, Trailer, Vary et Access-Control-*.

## Rechargement, CORS et contrôle de santé

Remplacez de manière atomique le fichier défini par `MOCK_CONFIG`, puis appelez le rechargement. Pour un jeton généré, utilisez la valeur affichée au démarrage dans l’en-tête Bearer.

```powershell
Invoke-RestMethod http://127.0.0.1:9080/admin/reload -Method Post -Headers @{ Authorization = "Bearer $env:MOCK_ADMIN_TOKEN" }
```

Le rechargement lit uniquement le fichier local configuré et conserve le jeton d’administration. Un jeton absent ou invalide renvoie 401.

Un rechargement réussi renvoie `status`, `generation` et `routes`. Un fichier absent ou une configuration invalide renvoie 400 avec `reason` et conserve la configuration active. Une configuration initiale invalide empêche le démarrage. Les rechargements et enregistrements s’exécutent en série. Les requêtes en cours gardent leurs données de réponse pendant le changement.

Par défaut, CORS autorise toutes les origines sans identifiants entre origines. Dans `cors.origins`, indiquez les origines exactes avec leur schéma et leur port, sans barre oblique finale. Un tableau vide désactive CORS. `*` s’utilise seul. La requête préliminaire valide l’origine, la méthode et les en-têtes. Les chemins d’administration et de catalogue ont une politique distincte. Une requête ordinaire d’une origine non autorisée peut être traitée sans recevoir d’en-têtes d’autorisation CORS.

`GET /healthz` indique `status: "ok"`, la `generation` active et le nombre de `routes`. Après un échec de rechargement, il signale la configuration encore active. HEAD est pris en charge. Les autres méthodes, hors OPTIONS, renvoient 405.

## Variables d’environnement

| Variable | Valeur par défaut | Rôle |
| --- | --- | --- |
| `MOCK_HOST` | `0.0.0.0` | Adresse d’écoute IPv4 ou IPv6. |
| `MOCK_PORT` | `9080` | Port d’écoute de 1 à 65535. |
| `MOCK_CONFIG` | `config/mock.json` | Chemin de configuration. Un chemin relatif part du répertoire de travail du processus. |
| `MOCK_ADMIN_TOKEN` | Généré | Jeton d’administration fixe facultatif d’au moins 16 octets. |

## Limitation de débit

Dans la console, ouvrez la section de limitation de débit de la route. Indiquez le nombre de requêtes par seconde et par client, puis éventuellement des valeurs par IP comme `{"192.0.2.10":20,"2001:db8::1":0}`. Les valeurs sont des entiers de 0 à 10000. Zéro signifie illimité. La route utilise `rate_limit.requests_per_second` et `rate_limit.clients`.

Chaque processus compte les requêtes acceptées pendant la dernière seconde par IP cliente, méthode et route configurée. Les variantes de chemin et de requête et les scénarios partagent le quota du client pour la route. Un dépassement renvoie 429 et `Retry-After: 1`. Si la capacité de suivi est atteinte, une nouvelle requête renvoie 503 avec le même en-tête. Les nouvelles limites s’appliquent dès l’enregistrement, avec conservation des compteurs actifs.

Les routes inconnues, les contrôles de santé, les requêtes d’administration et de catalogue et les requêtes OPTIONS ne consomment pas le quota.

L’adresse de la connexion identifie le client par défaut. Définissez `trusted_proxies`, par exemple `["127.0.0.1"]`, pour accepter `X-Forwarded-For` des proxys indiqués. Dans cette configuration, rendez le serveur accessible uniquement aux proxys de confiance. Dans une chaîne, le dernier proxy doit transmettre une seule adresse cliente vérifiée. [En-têtes du proxy inverse Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#headers)

## Exécution avec Docker

Construisez l’image Linux avec Docker. Nginx reçoit les requêtes HTTP et Zig Mock écoute sur l’adresse de bouclage du conteneur.

```sh
docker build -t zig-mock .
docker run -d --name zig-mock -p 127.0.0.1:18080:8080 -e MOCK_ADMIN_TOKEN -v zig-mock-data:/var/lib/zig-mock zig-mock
```

- Modifiez `18080` pour choisir le port de l’hôte. Nginx écoute sur le port `8080` du conteneur. Pour remplacer le port interne `9080` de Mock, ajoutez par exemple `-e MOCK_PORT=19080`.
- `-e MOCK_ADMIN_TOKEN` transmet le jeton depuis l’environnement du shell. Vous pouvez aussi le fournir avec `--env-file`. Un jeton fourni doit contenir au moins 16 octets. Si le jeton est absent ou vide, consultez `docker logs zig-mock` pour retrouver le jeton généré.
- Si le volume ne contient pas `mock.json`, il est initialisé à partir de `config/mock.json`. Réutilisez le volume lorsque vous remplacez le conteneur pour conserver les règles enregistrées. Pour appliquer la limitation de débit à chaque adresse IP cliente observée par Nginx, ajoutez `127.0.0.1` aux adresses de proxy de confiance dans la console et enregistrez.

Ouvrez la [console d’administration](http://127.0.0.1:18080/admin), le [catalogue en lecture seule](http://127.0.0.1:18080/viewer) ou le [point de contrôle de santé](http://127.0.0.1:18080/healthz). L’exemple publie le port HTTP sur l’adresse de bouclage de l’hôte. Pour un accès externe en HTTPS, utilisez les exemples de proxy inverse ci-dessous en ciblant le port publié sur l’hôte.

## Déploiement sous Linux

Les exemples de déploiement suivent le schéma `Client → Caddy ou Nginx (HTTPS) → 127.0.0.1:9080 → serveur Mock`. Exécutez les commandes de déploiement sur le serveur cible avec les privilèges d’administration.

Compilez pour l’architecture du serveur. La deuxième commande produit `zig-out/linux/bin/test_web` pour Linux x86_64 par compilation croisée. Pour ARM64, choisissez la cible correspondante et vérifiez le résultat sur le serveur cible.

```sh
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl -p zig-out/linux
```

Transférez l’exécutable et la configuration. Depuis le répertoire de transfert, créez un utilisateur système sans accès interactif et installez les fichiers.

```sh
sudo useradd --system --no-create-home --shell /usr/sbin/nologin mock
sudo install -d -m 0755 /opt/zig-mock /etc/zig-mock
sudo install -d -o mock -g mock -m 0750 /var/lib/zig-mock
sudo install -m 0755 test_web /opt/zig-mock/test_web
sudo install -o mock -g mock -m 0640 config/mock.json /var/lib/zig-mock/mock.json
sudo install -m 0600 deploy/mock.env.example /etc/zig-mock/mock.env
sudo install -m 0644 deploy/mock.service /etc/systemd/system/zig-mock.service
```

Pour utiliser un jeton fixe, définissez-le dans `/etc/zig-mock/mock.env`. Le service peut écrire dans `/var/lib/zig-mock/`. Seul root peut lire le fichier d’environnement.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now zig-mock
curl --fail http://127.0.0.1:9080/healthz
sudo journalctl -u zig-mock -n 50 --no-pager
```

Si un service systemd existant utilise `/etc/zig-mock/mock.json`, copiez ce fichier dans `/var/lib/zig-mock/`, attribuez-le à `mock:mock` et mettez à jour `MOCK_CONFIG` avant de redémarrer.

Rechargez la configuration après les changements JSON. Un changement de l’exécutable ou de l’environnement exige `sudo systemctl restart zig-mock`. Les messages de démarrage et le jeton généré sont disponibles dans journald.

### Caddy

Remplacez le domaine dans [l’exemple Caddy](../deploy/Caddyfile) et ajoutez le bloc de site à la configuration du serveur. Faites pointer le DNS vers le serveur et ouvrez les ports 80 et 443.

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

L’exemple par défaut transmet les requêtes Mock et bloque l’accès public à `/admin` et `/viewer`. Vérifiez HTTPS avec `/healthz` et une route d’exemple. Accédez à la console et au catalogue via `ssh -L 19080:127.0.0.1:9080 user@server` et le port local 19080, ou utilisez [l’autre exemple Caddy](../deploy/Caddyfile.admin.example) pour les publier en HTTPS. Dans ce cas, l’API d’administration exige toujours un jeton et les visiteurs pouvant joindre le domaine peuvent consulter le catalogue.

### Nginx

Pour publier les routes Mock, utilisez [la configuration Nginx par défaut](../deploy/nginx.conf.example). Elle bloque `/admin`, `/viewer` et leurs sous-chemins. Pour rendre les deux pages accessibles en HTTPS, utilisez plutôt [la variante avec administration](../deploy/nginx.admin.conf.example). L’API d’administration exige un jeton et le catalogue en lecture seule est accessible sans connexion.

Pointez le DNS vers le serveur, ouvrez les ports 80 et 443 et obtenez un certificat TLS pour le domaine. Installez une seule variante dans un répertoire inclus dans le bloc `http` de Nginx, généralement `/etc/nginx/conf.d/`. Remplacez les deux occurrences de `server_name mock.example.com` et indiquez la chaîne de certificats et la clé privée dans `ssl_certificate` et `ssl_certificate_key`.

```sh
# Use deploy/nginx.admin.conf.example as the source for the admin variant.
sudo install -m 0644 deploy/nginx.conf.example /etc/nginx/conf.d/zig-mock.conf
sudoedit /etc/nginx/conf.d/zig-mock.conf
sudo nginx -t
sudo systemctl reload nginx
curl --fail https://mock.example.com/healthz
```

Les deux variantes redirigent HTTP vers HTTPS et conservent les chemins encodés et les chaînes de requête lors du transfert. Nginx remplace l’en-tête entrant `X-Forwarded-For` par l’adresse de connexion qu’il a observée. Pour limiter le débit par client derrière ce proxy local, ajoutez `"trusted_proxies": ["127.0.0.1"]` à la configuration Mock et rechargez-la. [Module proxy de Nginx](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)

Le service ne journalise ni les corps de requête ni les jetons configurés manuellement. Configurez le contrôle d’accès au trafic Mock dans le proxy inverse si nécessaire.

## Vérification

```sh
zig fmt --check src/main.zig src/mock.zig src/app.zig src/body_match.zig src/jsonpath_regex.zig build.zig build.zig.zon
zig build test
zig build
python tests/integration.py
node --test tests/json-codec.test.cjs
```

Les tests d’intégration Python utilisent une configuration temporaire et un port local aléatoire. Vous pouvez fournir le chemin de l’exécutable, par exemple `python3 tests/integration.py /opt/zig-mock/test_web`.
