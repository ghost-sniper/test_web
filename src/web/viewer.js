'use strict';

const $ = id => document.getElementById(id);
const state = { catalog: null, selected: -1 };

function notice(message, error = false) {
  const element = $('viewerNotice');
  element.textContent = message;
  element.classList.toggle('error', error);
  element.hidden = !message;
}

function folderPath(id, folders) {
  const names = [];
  for (let folder = folders.get(id); folder; folder = folders.get(folder.parent_id)) names.unshift(folder.name);
  return names.length ? names.join(' / ') : '根目录';
}

function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}

function table(headers, rows) {
  const result = element('table', undefined, 'viewer-table');
  const header = result.createTHead().insertRow();
  for (const name of headers) {
    const cell = element('th', name);
    cell.scope = 'col';
    header.append(cell);
  }
  const body = result.createTBody();
  for (const values of rows) {
    const row = body.insertRow();
    for (const value of values) row.insertCell().textContent = value;
  }
  return result;
}

function renderRoutes() {
  const list = $('viewerRoutes');
  list.replaceChildren();

  const { routes, folders } = state.catalog;
  const byId = new Map(folders.map(folder => [folder.id, folder]));
  const query = $('viewerSearch').value.trim().toLowerCase();
  routes.forEach((route, index) => {
    if (!route.path.toLowerCase().includes(query)) return;
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    const selected = index === state.selected;
    button.className = selected ? 'route-item active' : 'route-item';
    if (selected) button.setAttribute('aria-current', 'true');
    const method = document.createElement('span');
    method.className = `method ${route.method.toLowerCase()}`;
    method.textContent = route.method;
    const label = document.createElement('span');
    label.className = 'route-label';
    const path = document.createElement('span');
    path.className = 'path';
    path.textContent = route.path;
    const folder = document.createElement('small');
    folder.textContent = folderPath(route.folder_id, byId);
    label.append(path, folder);
    button.append(method, label);
    button.title = `${route.method} ${route.path}`;
    button.onclick = () => {
      state.selected = index;
      renderRoutes();
      renderDetails();
      list.querySelector('[aria-current]')?.focus();
    };
    item.append(button);
    list.append(item);
  });
  $('viewerCount').textContent = `${list.children.length} / ${routes.length}`;
  $('viewerNoResults').hidden = list.children.length !== 0;
}

function requestInfo(route) {
  const { request } = route;
  const section = element('section', undefined, 'viewer-section');
  section.append(element('h3', '请求信息'));
  const parameters = Array.from(route.path.matchAll(/\/\{([A-Za-z_][A-Za-z0-9_]*)\}(?=\/|$)/g), match => match[1]);
  if (parameters.length) section.append(element('p', `路径参数 · ${parameters.join('、')}`, 'hint'));
  const requirement = request.body_required ? '必填' : '可省略';
  const format = request.format === 'xml' ? 'XML' : request.fields.length ? 'JSON 对象' : 'JSON';
  section.append(element('p', `请求体 · ${format} · ${requirement}`, 'hint'));
  if (request.fields.length) {
    section.append(table(['字段', '类型', '必填', '默认值'], request.fields.map(field => [
      field.name, field.type, field.required ? '是' : '否',
      field.default === null ? '—' : MockJSON.stringify(field.default),
    ])));
  } else if (request.format !== 'xml') {
    section.append(element('p', '未配置字段校验。', 'hint'));
  }
  return section;
}

function payloadPreview(text) {
  const payload = element('pre', text, 'viewer-payload');
  payload.tabIndex = 0;
  return payload;
}

