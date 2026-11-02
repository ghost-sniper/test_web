'use strict';

const $ = id => document.getElementById(id);
const state = { token: '', config: null, revision: '', generation: 0, route: -1, rule: 0, dirty: false, busy: false, controller: null, resultTab: 'body' };
const pretty = value => MockJSON.stringify(value);
const clone = value => MockJSON.parse(pretty(value));
const currentRoute = () => state.config?.routes[state.route];
const currentRule = () => currentRoute()?.rules[state.rule];
const editorIds = ['routeMethod', 'routePath', 'requestSpec', 'ruleId', 'priority', 'matchBody', 'matchQuery', 'matchHeaders', 'status', 'delay', 'template', 'responseBody', 'responseHeaders'];

function notice(message, error = false) {
  $('notice').textContent = message;
  $('notice').classList.toggle('error', error);
  $('notice').hidden = false;
}
function markDirty() {
  state.dirty = true;
  $('dirtyLabel').hidden = false;
  $('testHint').textContent = '有未保存修改：测试仍使用服务器上已保存的规则。';
}
function setBusy(busy) {
  state.busy = busy;
  $('workbench').inert = busy;
  $('routeList').inert = busy;
  for (const id of ['addRoute', 'refresh', 'reload']) $(id).disabled = busy || !state.config;
  $('save').textContent = busy ? '正在保存…' : '保存并生效 ↗';
}
function confirmAction(title, message, action = '确认') {
  return new Promise(resolve => {
    $('confirmTitle').textContent = title;
    $('confirmMessage').textContent = message;
    $('confirmProceed').textContent = action;
    const dialog = $('confirmDialog');
    dialog.returnValue = '';
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true });
    dialog.showModal();
  });
}
$('confirmCancel').onclick = () => $('confirmDialog').close('cancel');
$('confirmProceed').onclick = () => $('confirmDialog').close('confirm');

