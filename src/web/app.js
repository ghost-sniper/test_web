'use strict';

const $ = id => document.getElementById(id);
const state = { token: '', config: null, revision: '', generation: 0, route: -1, rule: 0, dirty: false, busy: false, controller: null, resultTab: 'body' };
const pretty = value => MockJSON.stringify(value);
const clone = value => MockJSON.parse(pretty(value));
const currentRoute = () => state.config?.routes[state.route];
const currentRule = () => currentRoute()?.rules[state.rule];
const editorIds = ['routeMethod', 'routePath', 'routeFolder', 'routeRateLimit', 'routeClientLimits', 'trustedProxyIps', 'requestFormat', 'xmlBodyRequired', 'requestSpec', 'ruleId', 'priority', 'matchBody', 'matchPath', 'matchQuery', 'matchHeaders', 'status', 'delay', 'responseFormat', 'template', 'responseBody', 'responseHeaders'];
const maxRequestsPerSecond = 10000;
const collapsedFolders = new Set();
let editingFolderId = null;
const narrowSidebar = window.matchMedia('(max-width: 650px)');
let desktopSidebarCollapsed = false;
let sidebarDrawerOpen = false;

function syncSidebar() {
  const sidebar = $('collectionSidebar');
  const toggle = $('sidebarToggle');
  const hadFocus = sidebar.contains(document.activeElement);
  const overlay = narrowSidebar.matches && sidebarDrawerOpen;
  const expanded = narrowSidebar.matches ? overlay : !desktopSidebarCollapsed;
  sidebar.hidden = !expanded;
  if (overlay) {
    sidebar.setAttribute('role', 'dialog');
    sidebar.setAttribute('aria-modal', 'true');
  } else {
    sidebar.removeAttribute('role');
    sidebar.removeAttribute('aria-modal');
  }
  $('workspaceMain').inert = overlay;
  $('sidebarBackdrop').hidden = !overlay;
  document.body.classList.toggle('sidebar-collapsed', !expanded);
  document.body.classList.toggle('sidebar-drawer-open', overlay);
  toggle.setAttribute('aria-expanded', String(expanded));
  const label = expanded ? '折叠接口侧栏' : '展开接口侧栏';
  toggle.setAttribute('aria-label', label);
  toggle.title = label;
  if (!expanded && hadFocus) toggle.focus();
}
function closeSidebarDrawer() {
  if (!sidebarDrawerOpen) return;
  sidebarDrawerOpen = false;
  syncSidebar();
  $('sidebarToggle').focus();
}
$('sidebarToggle').onclick = () => {
  if (narrowSidebar.matches) {
    sidebarDrawerOpen = true;
    syncSidebar();
    $('sidebarClose').focus();
  } else {
    desktopSidebarCollapsed = !desktopSidebarCollapsed;
    syncSidebar();
  }
};
$('sidebarClose').onclick = closeSidebarDrawer;
$('sidebarBackdrop').onclick = closeSidebarDrawer;
narrowSidebar.addEventListener('change', () => {
  sidebarDrawerOpen = false;
  syncSidebar();
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && sidebarDrawerOpen && !document.querySelector('dialog[open]')) {
    event.preventDefault();
    closeSidebarDrawer();
  }
});