function ruleInfo(rule, method) {
  const { match, response } = rule;
  const content = element('div', undefined, 'viewer-rule-content');
  content.append(element('h4', '匹配条件'));
  const xmlMatch = typeof match.body === 'string' ? match.body : null;
  const jsonMatch = xmlMatch === null ? match.body : null;
  const conditions = [
    ...(match.path ?? []).map(pair => ['路径参数', pair.name, MockJSON.stringify(pair.value)]),
    ...match.query.map(pair => ['查询参数', pair.name, MockJSON.stringify(pair.value)]),
    ...match.headers.map(pair => ['请求头', pair.name, MockJSON.stringify(pair.value)]),
    ...Object.entries(jsonMatch ?? {}).map(([name, value]) => ['请求体字段', name, MockJSON.stringify(value)]),
  ];
  const requiresObject = jsonMatch !== null && !Object.keys(jsonMatch).length;
  if (requiresObject) content.append(element('p', '请求体必须为 JSON 对象。', 'hint'));
  if (conditions.length) {
    content.append(table(['来源', '名称', '匹配值'], conditions));
  } else if (!requiresObject && xmlMatch === null) {
    content.append(element('p', '匹配所有通过请求校验的请求。', 'hint'));
  }
  if (xmlMatch !== null) {
    content.append(element('p', '请求体 XML · 全文匹配', 'hint'), payloadPreview(xmlMatch));
  }

  if (response.headers.length) {
    content.append(element('h4', '自定义响应头'));
    content.append(table(['名称', '值'], response.headers.map(pair => [pair.name, pair.value])));
  }
  const xmlResponse = response.format === 'xml';
  content.append(element('h4', (response.template ? '响应体模板' : '响应体') + (xmlResponse ? ' · XML' : '')));
  if (method === 'HEAD' || [204, 205, 304].includes(response.status)) {
    content.append(element('p', '此响应不发送响应体。', 'hint'));
  } else {
    content.append(payloadPreview(xmlResponse ? response.body : MockJSON.stringify(response.body)));
  }
  return content;
}

function renderDetails() {
  const route = state.catalog.routes[state.selected];
  const details = $('viewerDetails');
  const badge = $('viewerMethod');
  const title = $('viewerRouteTitle');
  badge.hidden = !route;
  if (!route) {
    title.textContent = '接口详情';
    title.removeAttribute('aria-label');
    $('viewerFolder').textContent = '';
    details.replaceChildren(element('p', '当前没有已配置的 Mock 接口。', 'hint'));
    return;
  }
  badge.textContent = route.method;
  badge.className = `method ${route.method.toLowerCase()}`;
  title.textContent = route.path;
  title.setAttribute('aria-label', `${route.method} ${route.path}`);
  $('viewerFolder').textContent = folderPath(route.folder_id, new Map(state.catalog.folders.map(folder => [folder.id, folder])));

  const rules = element('section', undefined, 'viewer-section');
  rules.append(element('h3', `Mock 规则 · ${route.rules.length}`));
  rules.append(element('p', '按优先级从高到低匹配，同级按配置顺序。', 'hint'));
  const ordered = route.rules.slice().sort((a, b) => b.priority - a.priority);
  ordered.forEach((rule, index) => {
    const panel = element('details', undefined, 'viewer-rule');
    const summary = element('summary');
    summary.append(element('strong', rule.id));
    summary.append(element('span', `HTTP ${rule.response.status} · 优先级 ${rule.priority} · ${rule.response.delay_ms} ms`));
    panel.append(summary);
    if (index === 0) {
      panel.open = true;
      panel.append(ruleInfo(rule, route.method));
    } else {
      panel.addEventListener('toggle', () => panel.append(ruleInfo(rule, route.method)), { once: true });
    }
    rules.append(panel);
  });
  details.replaceChildren(requestInfo(route), rules);
}

async function readCatalog() {
  const refresh = $('viewerRefresh');
  refresh.disabled = true;
  notice('正在加载接口…');
  try {
    const response = await fetch('/viewer/api/catalog', {
      credentials: 'omit',
      redirect: 'error',
      cache: 'no-store',
    });
    if (!response.ok) throw new Error(`读取接口失败（HTTP ${response.status}）。`);
    const snapshot = MockJSON.parse(await response.text());
    const previous = state.catalog?.routes[state.selected];
    state.catalog = snapshot.catalog;
    const index = previous
      ? state.catalog.routes.findIndex(route => route.method === previous.method && route.path === previous.path)
      : -1;
    state.selected = index >= 0 ? index : 0;
    $('viewerGeneration').textContent = `VERSION ${snapshot.generation}`;
    $('viewerContent').hidden = false;
    renderRoutes();
    renderDetails();
    notice('');
  } catch (error) {
    notice(error.message, true);
  } finally {
    refresh.disabled = false;
  }
}

$('viewerRefresh').onclick = readCatalog;
$('viewerSearch').oninput = () => {
  if (state.catalog) renderRoutes();
};
readCatalog();