async function api(path, options = {}) {
  const response = await fetch(path, { ...options, credentials: 'omit', cache: 'no-store', redirect: 'error', headers: {
    ...options.headers, Authorization: `Bearer ${state.token}`,
  } });
  const text = await response.text();
  let data;
  try { data = MockJSON.parse(text); } catch { throw new Error(`服务返回了无法解析的数据（HTTP ${response.status}）`); }
  if (!response.ok) {
    if (response.status === 401) throw new Error('管理 Token 无效或已更换，请重新连接服务。');
    if (response.status === 409) throw new Error('保存冲突：配置已被其他页面或文件编辑器修改。你的草稿已保留；请先备份修改，再刷新配置。外部文件修改需先重载文件。');
    throw new Error(`${data.message || '操作失败'}${data.reason ? ` · ${data.reason}` : ''}（HTTP ${response.status}）`);
  }
  return data;
}
function acceptConfig(data, selectedPath = null, selectedRule = null) {
  state.config = data.config;
  state.revision = data.revision;
  state.generation = data.generation;
  state.dirty = false;
  const selected = selectedPath ? state.config.routes.findIndex(r => `${r.method} ${r.path}` === selectedPath) : -1;
  state.route = selected >= 0 ? selected : (state.config.routes.length ? 0 : -1);
  state.rule = 0;
  if (selectedRule && currentRoute()) state.rule = Math.max(0, currentRoute().rules.findIndex(rule => rule.id === selectedRule));
  $('connectionState').textContent = '服务已连接';
  $('connectionDot').classList.add('connected');
  $('sessionButton').textContent = '断开连接';
  $('revisionLabel').textContent = `VERSION ${String(data.generation).padStart(2, '0')}`;
  $('emptyAction').textContent = '＋ 新建接口';
  render();
}
function renderList() {
  const list = $('routeList');
  list.replaceChildren();
  const query = $('search').value.trim().toLowerCase();
  $('routeCount').textContent = state.config?.routes.length || 0;
  for (const [index, route] of (state.config?.routes || []).entries()) {
    if (!`${route.method} ${route.path}`.toLowerCase().includes(query)) continue;
    const button = document.createElement('button');
    button.className = `route-item${state.route === index ? ' active' : ''}`;
    button.setAttribute('aria-current', state.route === index ? 'true' : 'false');
    const badge = document.createElement('span');
    badge.className = `method ${route.method.toLowerCase()}`;
    badge.textContent = route.method;
    const path = document.createElement('span');
    path.className = 'path'; path.textContent = route.path;
    button.title = `${route.method} ${route.path}`;
    button.append(badge, path);
    button.onclick = () => editAction(() => { collectRoute(); state.route = index; state.rule = 0; render(); });
    list.append(button);
  }
  if (!list.children.length) {
    const empty = document.createElement('p'); empty.className = 'sidebar-empty';
    empty.textContent = state.config ? '没有匹配的接口，试试新建一个。' : '连接服务后查看接口';
    list.append(empty);
  }
}
function render() {
  renderList();
  for (const id of ['addRoute', 'refresh', 'reload']) $(id).disabled = !state.config || state.busy;
  const route = currentRoute();
  $('workbench').hidden = !route;
  $('emptyState').hidden = !!route;
  if (!route) return;
  $('routeMethod').value = route.method;
  $('routePath').value = route.path;
  $('endpointPath').textContent = route.path;
  $('methodBadge').textContent = route.method;
  $('methodBadge').className = `method ${route.method.toLowerCase()}`;
  $('requestSpec').value = pretty(route.request || { body_required: false, fields: [] });
  $('dirtyLabel').hidden = !state.dirty;
  $('ruleCount').textContent = route.rules.length;
  $('ruleList').replaceChildren();
  route.rules.forEach((rule, index) => {
    const button = document.createElement('button');
    button.className = `rule-tab${index === state.rule ? ' active' : ''}`;
    button.textContent = `${index === state.rule ? '● ' : ''}${rule.id}`;
    button.setAttribute('role', 'tab');
    button.setAttribute('aria-selected', String(index === state.rule));
    button.onclick = () => editAction(() => { collectRoute(); state.rule = index; render(); });
    $('ruleList').append(button);
  });
  const rule = currentRule();
  $('ruleId').value = rule.id;
  $('priority').value = rule.priority || 0;
  $('status').value = rule.response.status ?? 200;
  $('delay').value = rule.response.delay_ms || 0;
  $('template').checked = !!rule.response.template;
  $('templateHint').hidden = !rule.response.template;
  $('responseBody').value = pretty(rule.response.body);
  $('responseHeaders').value = pretty(fromPairs(rule.response.headers));
  $('matchBody').value = pretty(rule.match?.body ?? null);
  $('matchQuery').value = pretty(fromPairs(rule.match?.query));
  $('matchHeaders').value = pretty(fromPairs(rule.match?.headers));
  $('matchDetails').open = !!(rule.match?.body || rule.match?.query?.length || rule.match?.headers?.length);
  $('deleteRule').disabled = route.rules.length === 1;
  $('deleteRule').title = route.rules.length === 1 ? '每个接口至少保留一个场景；也可删除整个接口' : '删除当前场景';
  fillExample();
}
function fromPairs(pairs = []) { return Object.fromEntries(pairs.map(pair => [pair.name, pair.value])); }
function parseJson(id, title, objectOnly = false) {
  let value;
  try { value = MockJSON.parse($(id).value); } catch (error) { $(id).focus(); throw new Error(`${title}不是有效的 JSON：${error.message}`); }
  if (objectOnly && (value === null || typeof value !== 'object' || Array.isArray(value) || MockJSON.isNumber(value))) {
    $(id).focus(); throw new Error(`${title}需要填写 JSON 对象。`);
  }
  return value;
}
function pairs(id, title) {
  return Object.entries(parseJson(id, title, true)).map(([name, value]) => {
    if (!name || typeof value !== 'string') throw new Error(`${title}的名称不能为空，值必须是字符串。`);
    return { name, value };
  });
}
function integer(id, title, min, max) {
  const value = Number($(id).value);
  if (!$(id).value.trim() || !Number.isInteger(value) || value < min || value > max) {
    $(id).focus(); throw new Error(`${title}需要是 ${min} 到 ${max} 之间的整数。`);
  }
  return value;
}
function collectRoute() {
  const route = currentRoute();
  if (!route) return;
  // Build the whole draft before mutating state, so syntax errors preserve it.
  const next = clone(route);
  next.method = $('routeMethod').value;
  next.path = $('routePath').value.trim();
  if (!/^\/(?!\/)/.test(next.path) || /[\s?#\\]/.test(next.path)) throw new Error('接口路径需以 / 开头，不能包含空白、反斜线或查询参数。');
  if (next.path === '/admin' || next.path.startsWith('/admin/') || next.path === '/healthz') throw new Error('该路径由管理服务保留，请换一个路径。');
  if (state.config.routes.some((other, i) => i !== state.route && other.method === next.method && other.path === next.path)) throw new Error('同一方法和路径的接口已存在。');
  next.request = parseJson('requestSpec', '请求配置', true);
  const rule = next.rules[state.rule];
  rule.id = $('ruleId').value.trim();
  if (!rule.id || next.rules.some((r, i) => i !== state.rule && r.id === rule.id)) throw new Error('场景 ID 不能为空，也不能与当前接口的其他场景重复。');
  rule.priority = integer('priority', '优先级', -2147483648, 2147483647);
  const bodyMatch = parseJson('matchBody', '请求体匹配条件');
  if (bodyMatch !== null && (typeof bodyMatch !== 'object' || Array.isArray(bodyMatch) || MockJSON.isNumber(bodyMatch))) throw new Error('请求体匹配条件需为 JSON 对象，或用 null 表示不限。');
  rule.match = { body: bodyMatch, query: pairs('matchQuery', '查询参数'), headers: pairs('matchHeaders', '请求头匹配条件') };
  rule.response = {
    ...rule.response, status: integer('status', '状态码', 200, 599), delay_ms: integer('delay', '延迟', 0, 30000),
    template: $('template').checked, body: parseJson('responseBody', '响应体'), headers: pairs('responseHeaders', '响应头'),
  };
  next.rules[state.rule] = rule;
  state.config.routes[state.route] = next;
}
function editAction(action) {
  if (state.busy) return;
  try { action(); } catch (error) { notice(error.message, true); }
}
function newRule(id) { return { id, priority: 0, response: { status: 200, body: { code: 200, message: 'ok' }, delay_ms: 0 } }; }
function uniqueId(base, existing) { let id = base, i = 2; while (existing.includes(id)) id = `${base}-${i++}`; return id; }
function addRoute() {
  if (!state.config) return $('loginDialog').showModal();
  editAction(() => {
    collectRoute();
    state.config.routes.push({ method: 'GET', path: uniqueId('/api/example', state.config.routes.map(r => r.path)), rules: [newRule('success')] });
    state.route = state.config.routes.length - 1; state.rule = 0; $('search').value = '';
    markDirty(); render(); $('routePath').focus(); $('routePath').select();
  });
}
function fillExample() {
  const route = currentRoute(), rule = currentRule();
  if (!route || !rule) return;
  if (!state.controller) {
    $('resultEmpty').hidden = false; $('result').hidden = true;
    $('resultBody').textContent = ''; $('resultHeaders').textContent = '';
    $('resultStatus').textContent = '等待请求'; $('resultStatus').className = 'result-status'; $('resultTime').textContent = '';
  }
  $('testMethod').value = route.method;
  const query = new URLSearchParams((rule.match?.query || []).map(pair => [pair.name, pair.value]));
  $('testPath').value = route.path + (query.size ? `?${query}` : '');
  const body = Object.create(null);
  for (const field of route.request?.fields || []) {
    if (field.default != null) body[field.name] = field.default;
    else if (field.required) body[field.name] = field.type === 'string' ? 'demo' : field.type === 'boolean' ? true : 1;
  }
  Object.assign(body, rule.match?.body || {});
  $('testBody').value = pretty(body);
  $('testHeaders').value = pretty({ 'Content-Type': 'application/json', ...fromPairs(rule.match?.headers) });
  updateTestMethod();
}
function updateTestMethod() {
  const noBody = ['GET', 'HEAD'].includes($('testMethod').value);
  $('testBody').disabled = noBody;
  $('testHint').textContent = `${noBody ? 'GET / HEAD 不发送请求体。' : ''}${state.dirty ? '有未保存修改：测试使用已保存的规则。' : '测试使用服务器上已保存的规则。'}`;
}
function showResultTab(tab) {
  state.resultTab = tab;
  for (const [id, name] of [['showBody', 'body'], ['showHeaders', 'headers']]) {
    $(id).classList.toggle('active', name === tab);
    $(id).setAttribute('aria-pressed', String(name === tab));
  }
  $('resultBody').hidden = tab !== 'body'; $('resultHeaders').hidden = tab !== 'headers';
}

async function sendRequest() {
  if (state.controller) { state.controller.abort(); return; }
  let url, headers;
  try {
    const input = $('testPath').value.trim();
    if (!input.startsWith('/') || input.startsWith('//') || /[\\\r\n]/.test(input)) throw new Error('只能测试当前服务的相对路径，例如 /order。');
    url = new URL(input, location.origin);
    const decoded = decodeURIComponent(url.pathname).replace(/\\/g, '/');
    if (url.origin !== location.origin || decoded === '/admin' || decoded.startsWith('/admin/')) throw new Error('测试面板只能调用当前服务的业务接口，不能调用管理接口。');
    headers = new Headers();
    for (const pair of pairs('testHeaders', '测试请求头')) headers.set(pair.name, pair.value);
  } catch (error) { notice(error.message, true); return; }
  const method = $('testMethod').value;
  state.controller = new AbortController();
  const controller = state.controller;
  const started = performance.now();
  const timeout = setTimeout(() => controller.abort(), 35000);
  $('send').textContent = '取消请求 ×'; $('send').classList.add('running');
  $('resultStatus').textContent = '请求中…'; $('resultStatus').className = 'result-status';
  $('resultTime').textContent = '';
  $('resultEmpty').hidden = true; $('result').hidden = false;
  $('resultBody').textContent = ''; $('resultHeaders').textContent = ''; showResultTab('body');
  try {
    const response = await fetch(url, {
      method, headers, body: ['GET', 'HEAD'].includes(method) ? undefined : ($('testBody').value || undefined),
      credentials: 'omit', redirect: 'manual', cache: 'no-store', referrerPolicy: 'no-referrer', signal: controller.signal,
    });
    if (response.type === 'opaqueredirect') throw new Error('接口返回了重定向；测试面板已阻止自动跳转。');
    const text = await response.text();
    $('resultStatus').textContent = `${response.status} ${response.statusText}`.trim();
    $('resultStatus').className = `result-status ${response.ok ? 'ok' : 'fail'}`;
    try { $('resultBody').textContent = pretty(MockJSON.parse(text)); } catch { $('resultBody').textContent = text || '（无响应体）'; }
    $('resultHeaders').textContent = [...response.headers].map(([key, value]) => `${key}: ${value}`).join('\n');
  } catch (error) {
    $('resultStatus').textContent = controller.signal.aborted ? '已取消 / 超时' : '发送失败';
    $('resultStatus').className = 'result-status fail';
    $('resultBody').textContent = controller.signal.aborted ? '请求已取消，或已超过 35 秒超时限制。' : error.message;
  } finally {
    clearTimeout(timeout); state.controller = null;
    $('resultTime').textContent = `${Math.round(performance.now() - started)} ms`;
    $('send').textContent = '发送请求 →'; $('send').classList.remove('running');
  }
}

$('loginForm').onsubmit = async event => {
  event.preventDefault();
  const previous = state.token;
  state.token = $('token').value.trim();
  $('loginSubmit').disabled = true; $('loginError').hidden = true;
  try {
    acceptConfig(await api('/admin/api/config'));
    $('token').value = ''; $('loginDialog').close(); $('notice').hidden = true;
  } catch (error) {
    state.token = previous; $('loginError').textContent = error.message; $('loginError').hidden = false;
  } finally { $('loginSubmit').disabled = false; }
};
$('loginCancel').onclick = () => { $('token').value = ''; $('loginDialog').close(); };
$('sessionButton').onclick = async () => {
  if (!state.config) return $('loginDialog').showModal();
  if (state.busy) return;
  if (state.dirty && !await confirmAction('断开服务连接？', '当前未保存的修改将丢失。', '断开连接')) return;
  state.controller?.abort(); state.token = ''; state.config = null; state.route = -1; state.dirty = false;
  $('connectionState').textContent = '未连接'; $('sessionButton').textContent = '连接服务';
  $('revisionLabel').textContent = '尚未连接'; $('emptyAction').textContent = '连接服务';
  $('resultBody').textContent = ''; $('resultHeaders').textContent = ''; $('notice').hidden = true;
  render();
};
$('save').onclick = async () => {
  if (state.busy) return;
  try {
    collectRoute();
    const selected = currentRoute() ? `${currentRoute().method} ${currentRoute().path}` : null;
    const selectedRule = currentRule()?.id;
    setBusy(true);
    const data = await api('/admin/api/config', { method: 'PUT', headers: { 'Content-Type': 'application/json', 'If-Match': `"${state.revision}"` }, body: pretty(state.config) });
    acceptConfig(data, selected, selectedRule);
    notice('已保存，配置立即生效。现在可以发送请求验证结果。');
  } catch (error) { notice(error.message, true); } finally { setBusy(false); }
};
$('refresh').onclick = async () => {
  if (state.busy) return;
  if (state.dirty && !await confirmAction('刷新服务器配置？', '这会放弃所有未保存的修改，并读取服务器当前配置。', '放弃修改并刷新')) return;
  setBusy(true);
  try { acceptConfig(await api('/admin/api/config')); notice('已读取服务器当前配置。'); }
  catch (error) { notice(error.message, true); } finally { setBusy(false); }
};
$('reload').onclick = async () => {
  if (state.busy || !await confirmAction('从磁盘重载配置？', '将加载配置文件中的内容。成功后，页面中未保存的修改会被替换。', '重载文件')) return;
  setBusy(true);
  try { await api('/admin/reload', { method: 'POST' }); acceptConfig(await api('/admin/api/config')); notice('配置文件已重新加载。'); }
  catch (error) { notice(error.message, true); } finally { setBusy(false); }
};
$('addRoute').onclick = addRoute;
$('emptyAction').onclick = addRoute;
$('search').oninput = renderList;
$('addRule').onclick = () => editAction(() => {
  collectRoute(); const route = currentRoute();
  route.rules.push(newRule(uniqueId('scenario', route.rules.map(r => r.id))));
  state.rule = route.rules.length - 1; markDirty(); render(); $('ruleId').focus();
});
$('copyRule').onclick = () => editAction(() => {
  collectRoute(); const route = currentRoute(), rule = clone(currentRule());
  rule.id = uniqueId(`${rule.id}-copy`, route.rules.map(r => r.id)); route.rules.push(rule);
  state.rule = route.rules.length - 1; markDirty(); render();
});
$('deleteRule').onclick = async () => {
  if (state.busy || currentRoute().rules.length === 1) return;
  try { collectRoute(); } catch (error) { notice(error.message, true); return; }
  if (!await confirmAction('删除当前场景？', `删除「${currentRule().id}」后，点击保存才会生效。`, '删除场景')) return;
  currentRoute().rules.splice(state.rule, 1); state.rule = 0; markDirty(); render();
};
$('deleteRoute').onclick = async () => {
  if (state.busy || !await confirmAction('删除接口并保存？', `删除 ${currentRoute().method} ${currentRoute().path} 及其所有场景。此操作会立即保存；其他未保存修改也会一并保存。`, '删除并保存')) return;
  const previousConfig = clone(state.config), previousRoute = state.route, previousRule = state.rule;
  const previousDirty = state.dirty;
  try {
    // The deleted route's invalid draft does not prevent deleting that route.
    state.config.routes.splice(state.route, 1); setBusy(true);
    const data = await api('/admin/api/config', { method: 'PUT', headers: { 'Content-Type': 'application/json', 'If-Match': `"${state.revision}"` }, body: pretty(state.config) });
    acceptConfig(data); notice('接口已删除，配置已保存。');
  } catch (error) {
    state.config = previousConfig; state.route = previousRoute; state.rule = previousRule; state.dirty = previousDirty;
    notice(error.message, true);
  } finally { setBusy(false); }
};
$('fillExample').onclick = () => editAction(() => { collectRoute(); fillExample(); });
$('testMethod').onchange = updateTestMethod;
$('send').onclick = sendRequest;
$('showBody').onclick = () => showResultTab('body');
$('showHeaders').onclick = () => showResultTab('headers');
$('copyResult').onclick = async () => {
  const target = state.resultTab === 'body' ? $('resultBody') : $('resultHeaders');
  try { await navigator.clipboard.writeText(target.textContent); notice('响应内容已复制。'); }
  catch { const range = document.createRange(); range.selectNodeContents(target); const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range); notice('已选中响应内容，请按 Ctrl+C 复制。'); }
};
for (const id of editorIds) $(id).addEventListener('input', () => { markDirty(); $('templateHint').hidden = !$('template').checked; });
window.addEventListener('beforeunload', event => { if (state.dirty) { event.preventDefault(); event.returnValue = ''; } });
render();
$('loginDialog').showModal();
