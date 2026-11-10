"""HTTP integration tests; starts an isolated server with a temporary config.

Run after `zig build`: python tests/integration.py [path/to/test_web]
Uses only the Python standard library. Never edits config/mock.json.
"""
import concurrent.futures
import copy
import http.client
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
EXE = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else ROOT / "zig-out/bin" / ("test_web.exe" if os.name == "nt" else "test_web")
TOKEN = "integration-test-token-32-characters"


class MockServer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="zig-mock-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.config_path = Path(cls.temp.name) / "mock.json"
        cls.baseline = json.loads((ROOT / "config/mock.json").read_text(encoding="utf-8"))
        cls.write_config(cls.baseline)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            cls.port = sock.getsockname()[1]
        cls.env = dict(os.environ, MOCK_HOST="127.0.0.1", MOCK_PORT=str(cls.port),
                       MOCK_CONFIG=str(cls.config_path), MOCK_ADMIN_TOKEN=TOKEN)
        cls.log = (Path(cls.temp.name) / "server.log").open("wb")
        cls.addClassCleanup(cls.log.close)
        cls.process = subprocess.Popen([str(EXE)], env=cls.env, stdout=cls.log, stderr=cls.log,
                                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        cls.addClassCleanup(cls.stop_server)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if cls.process.poll() is not None:
                raise RuntimeError((Path(cls.temp.name) / "server.log").read_text(errors="replace"))
            try:
                if cls.request("GET", "/healthz")[0] == 200:
                    return
            except OSError:
                pass
            time.sleep(0.05)
        raise RuntimeError("Server did not become healthy")

    @classmethod
    def stop_server(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait()

    @classmethod
    def write_config(cls, config):
        staging = cls.config_path.with_suffix(".tmp")
        staging.write_text(json.dumps(config, ensure_ascii=False), encoding="utf-8")
        os.replace(staging, cls.config_path)

    @classmethod
    def request(cls, method, path, body=None, headers=None, *, port=None):
        headers = dict(headers or {})
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
            headers.setdefault("Content-Type", "application/json")
        conn = http.client.HTTPConnection("127.0.0.1", cls.port if port is None else port, timeout=10)
        try:
            conn.request(method, path, body=body, headers=headers)
            response = conn.getresponse()
            data = response.read()
            received = dict((k.lower(), v) for k, v in response.getheaders())
            parsed = (json.loads(data) if 'application/json' in received.get('content-type', '') else data.decode('utf-8')) if data else None
            return response.status, received, parsed
        finally:
            conn.close()

    def admin_config(self):
        return self.request('GET', '/admin/api/config', headers={'Authorization': f'Bearer {TOKEN}'})

    def save_config(self, config, revision):
        return self.request('PUT', '/admin/api/config', config, {
            'Authorization': f'Bearer {TOKEN}', 'If-Match': f'"{revision}"'})


class MockServiceTests(MockServer):
    def reload(self, config=None):
        if config is not None:
            self.write_config(config)
        return self.request("POST", "/admin/reload", headers={"Authorization": f"Bearer {TOKEN}"})

    def setUp(self):
        self.assertEqual(self.reload(copy.deepcopy(self.baseline))[0], 200)

    def test_admin_assets_and_protected_config(self):
        for path, mime in (('/admin/', 'text/html'), ('/admin', 'text/html'),
                           ('/admin/app.js', 'text/javascript'), ('/admin/style.css', 'text/css')):
            status, headers, body = self.request('GET', path)
            self.assertEqual(status, 200)
            self.assertIn(mime, headers['content-type'])
            self.assertIn("frame-ancestors 'none'", headers['content-security-policy'])
            self.assertEqual(headers['cache-control'], 'no-store')
            self.assertNotIn(TOKEN, body)
        self.assertEqual(self.request('GET', '/admin/api/config')[0], 401)
        self.assertEqual(self.request('PUT', '/admin/api/config', self.baseline)[0], 401)
        status, headers, body = self.admin_config()
        self.assertEqual(status, 200)
        self.assertEqual(headers['etag'], f'"{body["revision"]}"')
        self.assertEqual(len(body['revision']), 64)
        self.assertEqual(body['config']['routes'][0]['path'], '/hello/test')

    def test_admin_create_update_delete_persists_and_activates(self):
        data = self.admin_config()[2]
        config = data['config']
        config['routes'].append({'method': 'GET', 'path': '/online', 'rules': [
            {'id': 'online', 'response': {'body': {'message': 'created'}}}]})
        status, _, created = self.save_config(config, data['revision'])
        self.assertEqual(status, 200)
        self.assertEqual(self.request('GET', '/online')[2], {'message': 'created'})
        self.assertEqual(json.loads(self.config_path.read_text(encoding='utf-8'))['routes'][-1]['path'], '/online')
        created['config']['routes'][-1]['rules'][0]['response'].update(status=201, body={'message': 'updated'})
        status, _, updated = self.save_config(created['config'], created['revision'])
        self.assertEqual(status, 200)
        self.assertEqual(self.request('GET', '/online')[::2], (201, {'message': 'updated'}))
        self.assertEqual(self.reload()[0], 200)
        self.assertEqual(self.request('GET', '/online')[2]['message'], 'updated')
        updated['config']['routes'].pop()
        self.assertEqual(self.save_config(updated['config'], updated['revision'])[0], 200)
        self.assertEqual(self.request('GET', '/online')[0], 404)
        self.assertEqual(len(json.loads(self.config_path.read_text(encoding='utf-8'))['routes']), 2)

    def test_viewer_reads_current_catalog_without_write_access(self):
        current = self.admin_config()[2]
        path = '/viewer/api/catalog'
        status, _, page = self.request('GET', '/viewer')
        self.assertEqual(status, 200)
        self.assertNotIn('type="password"', page)
        self.assertIn('/viewer/assets/viewer.js', page)
        self.assertEqual(self.request('GET', '/viewer/assets/viewer.js')[0], 200)
        self.assertEqual(self.request('GET', '/admin/viewer/api/config')[0], 404)
        status, headers, snapshot = self.request('GET', path, headers={'Origin': 'https://frontend.example'})
        self.assertEqual(status, 200)
        self.assertNotIn('access-control-allow-origin', headers)
        self.assertEqual(set(snapshot), {'generation', 'catalog'})
        self.assertEqual(snapshot['generation'], current['generation'])
        catalog = snapshot['catalog']
        self.assertEqual(set(catalog), {'folders', 'routes'})
        self.assertEqual(catalog['folders'], current['config'].get('folders', []))
        hello, order = catalog['routes']
        self.assertEqual(set(hello), {'method', 'path', 'folder_id', 'request', 'rules'})
        self.assertEqual((hello['method'], hello['path']), ('POST', '/hello/test'))
        self.assertEqual(hello['request']['fields'][0]['name'], 'name')
        self.assertEqual(order['rules'][0]['match']['body'], {'pay_method': 'UnionPay'})
        self.assertEqual(order['rules'][0]['response']['body'], current['config']['routes'][1]['rules'][0]['response']['body'])
        for method in ('PUT', 'POST', 'DELETE'):
            status, headers, _ = self.request(method, path)
            self.assertEqual((status, headers['allow']), (405, 'GET'))
        self.assertEqual(self.request('GET', '/admin/api/config')[0], 401)
        self.assertEqual(self.request('PUT', '/admin/api/config', current['config'], {
            'If-Match': f'"{current["revision"]}"'})[0], 401)
        self.assertEqual(self.request('POST', '/admin/reload')[0], 401)
        config = copy.deepcopy(current['config'])
        for reserved_path in ('/viewer', path):
            config['routes'][0]['path'] = reserved_path
            status, _, error = self.save_config(config, current['revision'])
            self.assertEqual((status, error['reason']), (400, 'ReservedPath'))
        self.assertEqual(self.admin_config()[2], current)

    def test_admin_persists_folders_and_rejects_invalid_tree(self):
        data = self.admin_config()[2]
        config = data['config']
        config['folders'] = [
            {'id': 'examples', 'name': '示例'},
            {'id': 'hello', 'name': '问候', 'parent_id': 'examples'},
            {'id': 'empty', 'name': '空目录'},
        ]
        config['routes'][0]['folder_id'] = 'hello'
        status, _, saved = self.save_config(config, data['revision'])
        self.assertEqual(status, 200)
        self.assertEqual(self.reload()[0], 200)
        self.assertEqual(self.admin_config()[2]['config'], config)
        self.assertEqual(self.request('POST', '/hello/test', {})[0], 200)

        invalid = copy.deepcopy(config)
        invalid['folders'][0]['parent_id'] = 'hello'
        status, _, rejected = self.save_config(invalid, saved['revision'])
        self.assertEqual((status, rejected['reason']), (400, 'FolderCycle'))
        invalid = copy.deepcopy(config)
        invalid['routes'][0]['folder_id'] = 'missing'
        status, _, rejected = self.save_config(invalid, saved['revision'])
        self.assertEqual((status, rejected['reason']), (400, 'UnknownRouteFolder'))
        self.assertEqual(json.loads(self.config_path.read_text(encoding='utf-8')), config)

    def test_admin_conflicts_and_invalid_save_preserve_disk_and_memory(self):
        original = self.config_path.read_bytes()
        data = self.admin_config()[2]
        invalid = copy.deepcopy(data['config'])
        invalid['routes'][0]['rules'][0]['response']['status'] = 999
        self.assertEqual(self.save_config(invalid, data['revision'])[0], 400)
        self.assertEqual(self.config_path.read_bytes(), original)
        self.assertEqual(self.admin_config()[2]['revision'], data['revision'])
        self.assertEqual(self.request('PUT', '/admin/api/config', data['config'],
                                     {'Authorization': f'Bearer {TOKEN}'})[0], 428)
        config = copy.deepcopy(data['config'])
        config['routes'][0]['rules'][0]['response']['delay_ms'] = 1
        self.assertEqual(self.save_config(config, data['revision'])[0], 200)
        saved = self.config_path.read_bytes()
        self.assertEqual(self.save_config(data['config'], data['revision'])[0], 409)
        self.assertEqual(self.config_path.read_bytes(), saved)
        current = self.admin_config()[2]
        self.config_path.write_bytes(saved + b'\n')
        self.assertEqual(self.save_config(current['config'], current['revision'])[0], 409)
        self.assertEqual(self.config_path.read_bytes(), saved + b'\n')
        self.config_path.unlink()
        self.assertEqual(self.save_config(current['config'], current['revision'])[0], 500)
        self.assertEqual(self.admin_config()[2]['revision'], current['revision'])

    def test_admin_concurrent_edit_rejects_stale_writer(self):
        data = self.admin_config()[2]
        def save_variant(n):
            config = copy.deepcopy(data['config'])
            config['routes'][0]['rules'][0]['response']['delay_ms'] = n
            return self.save_config(config, data['revision'])[0]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            statuses = list(pool.map(save_variant, [1, 2]))
        self.assertEqual(sorted(statuses), [200, 409])
        current = self.admin_config()[2]
        disk = json.loads(self.config_path.read_text(encoding='utf-8'))
        self.assertEqual(current['config'], disk)

    def test_admin_roundtrip_preserves_numeric_match_types(self):
        data = self.admin_config()[2]
        raw = b'{"routes":[{"method":"POST","path":"/numbers","rules":[{"id":"float","match":{"body":{"v":1.0}},"response":{"body":{"id":9223372036854775807}}}]}]}'
        self.assertEqual(self.save_config(raw, data['revision'])[0], 200)
        self.assertEqual(self.request('POST', '/numbers', b'{"v":1.0}')[0], 200)
        self.assertEqual(self.request('POST', '/numbers', b'{"v":1}')[0], 404)
        config = self.admin_config()[2]['config']
        self.assertIsInstance(config['routes'][0]['rules'][0]['match']['body']['v'], float)
        self.assertEqual(config['routes'][0]['rules'][0]['response']['body']['id'], 9223372036854775807)

    def test_migrated_hello_and_validation(self):
        status, _, body = self.request("POST", "/hello/test", {"name": '小"明', "age": 20, "ignored": True})
        self.assertEqual(status, 200)
        self.assertEqual(body, {"message": '小"明明年这个时候你是21岁', "code": 200})
        self.assertEqual(self.request("POST", "/hello/test", {})[2]["message"], "明年这个时候你是1岁")
        for invalid in (b"{", b"[]", b"null", {"age": "20"}, {"email": 1}):
            self.assertEqual(self.request("POST", "/hello/test", invalid)[0], 400)
        self.assertEqual(self.request("POST", "/hello/test")[2]["message"], "missing request body")
        self.assertEqual(self.request("POST", "/hello/test", {"age": 9223372036854775807})[0], 400)
        self.assertEqual(self.request("GET", "/healthz")[0], 200)

    def test_xml_request_matching_and_raw_responses(self):
        pattern = '<order>\r\n<id>7</id>\r\n</order>'
        reply = '<?xml version="1.0" encoding="UTF-8"?><accepted>收到 &amp; 确认</accepted>'
        config = {'routes': [
            {'method': 'POST', 'path': '/xml', 'request': {'format': 'xml', 'body_required': True}, 'rules': [
                {'id': 'accepted', 'priority': 10, 'match': {
                    'body': pattern, 'query': [{'name': 'mode', 'value': 'submit'}],
                }, 'response': {'format': 'xml', 'status': 201, 'body': reply}},
                {'id': 'fallback', 'response': {'body': {'matched': False}}},
            ]},
            {'method': 'POST', 'path': '/xml-output', 'rules': [
                {'id': 'ok', 'match': {'body': {'valid': True}}, 'response': {
                    'format': 'xml', 'body': '<ok/>',
                    'headers': [{'name': 'Content-Type', 'value': 'application/soap+xml; charset=utf-8'}],
                }},
            ]},
            {'method': 'GET', 'path': '/xml-empty', 'request': {'format': 'xml'}, 'rules': [
                {'id': 'empty', 'response': {'format': 'xml', 'status': 204, 'body': None}},
            ]},
        ]}
        revision = self.admin_config()[2]['revision']
        self.assertEqual(self.save_config(config, revision)[0], 200)
        payload = ('\ufeff ' + pattern.replace('\r\n', '\n') + '\n').encode('utf-8')
        xml_headers = {'Content-Type': 'application/xml; charset=utf-8'}
        status, headers, body = self.request('POST', '/xml?mode=submit', payload, xml_headers)
        self.assertEqual((status, headers['content-type'], body), (201, 'application/xml; charset=utf-8', reply))
        self.assertEqual(self.request('POST', '/xml', payload, xml_headers)[2], {'matched': False})
        self.assertEqual(self.request('POST', '/xml?mode=submit', b'<order><id>7</id></order>', xml_headers)[2], {'matched': False})
        for invalid in (None, b'{}', b'<order></wrong>', b'<order/><extra/>', b'<order>&missing;</order>',
                        b'<order>\xff</order>', b'<!DOCTYPE order SYSTEM "file:///test"><order/>'):
            self.assertEqual(self.request('POST', '/xml', invalid, xml_headers)[0], 400, invalid)
        status, headers, body = self.request('POST', '/xml-output', {'valid': True})
        self.assertEqual((status, headers['content-type'], body), (200, 'application/soap+xml; charset=utf-8', '<ok/>'))
        self.assertEqual(self.request('GET', '/xml-empty')[::2], (204, None))
        catalog = self.request('GET', '/viewer/api/catalog')[2]['catalog']['routes']
        self.assertEqual(catalog[0]['request']['format'], 'xml')
        self.assertEqual(catalog[0]['rules'][0]['response']['body'], reply)

        for path, key, invalid in (
            (('request',), 'fields', [{'name': 'id', 'type': 'integer'}]),
            (('rules', 0, 'match'), 'body', {'id': 7}),
            (('rules', 0, 'response'), 'body', '<unclosed>'),
        ):
            invalid_config = copy.deepcopy(config)
            target = invalid_config['routes'][0]
            for part in path:
                target = target[part]
            target[key] = invalid
            self.assertEqual(self.save_config(invalid_config, self.admin_config()[2]['revision'])[0], 400)
        self.assertEqual(self.reload()[0], 200)
        self.assertEqual(self.request('POST', '/xml?mode=submit', payload, xml_headers)[::2], (201, reply))

    def test_xml_templates_extract_and_escape_request_values(self):
        template = ('<result id="{{body.@id}}"><name>{{body.name}}</name>'
                    '<age>{{body.customer.age|add:1}}</age><text>{{body.customer}}</text>'
                    '<code>{{body.m:code}}</code></result>')
        config = {'routes': [
            {'method': 'POST', 'path': '/xml-template', 'request': {'format': 'xml'}, 'rules': [
                {'id': 'ok', 'response': {'format': 'xml', 'template': True, 'body': template}},
            ]},
            {'method': 'POST', 'path': '/xml-to-json', 'request': {'format': 'xml'}, 'rules': [
                {'id': 'ok', 'response': {'template': True, 'body': {'age': '{{body.customer.age}}'}}},
            ]},
            {'method': 'POST', 'path': '/json-to-xml', 'request': {'fields': [
                {'name': 'name', 'type': 'string', 'required': True},
            ]}, 'rules': [
                {'id': 'ok', 'response': {'format': 'xml', 'template': True, 'body': '<result>{{body.name}}</result>'}},
            ]},
        ]}
        self.assertEqual(self.save_config(config, self.admin_config()[2]['revision'])[0], 200)
        payload = (b'<request xmlns:m="urn:mock" id="A&quot;&amp;&#10;B">'
                   b'<name>A &amp; <![CDATA[<B>]]></name><name>ignored</name>'
                   b'<customer><age> 7 </age><age>99</age></customer>'
                   b'<m:code>&#65;</m:code></request>')
        status, headers, result = self.request('POST', '/xml-template', payload)
        self.assertEqual((status, headers['content-type']), (200, 'application/xml; charset=utf-8'))
        self.assertIn('A &amp; &lt;B&gt;', result)
        root = ET.fromstring(result)
        self.assertEqual(root.get('id'), 'A"&\nB')
        self.assertEqual(root.findtext('name'), 'A & <B>')
        self.assertEqual(root.findtext('age'), '8')
        self.assertEqual(root.findtext('text'), ' 7 99')
        self.assertEqual(root.findtext('code'), 'A')
        for invalid in (None, b'<request/>', payload.replace(b' 7 ', b'not-an-integer'),
                        payload.replace(b' 7 ', b'9223372036854775807')):
            self.assertEqual(self.request('POST', '/xml-template', invalid)[0], 400)
        self.assertEqual(self.request('POST', '/xml-to-json', payload)[2], {'age': ' 7 '})
        injected = '<malicious/> & "text"'
        result = self.request('POST', '/json-to-xml', {'name': injected})[2]
        self.assertEqual(ET.fromstring(result).text, injected)
        self.assertEqual(self.request('POST', '/json-to-xml', {'name': '\0'})[0], 400)

        revision = self.admin_config()[2]['revision']
        for invalid in (
            '<result><!-- {{body.name}} --></result>',
            '<result><![CDATA[{{body.name}}]]></result>',
            '<?demo {{body.name}}?><result/>',
            '<result xmlns="{{body.name}}"/>',
            '<result>{{body.customer..age}}</result>',
            '<result>{{body.name</result>',
        ):
            broken = copy.deepcopy(config)
            broken['routes'][0]['rules'][0]['response']['body'] = invalid
            self.assertEqual(self.save_config(broken, revision)[0], 400, invalid)
        self.assertEqual(self.request('POST', '/xml-template', payload)[0], 200)

    def test_migrated_order(self):
        order = dict(product_name="test", product_id=1, order_id="o1", count=2, buyer_account="demo", pay_method="WeChat")
        self.assertEqual(self.request("POST", "/order", order)[2], {"code": 200, "message": "下单成功"})
        order["pay_method"] = "UnionPay"
        status, _, body = self.request("POST", "/order", order)
        self.assertEqual(status, 400)
        self.assertEqual(body["message"], "不支持银联支付方式")
        del order["count"]
        self.assertEqual(self.request("POST", "/order", order)[0], 400)

    def test_health_unknown_routes_and_methods(self):
        status, _, body = self.request("GET", "/healthz")
        self.assertEqual((status, body["status"], body["routes"]), (200, "ok", 2))
        self.assertEqual(self.request("HEAD", "/healthz")[2], None)
        self.assertEqual(self.request("POST", "/healthz")[0], 405)
        self.assertEqual(self.request("GET", "/missing")[0], 404)
        self.assertEqual(self.request("GET", "/order")[0], 404)

    def test_cors_preflight_and_errors(self):
        headers = {"Origin": "https://frontend.example", "Access-Control-Request-Method": "POST",
                   "Access-Control-Request-Headers": "content-type, AUTHORIZATION"}
        status, received, _ = self.request("OPTIONS", "/order", headers=headers)
        self.assertEqual(status, 204)
        self.assertEqual(received["access-control-allow-origin"], "*")
        self.assertNotIn("access-control-allow-credentials", received)
        for path in ("/healthz", "/missing"):
            self.assertEqual(self.request("GET", path, headers={"Origin": "https://frontend.example"})[1]["access-control-allow-origin"], "*")
        headers["Access-Control-Request-Headers"] = "x-not-allowed"
        self.assertEqual(self.request("OPTIONS", "/order", headers=headers)[0], 403)
        config = copy.deepcopy(self.baseline)
        config["cors"]["origins"] = ["https://allowed.example"]
        self.assertEqual(self.reload(config)[0], 200)
        headers["Access-Control-Request-Headers"] = "content-type"
        self.assertEqual(self.request("OPTIONS", "/order", headers=headers)[0], 403)
        headers["Origin"] = "https://allowed.example"
        self.assertEqual(self.request("OPTIONS", "/order", headers=headers)[1]["access-control-allow-origin"], headers["Origin"])
        self.assertNotIn("access-control-allow-origin", self.request("POST", "/admin/reload", headers=headers)[1])

    def test_reload_auth_and_invalid_config_rollback(self):
        generation = self.request("GET", "/healthz")[2]["generation"]
        self.assertEqual(self.request("POST", "/admin/reload")[0], 401)
        self.assertEqual(self.request("POST", "/admin/reload", headers={"Authorization": "Bearer wrong"})[0], 401)
        self.assertEqual(self.request("GET", "/admin/reload")[0], 405)
        invalid_configs = []
        for modify in (
            lambda c: c.update(typo=True),
            lambda c: c["routes"][0]["rules"][0]["response"].update(status=999),
            lambda c: c["routes"][0].update(path="/healthz"),
            lambda c: c["routes"].append(copy.deepcopy(c["routes"][0])),
            lambda c: c["routes"][0]["rules"][0]["response"].update(body="{{body.unknown}}"),
            lambda c: c["routes"][0]["rules"][0]["response"].update(headers=[{"name": "X-Bad", "value": "x\r\ninjected: true"}]),
            lambda c: c["routes"][0]["rules"][0]["response"].update(headers=[{"name": "Content-Length", "value": "1"}]),
        ):
            config = copy.deepcopy(self.baseline)
            modify(config)
            invalid_configs.append(config)
        for config in invalid_configs:
            self.assertEqual(self.reload(config)[0], 400)
            self.assertEqual(self.request("GET", "/healthz")[2]["generation"], generation)
            self.assertEqual(self.request("POST", "/hello/test", {})[0], 200)
        self.config_path.write_text("{", encoding="utf-8")
        self.assertEqual(self.reload()[0], 400)
        self.config_path.unlink()
        self.assertEqual(self.reload()[0], 400)
        self.assertEqual(self.request("GET", "/healthz")[2]["generation"], generation)

    def test_matching_priority_query_headers_and_no_match(self):
        config = copy.deepcopy(self.baseline)
        config["routes"].append({"method": "POST", "path": "/match", "rules": [
            {"id": "fallback", "priority": -1, "response": {"body": "fallback"}},
            {"id": "first", "priority": 10, "match": {"body": {"nested": {"n": 1}, "items": [1, 2]},
                 "query": [{"name": "q", "value": "hello world"}], "headers": [{"name": "X-Scenario", "value": "yes"}]},
             "response": {"status": 201, "headers": [{"name": "X-Mock", "value": "first"}], "body": {"selected": "first"}}},
            {"id": "tie", "priority": 10, "match": {"body": {"nested": {"n": 1}}}, "response": {"body": "tie"}}
        ]})
        self.assertEqual(self.reload(config)[0], 200)
        payload = {"nested": {"n": 1, "extra": True}, "items": [1, 2]}
        status, headers, body = self.request("POST", "/match?q=hello%20world", payload, {"x-scenario": "yes"})
        self.assertEqual((status, headers["x-mock"], body["selected"]), (201, "first", "first"))
        self.assertEqual(self.request("POST", "/match", payload)[2], "tie")
        self.assertEqual(self.request("POST", "/match", {"nested": {"n": "1"}})[2], "fallback")
        config["routes"][-1]["rules"] = config["routes"][-1]["rules"][1:2]
        self.assertEqual(self.reload(config)[0], 200)
        self.assertEqual(self.request("POST", "/match", {})[0], 404)

    def test_url_query_matching_decodes_names_and_values(self):
        config = {"routes": [{"method": "GET", "path": "/query", "rules": [
            {"id": "query", "priority": 1, "match": {"query": [
                {"name": "状态", "value": "paid + shipped"},
                {"name": "flag", "value": ""},
            ]}, "response": {"body": "matched"}},
            {"id": "fallback", "response": {"body": "fallback"}},
        ]}]}
        self.assertEqual(self.save_config(config, self.admin_config()[2]["revision"])[0], 200)
        name = "%E7%8A%B6%E6%80%81"
        target = f"{name}=paid+%2B+shipped"
        for query in (f"flag=&{target}", f"{target}&flag&extra=1", f"{target}&{name}=other&flag"):
            self.assertEqual(self.request("GET", f"/query?{query}")[2], "matched")
        for query in (target, f"{target}&flag=no", f"{name}=other&{target}&flag"):
            self.assertEqual(self.request("GET", f"/query?{query}")[2], "fallback")
        self.assertEqual(self.request("GET", "/query?flag=%ZZ")[0], 400)

    def test_url_path_templates_and_parameter_conditions(self):
        def route(path, value):
            return {"method": "GET", "path": path, "rules": [{"id": "fallback", "response": {"body": value}}]}

        config = {"routes": [
            route("/{collection}/{id}/items/{item}", "generic"),
            route("/orders/{id}/items/{item}", "order-item"),
            route("/orders/{id}", "order"),
            route("/{collection}/42", "tie"),
            route("/orders/latest", "latest"),
        ]}
        config["routes"][1]["rules"].append({
            "id": "selected", "priority": 10,
            "match": {
                "path": [{"name": "id", "value": "a/b"}, {"name": "item", "value": "a+b"}],
                "query": [{"name": "detail", "value": "yes"}],
            },
            "response": {"body": "selected"},
        })
        self.assertEqual(self.save_config(config, self.admin_config()[2]["revision"])[0], 200)
        self.assertEqual(self.request("GET", "/orders/latest")[2], "latest")
        self.assertEqual(self.request("GET", "/orders/42")[2], "order")
        self.assertEqual(self.request("GET", "/orders/a%2Fb/items/a+b?detail=yes")[2], "selected")
        self.assertEqual(self.request("GET", "/orders/a%2Fb/items/a%2Bb?detail=yes")[2], "selected")
        self.assertEqual(self.request("GET", "/orders/a%2Fb/items/a+b")[2], "order-item")
        self.assertEqual(self.request("GET", "/orders/other/items/a+b?detail=yes")[2], "order-item")
        self.assertEqual(self.request("GET", "/products/1/items/2")[2], "generic")
        for path in ("/orders/", "/orders/42/", "/orders/a/b/items/a+b"):
            self.assertEqual(self.request("GET", path)[0], 404)
        self.assertEqual(self.request("GET", "/orders/%ZZ")[0], 400)

        catalog = self.request("GET", "/viewer/api/catalog")[2]["catalog"]["routes"]
        self.assertEqual(catalog[1]["rules"][1]["match"]["path"], config["routes"][1]["rules"][1]["match"]["path"])
        revision = self.admin_config()[2]["revision"]
        for invalid_route, reason in (
            (route("/orders/{orderId}", "duplicate"), "DuplicateRoute"),
            (route("/users/{id}/{id}", "duplicate-name"), "DuplicatePathParameter"),
            (route("/users/{1id}", "invalid-name"), "InvalidPathParameter"),
            ({"method": "GET", "path": "/fixed", "rules": [{
                "id": "invalid", "match": {"path": [{"name": "id", "value": "42"}]}, "response": {"body": None},
            }]}, "InvalidPathMatch"),
        ):
            invalid = {"routes": config["routes"] + [invalid_route]}
            status, _, error = self.save_config(invalid, revision)
            self.assertEqual((status, error["reason"]), (400, reason))
        self.assertEqual(self.request("GET", "/orders/latest")[2], "latest")

    def test_reload_during_delayed_responses_keeps_snapshot_alive(self):
        config = copy.deepcopy(self.baseline)
        route = {"method": "GET", "path": "/snapshot", "rules": [{"id": "snapshot", "response": {
            "delay_ms": 400, "headers": [{"name": "X-Snapshot", "value": "old"}], "body": {"snapshot": "old"}}}]}
        config["routes"].append(route)
        self.assertEqual(self.reload(config)[0], 200)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            started = time.monotonic()
            pending = [pool.submit(self.request, "GET", "/snapshot") for _ in range(8)]
            time.sleep(0.1)
            route["rules"][0]["response"].update(delay_ms=0, headers=[{"name": "X-Snapshot", "value": "new"}], body={"snapshot": "new"})
            self.assertEqual(self.reload(config)[0], 200)
            for future in pending:
                status, headers, body = future.result()
                self.assertEqual(status, 200)
                self.assertIn(body["snapshot"], ("old", "new"))
                self.assertEqual(headers["x-snapshot"], body["snapshot"])
            self.assertGreaterEqual(time.monotonic() - started, 0.35)
        self.assertEqual(self.request("GET", "/snapshot")[2]["snapshot"], "new")

    def test_removed_route_and_no_content(self):
        config = {"routes": [{"method": "DELETE", "path": "/empty", "rules": [
            {"id": "empty", "response": {"status": 204, "body": None}}]}]}
        self.assertEqual(self.reload(config)[0], 200)
        self.assertEqual(self.request("POST", "/hello/test", {})[0], 404)
        self.assertEqual(self.request("DELETE", "/empty")[::2], (204, None))

    def test_startup_rejects_invalid_config_and_short_token(self):
        self.config_path.write_text("{", encoding="utf-8")
        result = subprocess.run([str(EXE)], env=self.env, capture_output=True, timeout=10,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"cannot load", result.stderr)
        self.write_config(self.baseline)
        result = subprocess.run([str(EXE)], env=dict(self.env, MOCK_ADMIN_TOKEN="short"),
                                capture_output=True, timeout=10,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"AdminTokenTooShort", result.stderr)

    def test_generated_admin_token_when_missing_or_empty(self):
        configured_log = Path(self.log.name).read_text(encoding="utf-8", errors="replace")
        self.assertTrue(TOKEN not in configured_log, "Configured token appeared in startup output")
        self.assertTrue("Generated admin token:" not in configured_log)
        generated = set()
        for mode in ("missing", "empty"):
            with self.subTest(mode=mode):
                with socket.socket() as sock:
                    sock.bind(("127.0.0.1", 0))
                    port = sock.getsockname()[1]
                env = dict(self.env, MOCK_PORT=str(port))
                if mode == "missing":
                    del env["MOCK_ADMIN_TOKEN"]
                else:
                    env["MOCK_ADMIN_TOKEN"] = ""
                log_path = Path(self.temp.name) / f"server-token-{mode}.log"
                with log_path.open("wb") as log:
                    process = subprocess.Popen([str(EXE)], env=env, stdout=log, stderr=log,
                                               creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                    try:
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            if process.poll() is not None:
                                self.fail("Isolated server exited early")
                            try:
                                if self.request("GET", "/healthz", port=port)[0] == 200:
                                    break
                            except OSError:
                                pass
                            time.sleep(0.05)
                        else:
                            self.fail("Isolated server did not start")
                        output = log_path.read_text(encoding="utf-8", errors="replace")
                        tokens = re.findall(r"^Generated admin token: ([a-f0-9]{64})$", output, re.MULTILINE)
                        self.assertEqual(len(tokens), 1)
                        token = tokens[0]
                        self.assertTrue(token not in generated, "Generated token was reused")
                        generated.add(token)
                        self.assertEqual(self.request("GET", "/admin/", port=port)[0], 200)
                        self.assertEqual(self.request("GET", "/admin/api/config", port=port)[0], 401)
                        self.assertEqual(self.request("GET", "/admin/api/config",
                                                      headers={"Authorization": f"Bearer {token}"}, port=port)[0], 200)
                    finally:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()


class RateLimitTests(MockServer):
    def test_online_limits_isolate_clients_routes_and_methods(self):
        origin = "https://example.com"
        saved = self.admin_config()[2]
        config = saved["config"]
        for method, path in [("GET", "/limited"), ("POST", "/limited"), ("GET", "/other")]:
            config["routes"].append({"method": method, "path": path,
                                     "rules": [{"id": "ok", "response": {"body": {"ok": True}}}]})
        status, _, saved = self.save_config(config, saved["revision"])
        self.assertEqual(status, 200)
        self.assertEqual([self.request("GET", "/limited")[0] for _ in range(3)], [200] * 3)
        config = saved["config"]
        for route in config["routes"][-3:]:
            route["rate_limit"] = {"requests_per_second": 1}
        status, _, saved = self.save_config(config, saved["revision"])
        self.assertEqual(status, 200)
        self.assertEqual(self.request("GET", "/limited", headers={"X-Forwarded-For": "192.0.2.1"})[0], 200)
        self.assertEqual(self.request("GET", "/limited", headers={"X-Forwarded-For": "192.0.2.2"})[0], 429)

        config = saved["config"]
        config["trusted_proxies"] = ["127.0.0.1"]
        config["routes"][-3]["rate_limit"]["clients"] = [
            {"ip": "192.0.2.2", "requests_per_second": 2},
            {"ip": "2001:db8::1", "requests_per_second": 0},
        ]
        status, _, saved = self.save_config(config, saved["revision"])
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(self.config_path.read_text(encoding="utf-8")), saved["config"])

        def hit(ip, path="/limited", method="GET"):
            return self.request(method, path, headers={"Origin": origin, "X-Forwarded-For": ip})

        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            responses = list(pool.map(lambda _: hit("192.0.2.2"), range(6)))
        self.assertEqual(sorted(code for code, _, _ in responses), [200, 200, 429, 429, 429, 429])
        for status, headers, body in responses:
            if status == 429:
                self.assertEqual(headers["retry-after"], "1")
                self.assertEqual(headers["access-control-allow-origin"], "*")
                self.assertEqual(headers["access-control-expose-headers"], "Retry-After")
                self.assertEqual(body["code"], 429)
        self.assertEqual(hit("192.0.2.1")[0], 200)
        self.assertEqual(hit("198.51.100.5, 192.0.2.1", "/limited?x=1")[0], 429)
        self.assertEqual(hit("192.0.2.1", "/other")[0], 200)
        self.assertEqual(hit("192.0.2.1", method="POST")[0], 200)
        self.assertEqual([hit("2001:db8:0::1")[0] for _ in range(3)], [200] * 3)
        self.assertEqual(hit("192.0.2.1", "/unknown")[0], 404)
        self.assertEqual(self.request("GET", "/healthz")[0], 200)
        self.assertEqual(self.admin_config()[0], 200)
        self.assertEqual(self.request("OPTIONS", "/limited", headers={
            "Origin": origin, "Access-Control-Request-Method": "GET",
        })[0], 204)

        config = saved["config"]
        config["routes"][-3]["rate_limit"]["clients"][0]["requests_per_second"] = 3
        status, _, saved = self.save_config(config, saved["revision"])
        self.assertEqual(status, 200)
        self.assertEqual(hit("192.0.2.2")[0], 200)
        self.assertEqual(hit("192.0.2.2")[0], 429)
        self.assertEqual(hit("192.0.2.1")[0], 429)
        invalid = copy.deepcopy(saved["config"])
        invalid["routes"][-3]["rate_limit"]["requests_per_second"] = 10001
        self.assertEqual(self.save_config(invalid, saved["revision"])[0], 400)
        self.assertEqual(self.admin_config()[2]["revision"], saved["revision"])
        time.sleep(1.05)
        self.assertEqual(hit("192.0.2.1")[0], 200)


if __name__ == "__main__":
    unittest.main(verbosity=2)