function notice(message, error = false) {
  $('notice').textContent = message;
  $('notice').classList.toggle('error', error);
  $('notice').hidden = false;
}
function markDirty() {
  state.dirty = true;
  $('dirtyLabel').hidden = false;
  $('emptySave').hidden = false;
  $('testHint').textContent = '有未保存修改：测试仍使用服务器上已保存的规则。';
}
function setBusy(busy) {
  state.busy = busy;
  $('workbench').inert = busy;
  $('routeList').inert = busy;
  for (const id of ['addRoute', 'addFolder', 'emptySave', 'refresh', 'reload']) $(id).disabled = busy || !state.config;
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
  expandFolderPath(currentRoute()?.folder_id);
  $('connectionState').textContent = '服务已连接';
  $('connectionDot').classList.add('connected');
  $('sessionButton').textContent = '断开连接';
  $('revisionLabel').textContent = `VERSION ${String(data.generation).padStart(2, '0')}`;
  $('emptyAction').textContent = '＋ 新建接口';
  render();
}
function folderMap(folders = state.config?.folders ?? []) {
  return new Map(folders.map(folder => [folder.id, folder]));
}
function folderTrail(id, folders) {
  const trail = [];
  for (let folder = folders.get(id); folder; folder = folders.get(folder.parent_id)) {
    trail.unshift(folder);
  }
  return trail;
}
function folderPath(id, folders) {
  return folderTrail(id, folders).map(folder => folder.name).join(' / ');
}
function expandFolderPath(id) {
  for (const folder of folderTrail(id, folderMap())) collapsedFolders.delete(folder.id);
}
function fillFolderSelect(select, selected, folders = folderMap(), excluded = new Set()) {
  select.replaceChildren(new Option('根目录', ''));
  for (const folder of folders.values()) {
    if (!excluded.has(folder.id)) select.add(new Option(folderPath(folder.id, folders), folder.id));
  }
  select.value = selected ?? '';
}
function routeItem(route, index, breadcrumb = '') {
  const item = document.createElement('li');
  item.className = 'route-entry';
  const button = document.createElement('button');
  button.type = 'button';
  button.className = `route-item${state.route === index ? ' active' : ''}`;
  button.setAttribute('aria-current', state.route === index ? 'true' : 'false');
  const badge = document.createElement('span');
  badge.className = `method ${route.method.toLowerCase()}`;
  badge.textContent = route.method;
  const label = document.createElement('span');
  label.className = 'route-label';
  const path = document.createElement('span');
  path.className = 'path';
  path.textContent = route.path;
  label.append(path);
  if (breadcrumb) {
    const location = document.createElement('small');
    location.textContent = breadcrumb;
    label.append(location);
  }
  button.title = `${route.method} ${route.path}${breadcrumb ? ` · ${breadcrumb}` : ''}`;
  button.append(badge, label);
  button.onclick = () => editAction(() => {
    collectRoute();
    state.route = index;
    state.rule = 0;
    expandFolderPath(currentRoute().folder_id);
    render();
    closeSidebarDrawer();
  });
  const move = document.createElement('button');
  move.type = 'button';
  move.className = 'route-move';
  move.textContent = '移动';
  move.setAttribute('aria-label', `移动接口 ${route.method} ${route.path}`);
  move.disabled = !state.config.folders?.length;
  move.title = move.disabled ? '请先新建目录' : '移动到目录';
  move.onclick = () => openRouteMove(index);
  item.append(button, move);
  return item;
}
function renderTree(parent, groups) {
  const list = document.createElement('ul');
  list.className = 'collection-list';
  const group = groups.get(parent);
  if (!group) return list;
  for (const folder of group.folders) {
    const item = document.createElement('li');
    item.className = 'folder-item';
    const details = document.createElement('details');
    details.open = !collapsedFolders.has(folder.id);
    details.ontoggle = () => {
      if (!details.isConnected) return;
      if (details.open) collapsedFolders.delete(folder.id);
      else collapsedFolders.add(folder.id);
    };
    const summary = document.createElement('summary');
    summary.textContent = folder.name;
    summary.title = folder.name;
    const children = renderTree(folder.id, groups);
    children.classList.add('folder-children');
    if (!children.children.length) {
      const empty = document.createElement('li');
      empty.className = 'folder-empty';
      empty.textContent = '空目录';
      children.append(empty);
    }
    details.append(summary, children);
    const edit = document.createElement('button');
    edit.type = 'button';
    edit.className = 'folder-edit';
    edit.textContent = '⋯';
    edit.setAttribute('aria-label', `管理目录 ${folder.name}`);
    edit.onclick = () => openFolderEditor(folder.id);
    item.append(details, edit);
    list.append(item);
  }
  for (const { route, index } of group.routes) list.append(routeItem(route, index));
  return list;
}
function urlSearch(input) {
  if (/^https?:\/\//i.test(input)) {
    try {
      const path = new URL(input).pathname.toLowerCase();
      return route => route.path.toLowerCase() === path;
    } catch {
      return () => false;
    }
  }
  const part = input.split(/[?#]/, 1)[0].toLowerCase();
  return route => part.length > 0 && route.path.toLowerCase().includes(part);
}
function renderList() {
  const nav = $('routeList');
  const query = $('search').value.trim();
  const routes = state.config?.routes ?? [];
  const folders = folderMap();
  $('routeCount').textContent = routes.length;
  let list;
  if (query && state.config) {
    const matches = urlSearch(query);
    list = document.createElement('ul');
    list.className = 'collection-list';
    routes.forEach((route, index) => {
      if (matches(route)) list.append(routeItem(route, index, folderPath(route.folder_id, folders) || '根目录'));
    });
    $('routeCount').textContent = `${list.children.length} / ${routes.length}`;
  } else {
    const groups = new Map();
    function group(id) {
      if (!groups.has(id)) groups.set(id, { folders: [], routes: [] });
      return groups.get(id);
    }
    for (const folder of folders.values()) group(folder.parent_id ?? null).folders.push(folder);
    routes.forEach((route, index) => group(route.folder_id ?? null).routes.push({ route, index }));
    list = renderTree(null, groups);
  }
  if (list.children.length) {
    nav.replaceChildren(list);
    return;
  }
  const empty = document.createElement('p');
  empty.className = 'sidebar-empty';
  empty.textContent = !state.config ? '连接服务后查看接口' : query ? '没有 URL 匹配的接口。' : '接口集合为空。';
  nav.replaceChildren(empty);
}
function render() {
  renderList();
  for (const id of ['addRoute', 'addFolder', 'emptySave', 'refresh', 'reload']) $(id).disabled = !state.config || state.busy;
  const route = currentRoute();
  $('workbench').hidden = !route;
  $('emptyState').hidden = !!route;
  $('emptySave').hidden = !state.config || !state.dirty;
  if (!route) return;
  $('routeMethod').value = route.method;
  $('routePath').value = route.path;
  fillFolderSelect($('routeFolder'), route.folder_id);
  const policy = route.rate_limit;
  const defaultLimit = policy?.requests_per_second ?? 0;
  const clients = policy?.clients ?? [];
  $('routeRateLimit').value = defaultLimit;
  $('routeClientLimits').value = pretty(Object.fromEntries(clients.map(client => [client.ip, client.requests_per_second])));
  $('trustedProxyIps').value = (state.config.trusted_proxies ?? []).join(', ');
  $('rateLimitSummary').textContent = (defaultLimit ? `${defaultLimit} 次/秒/IP` : '默认不限') + (clients.length ? ` · ${clients.length} 个单独上限` : '');
  $('endpointPath').textContent = route.path;
  $('methodBadge').textContent = route.method;
  $('methodBadge').className = `method ${route.method.toLowerCase()}`;
  const { format = 'json', ...requestSpec } = route.request ?? { body_required: false, fields: [] };
  $('requestFormat').value = format;
  $('xmlBodyRequired').checked = !!requestSpec.body_required;
  $('requestSpec').value = pretty(requestSpec);
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
  const responseFormat = rule.response.format ?? 'json';
  $('responseFormat').value = responseFormat;
  $('template').checked = !!rule.response.template;
  $('responseBody').value = responseFormat === 'xml' ? rule.response.body ?? '' : pretty(rule.response.body);
  $('responseHeaders').value = pretty(fromPairs(rule.response.headers));
  const matchBody = rule.match?.body ?? null;
  $('matchBody').value = typeof matchBody === 'string' ? matchBody : (format === 'xml' && matchBody === null ? '' : pretty(matchBody));
  $('matchPath').value = pretty(fromPairs(rule.match?.path));
  $('matchQuery').value = pretty(fromPairs(rule.match?.query));
  $('matchHeaders').value = pretty(fromPairs(rule.match?.headers));
  $('matchDetails').open = !!(rule.match?.body || rule.match?.path?.length || rule.match?.query?.length || rule.match?.headers?.length);
  $('deleteRule').disabled = route.rules.length === 1;
  $('deleteRule').title = route.rules.length === 1 ? '每个接口至少保留一个场景；也可删除整个接口' : '删除当前场景';
  updateBodyEditors();
  fillExample();
}
function updateBodyEditors() {
  const xmlRequest = $('requestFormat').value === 'xml';
  const xmlResponse = $('responseFormat').value === 'xml';
  $('jsonRequestFields').hidden = xmlRequest;
  $('xmlRequestOptions').hidden = !xmlRequest;
  $('matchBodyLabel').textContent = xmlRequest ? 'XML 请求体全文匹配（留空表示不限）' : 'JSON 请求体子集（null 表示不限）';
  $('matchBody').placeholder = xmlRequest ? '<request />' : 'null';
  $('responseBodyFormat').textContent = xmlResponse ? 'XML' : 'JSON';
  const templateHint = $('templateHint');
  templateHint.hidden = !$('template').checked;
  templateHint.textContent = (xmlRequest
    ? '支持 {{body.name}}、{{body.customer.name}}、{{body.@id}} 和 {{body.age|add:1}}。'
    : '支持 {{body.name}} 和 {{body.age|add:1}}，JSON 字段需声明为必填或有默认值。')
    + (xmlResponse ? 'XML 占位符可写在元素文本或属性值中。' : '');
  $('xmlResponseHint').hidden = !xmlResponse;
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
function readXml(id, title, optional = false) {
  const value = $(id).value;
  if (optional && !value.trim()) return null;
  if (!value.trimStart().startsWith('<')) {
    $(id).focus();
    throw new Error(`${title}需要填写 XML 文档。`);
  }
  return value;
}
function pairs(id, title) {
  return Object.entries(parseJson(id, title, true)).map(([name, value]) => {
    if (!name || typeof value !== 'string') throw new Error(`${title}的名称不能为空，值必须是字符串。`);
    return { name, value };
  });
}
function pathParameterName(segment) {
  return segment.startsWith('{') && segment.endsWith('}') ? segment.slice(1, -1) : null;
}
function queryPairs() {
  const field = $('matchQuery');
  const input = field.value.trim();
  if (!input) return [];
  if (input.startsWith('{')) return pairs('matchQuery', 'URL 查询参数');
  try {
    if (!/^(?:[?/]|https?:\/\/)/i.test(input)) throw new Error();
    const url = new URL(input, location.origin);
    if (!url.search) throw new Error();
    decodeURIComponent(url.search);
    const values = new Map();
    for (const [name, value] of url.searchParams) {
      if (!name) throw new Error();
      if (!values.has(name)) values.set(name, value);
    }
    return Array.from(values, ([name, value]) => ({ name, value }));
  } catch {
    field.focus();
    throw new Error('请填写有效的查询字符串（例如 ?scenario=error）、带查询参数的 URL 或 JSON 对象。');
  }
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
  const folderId = $('routeFolder').value;
  if (folderId) next.folder_id = folderId;
  else delete next.folder_id;
  if (!/^\/(?!\/)/.test(next.path) || /[\s?#\\]/.test(next.path)) throw new Error('接口路径需以 / 开头，不能包含空白、反斜线或查询参数。');
  if (next.path === '/admin' || next.path.startsWith('/admin/') || next.path === '/healthz') throw new Error('该路径由管理服务保留，请换一个路径。');
  const pathNames = next.path.split('/').map(pathParameterName).filter(name => name !== null);
  if (pathNames.some(name => !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) || new Set(pathNames).size !== pathNames.length) {
    throw new Error('路径参数名称需以英文字母或下划线开头，仅包含英文字母、数字或下划线，且不能重复。');
  }
  if (state.config.routes.some((other, i) => i !== state.route && other.method === next.method && other.path === next.path)) throw new Error('同一方法和路径的接口已存在。');
  const defaultLimit = integer('routeRateLimit', '每个客户端每秒上限', 0, maxRequestsPerSecond);
  const clients = Object.entries(parseJson('routeClientLimits', '客户端 IP 单独上限', true)).map(([ip, limit]) => {
    if (!ip.trim() || !Number.isInteger(limit) || limit < 0 || limit > maxRequestsPerSecond) {
      $('routeClientLimits').focus();
      throw new Error(`客户端上限需要填写 IP 及 0 到 ${maxRequestsPerSecond} 之间的整数。`);
    }
    return { ip: ip.trim(), requests_per_second: limit };
  });
  if (defaultLimit || clients.length) next.rate_limit = { requests_per_second: defaultLimit, clients };
  else delete next.rate_limit;
  const trustedProxies = $('trustedProxyIps').value.split(',').map(ip => ip.trim()).filter(Boolean);
  const requestFormat = $('requestFormat').value;
  next.request = requestFormat === 'xml'
    ? { format: 'xml', body_required: $('xmlBodyRequired').checked }
    : { ...parseJson('requestSpec', '请求配置', true), format: 'json' };
  const rule = next.rules[state.rule];
  rule.id = $('ruleId').value.trim();
  if (!rule.id || next.rules.some((r, i) => i !== state.rule && r.id === rule.id)) throw new Error('场景 ID 不能为空，也不能与当前接口的其他场景重复。');
  rule.priority = integer('priority', '优先级', -2147483648, 2147483647);
  const bodyMatch = requestFormat === 'xml'
    ? readXml('matchBody', '请求体匹配条件', true)
    : parseJson('matchBody', '请求体匹配条件');
  if (requestFormat === 'json' && bodyMatch !== null && (typeof bodyMatch !== 'object' || Array.isArray(bodyMatch) || MockJSON.isNumber(bodyMatch))) throw new Error('请求体匹配条件需为 JSON 对象，或用 null 表示不限。');
  const pathMatch = $('matchPath').value.trim() ? pairs('matchPath', 'URL 路径参数') : [];
  for (const { name, value } of pathMatch) {
    if (!pathNames.includes(name) || !value) {
      $('matchPath').focus();
      throw new Error(`路径参数 ${name} 必须在接口路径中声明，且匹配值不能为空。`);
    }
  }
  rule.match = { body: bodyMatch, path: pathMatch, query: queryPairs(), headers: pairs('matchHeaders', '请求头匹配条件') };
  const responseFormat = $('responseFormat').value;
  const status = integer('status', '状态码', 200, 599);
  const responseBody = responseFormat === 'xml'
    ? readXml('responseBody', '响应体', [204, 205, 304].includes(status))
    : parseJson('responseBody', '响应体');
  rule.response = {
    ...rule.response, status, format: responseFormat, delay_ms: integer('delay', '延迟', 0, 30000),
    template: $('template').checked, body: responseBody, headers: pairs('responseHeaders', '响应头'),
  };
  next.rules[state.rule] = rule;
  state.config.routes[state.route] = next;
  if (trustedProxies.length) state.config.trusted_proxies = trustedProxies;
  else delete state.config.trusted_proxies;
}
function editAction(action) {
  if (state.busy) return;
  try { action(); } catch (error) { notice(error.message, true); }
}
function openRouteMove(index) {
  editAction(() => {
    collectRoute();
    const route = state.config.routes[index];
    const dialog = $('routeMoveDialog');
    const target = $('routeMoveTarget');
    $('routeMoveLabel').textContent = `${route.method} ${route.path}`;
    fillFolderSelect(target, route.folder_id);
    $('routeMoveForm').onsubmit = event => {
      event.preventDefault();
      const folderId = target.value;
      dialog.close();
      if (folderId === (route.folder_id ?? '')) return;
      if (folderId) route.folder_id = folderId;
      else delete route.folder_id;
      if (index === state.route) $('routeFolder').value = folderId;
      expandFolderPath(folderId);
      markDirty();
      renderList();
      notice('接口位置已更新。点击「保存并生效」写入配置。');
    };
    dialog.showModal();
  });
}
$('routeMoveCancel').onclick = () => $('routeMoveDialog').close();
function newRule(id) { return { id, priority: 0, response: { status: 200, body: { code: 200, message: 'ok' }, delay_ms: 0 } }; }
function uniqueId(base, existing) { let id = base, i = 2; while (existing.includes(id)) id = `${base}-${i++}`; return id; }
function folderHasContents(id) {
  return (state.config.folders ?? []).some(folder => folder.parent_id === id) ||
    state.config.routes.some(route => route.folder_id === id);
}
function openFolderEditor(id = null) {
  editAction(() => {
    collectRoute();
    editingFolderId = id;
    const folders = folderMap();
    const folder = folders.get(id);
    const excluded = new Set();
    if (folder) {
      for (const candidate of folders.values()) {
        if (folderTrail(candidate.id, folders).some(ancestor => ancestor.id === id)) excluded.add(candidate.id);
      }
    }
    $('folderTitle').textContent = folder ? '管理目录' : '新建目录';
    $('folderName').value = folder?.name ?? '';
    fillFolderSelect($('folderParent'), folder?.parent_id, folders, excluded);
    $('folderDelete').hidden = !folder;
    $('folderDelete').disabled = !!folder && folderHasContents(id);
    $('folderDeleteHint').hidden = !$('folderDelete').disabled;
    $('folderError').hidden = true;
    $('folderDialog').showModal();
  });
}
function updateFolderDraft(folders, visibleFolderId) {
  if (folders.length) state.config.folders = folders;
  else delete state.config.folders;
  expandFolderPath(visibleFolderId);
  $('search').value = '';
  $('folderDialog').close();
  markDirty();
  renderList();
  if (currentRoute()) fillFolderSelect($('routeFolder'), currentRoute().folder_id);
  notice('目录修改已加入草稿。点击「保存并生效」写入配置。');
}
$('folderForm').onsubmit = event => {
  event.preventDefault();
  const name = $('folderName').value.trim();
  const parentId = $('folderParent').value || null;
  const folders = state.config.folders ?? [];
  const id = editingFolderId ?? uniqueId('folder', folders.map(folder => folder.id));
  try {
    if (!name || /[\/\\\r\n]/.test(name)) throw new Error('请输入目录名称，名称不能包含斜杠或换行。');
    if (folders.some(folder => folder.id !== id && (folder.parent_id ?? null) === parentId && folder.name === name)) {
      throw new Error('同一上级目录下已存在同名目录。');
    }
    const next = folders.slice();
    const index = next.findIndex(folder => folder.id === id);
    const folder = { id, name, parent_id: parentId };
    if (index < 0) next.push(folder);
    else next[index] = folder;
    const byId = folderMap(next);
    if (next.some(entry => folderTrail(entry.id, byId).length > 16)) throw new Error('目录最多支持 16 层。');
    updateFolderDraft(next, id);
  } catch (error) {
    $('folderError').textContent = error.message;
    $('folderError').hidden = false;
  }
};
$('folderCancel').onclick = () => $('folderDialog').close();
$('folderDelete').onclick = () => {
  if (!editingFolderId || folderHasContents(editingFolderId)) return;
  const folders = state.config.folders;
  const parent = folders.find(folder => folder.id === editingFolderId)?.parent_id;
  collapsedFolders.delete(editingFolderId);
  updateFolderDraft(folders.filter(folder => folder.id !== editingFolderId), parent);
};
function addRoute() {
  if (!state.config) return $('loginDialog').showModal();
  editAction(() => {
    collectRoute();
    state.config.routes.push({ method: 'GET', path: uniqueId('/api/example', state.config.routes.map(r => r.path)), rules: [newRule('success')] });
    state.route = state.config.routes.length - 1; state.rule = 0; $('search').value = '';
    markDirty();
    render();
    closeSidebarDrawer();
    $('routePath').focus();
    $('routePath').select();
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
  const pathValues = new Map((rule.match?.path ?? []).map(pair => [pair.name, pair.value]));
  const path = route.path.split('/').map(segment => {
    const name = pathParameterName(segment);
    return name === null ? segment : encodeURIComponent(pathValues.get(name) ?? 'demo');
  }).join('/');
  $('testPath').value = path + (query.size ? `?${query}` : '');
  const xmlRequest = route.request?.format === 'xml';
  $('testBodyFormat').textContent = xmlRequest ? 'XML' : 'JSON';
  if (xmlRequest) {
    $('testBody').value = typeof rule.match?.body === 'string' ? rule.match.body : '<request />';
  } else {
    const body = Object.create(null);
    for (const field of route.request?.fields || []) {
      if (field.default != null) body[field.name] = field.default;
      else if (field.required) body[field.name] = field.type === 'string' ? 'demo' : field.type === 'boolean' ? true : 1;
    }
    Object.assign(body, rule.match?.body || {});
    $('testBody').value = pretty(body);
  }
  const headers = fromPairs(rule.match?.headers);
  if (!Object.keys(headers).some(name => name.toLowerCase() === 'content-type')) {
    headers['Content-Type'] = xmlRequest ? 'application/xml' : 'application/json';
  }
  $('testHeaders').value = pretty(headers);
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
    if (url.origin !== location.origin || ['/admin', '/viewer'].some(path => decoded === path || decoded.startsWith(path + '/'))) {
      throw new Error('测试面板只能调用当前服务的 Mock 接口。');
    }
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
  collapsedFolders.clear();
  $('search').value = '';
  $('connectionState').textContent = '未连接'; $('sessionButton').textContent = '连接服务';
  $('revisionLabel').textContent = '尚未连接'; $('emptyAction').textContent = '连接服务';
  $('resultBody').textContent = ''; $('resultHeaders').textContent = ''; $('notice').hidden = true;
  render();
};
async function saveConfig() {
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
}
$('save').onclick = saveConfig;
$('emptySave').onclick = saveConfig;
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
$('addFolder').onclick = () => openFolderEditor();
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
for (const id of editorIds) $(id).addEventListener('input', markDirty);
$('requestFormat').onchange = () => {
  const match = $('matchBody');
  if ($('requestFormat').value === 'xml' && match.value.trim() === 'null') match.value = '';
  if ($('requestFormat').value === 'json' && !match.value.trim()) match.value = 'null';
  updateBodyEditors();
};
$('responseFormat').onchange = updateBodyEditors;
$('template').onchange = updateBodyEditors;
window.addEventListener('beforeunload', event => { if (state.dirty) { event.preventDefault(); event.returnValue = ''; } });
syncSidebar();
render();
$('loginDialog').showModal();
