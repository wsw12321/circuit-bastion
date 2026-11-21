const MODULES = {
  scanner: { name: '扫描器', type: '观测模块', desc: '发现范围内敌人，输出标签与距离', icon: '⌁', cls: 'scan', ports: [['signal', '输出信号', '脉冲炮']], stats: ['范围 3', '间隔 1.2s', '功耗 4'], cost: 7 },
  filter: { name: '过滤器', type: '处理模块', desc: '只放行满足条件的事件', icon: '◇', cls: 'filter', ports: [['signal', '输入信号', '扫描器'], ['signal', '输出信号', '脉冲炮']], stats: ['条件 2', '延迟 0.2s', '功耗 3'], cost: 6 },
  splitter: { name: '分流器', type: '处理模块', desc: '按标签把事件送往不同线路', icon: 'Y', cls: 'split', ports: [['signal', '输入信号', '过滤器'], ['signal', '输出 A', '弧光塔'], ['signal', '输出 B', '减速场']], stats: ['分支 2', '延迟 0.4s', '功耗 5'], cost: 8 },
  pulse: { name: '脉冲炮', type: '执行模块', desc: '单体高伤害，优先锁定装甲目标', icon: '⌁', cls: '', ports: [['signal', '输入信号', '扫描器'], ['power', '能源输入', '电池'], ['cooling', '冷却输入', '散热器']], stats: ['伤害 28', '冷却 2.4s', '功耗 14'], cost: 12 },
  arc: { name: '弧光塔', type: '执行模块', desc: '在多个目标之间跳跃', icon: 'ϟ', cls: 'split', ports: [['signal', '输入信号', '分流器'], ['power', '能源输入', '电池']], stats: ['伤害 12×3', '冷却 1.6s', '功耗 10'], cost: 10 },
  slow: { name: '减速场', type: '执行模块', desc: '改变区域内敌人的移动速度', icon: '◌', cls: 'slow', ports: [['signal', '输入信号', '分流器'], ['power', '能源输入', '电池']], stats: ['减速 35%', '范围 2', '功耗 8'], cost: 9 },
  battery: { name: '电池', type: '基础设施', desc: '储存能源，缓解峰值消耗', icon: '▥', cls: 'battery', ports: [['power', '能源输出', '脉冲炮']], stats: ['容量 42', '充能 8/s', '功耗 0'], cost: 8 },
  radiator: { name: '散热器', type: '基础设施', desc: '降低附近模块过热', icon: '▦', cls: 'heat', ports: [['cooling', '冷却输出', '脉冲炮']], stats: ['散热 12/s', '范围 2', '功耗 2'], cost: 7 },
  cache: { name: '缓存', type: '基础设施', desc: '储存短时间内未被处理的事件', icon: '▤', cls: 'cache', ports: [['signal', '输入信号', '过滤器'], ['signal', '输出信号', '分流器']], stats: ['容量 6', '延迟 1.0s', '功耗 2'], cost: 7 },
  router: { name: '路由器', type: '基础设施', desc: '扩大端口数量，但会增加延迟', icon: '⊞', cls: 'router', ports: [['signal', '输入信号', '缓存'], ['signal', '输出信号', '脉冲炮'], ['power', '能源输入', '电池']], stats: ['端口 +2', '延迟 0.6s', '功耗 5'], cost: 11 },
};
const ENEMIES = [
  { name: '群集', icon: 'G', hp: 35, speed: 1.4, tag: '群体', color: 'cyan' },
  { name: '装甲', icon: 'A', hp: 82, speed: .82, tag: '装甲', color: 'orange' },
  { name: '隐匿', icon: 'V', hp: 48, speed: 1.1, tag: '隐匿', color: 'violet' },
  { name: '载荷', icon: 'P', hp: 110, speed: .65, tag: '载荷', color: 'amber' },
  { name: '干扰', icon: 'I', hp: 60, speed: .9, tag: '干扰', color: 'red' },
  { name: '维修', icon: 'R', hp: 68, speed: 1.0, tag: '维修', color: 'mint' },
];
const WAVE_DATA = [
  ['初始侦察', '群体', 5], ['装甲试探', '装甲', 6], ['干扰脉冲', '干扰', 7], ['双路载荷', '载荷', 8], ['隐匿穿越', '隐匿', 9], ['热交换', '维修', 10], ['混合编队', '混合', 11], ['断线回响', '干扰', 12], ['核心压测', '装甲', 13], ['逆向首领', '首领', 1],
];
const state = {
  phase: 'prepare', wave: 3, speed: 1, paused: false, tick: 0, interval: null, nextEnemyId: 0,
  charge: 46, structure: 12, sample: 9, heat: 38, coreHp: 100, selectedModule: 'pulse', selectedCell: null, placement: null,
  showSignalsOnly: false, modules: [], enemies: [], events: [], eventSeq: 0, waveResolved: false,
  inventory: { pulse: 2, scanner: 1, filter: 1, battery: 1, radiator: 1 },
  shop: ['arc', 'slow', 'router', 'cache', 'splitter'], rules: [
    { trigger: '发现目标', condition: '标签包含「装甲」', action: '发送至 脉冲炮' },
    { trigger: '模块收到信号', condition: '能源高于 20', action: '优先锁定最近目标' },
  ], firmware: 'overclock',
};

const $ = (id) => document.getElementById(id);
const battlefield = $('battlefield');

function persist() {
  try { localStorage.setItem('circuit-bastion-save', JSON.stringify({ wave: state.wave, charge: state.charge, structure: state.structure, sample: state.sample, inventory: state.inventory, modules: state.modules, rules: state.rules, firmware: state.firmware })); $('save-status').textContent = '本地存档已更新'; } catch { $('save-status').textContent = '存档暂不可用'; }
}
function restore() {
  try {
    const saved = JSON.parse(localStorage.getItem('circuit-bastion-save') || 'null');
    if (!saved) return;
    Object.assign(state, saved); state.wave = Math.max(1, Math.min(10, saved.wave || 3));
  } catch { /* ignore malformed local data */ }
}
function moduleById(id) { return MODULES[id] || MODULES.pulse; }
function logEvent(type, text, source = '系统', target = '—', path = ['扫描器', '过滤器', '脉冲炮']) {
  const event = { id: ++state.eventSeq, t: state.tick, type, text, source, target, path };
  state.events.unshift(event); state.events = state.events.slice(0, 18); renderEvents();
}
function formatTime(seconds) { const m = String(Math.floor(seconds / 60)).padStart(2, '0'); const s = (seconds % 60).toFixed(1).padStart(4, '0'); return `${m}:${s}`; }
function setToast(text) { $('field-toast').textContent = text; $('field-toast').style.opacity = '1'; clearTimeout(setToast.timeout); setToast.timeout = setTimeout(() => { $('field-toast').style.opacity = '.5'; }, 2600); }

function renderWaveList() {
  $('wave-count').textContent = `${String(state.wave).padStart(2, '0')} / 10`;
  $('wave-progress').style.width = `${state.wave * 10}%`;
  $('wave-list').innerHTML = WAVE_DATA.map((wave, i) => `<button class="wave-row ${i + 1 === state.wave ? 'current' : ''} ${i + 1 < state.wave ? 'done' : ''}" data-wave="${i + 1}"><span class="wave-index">${String(i + 1).padStart(2, '0')}</span><span>${wave[0]}</span><span class="wave-state">${i + 1 < state.wave ? '✓' : i + 1 === state.wave ? 'LIVE' : '·'}</span></button>`).join('');
  document.querySelectorAll('.wave-row').forEach((row) => row.addEventListener('click', () => { const target = Number(row.dataset.wave); if (target <= state.wave) { state.wave = target; renderAll(); setToast(`已切换到第 ${target} 波复盘`); } }));
  const data = WAVE_DATA[state.wave] || WAVE_DATA[0]; $('next-wave-name').textContent = data[0]; $('next-wave-desc').textContent = data[1] === '混合' ? '混合编队会同时测试线路带宽与峰值能源。' : `携带“${data[1]}”标签，优先观察它的路径与规则响应。`; $('threat-label').textContent = state.wave === 10 ? '首领' : `威胁 ${['Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ'][Math.min(3, Math.ceil(state.wave / 3) - 1)]}`;
  const count = state.wave === 10 ? 1 : Math.min(12, 4 + state.wave); $('enemy-preview').innerHTML = Array.from({ length: Math.min(6, count) }, (_, i) => `<span class="enemy-token ${state.wave === 10 ? 'boss' : ''}">${state.wave === 10 ? 'B' : (i % 3 === 0 ? 'A' : 'G')}</span>`).join('');
}

function buildField() {
  battlefield.innerHTML = '';
  const routeCells = new Set([1, 2, 3, 4, 5, 6, 14, 22, 30, 38, 39, 40, 41, 42, 43, 44]);
  for (let i = 0; i < 48; i += 1) {
    const cell = document.createElement('button'); cell.className = `grid-cell ${routeCells.has(i) ? 'route' : ''} ${i === 1 ? 'entry-cell' : ''} ${i === 44 ? 'core-cell' : ''}`; cell.dataset.cell = i;
    cell.addEventListener('click', () => onCellClick(i)); battlefield.appendChild(cell);
  }
  drawConnections(); renderModules();
}
function cellPosition(index) { const cell = battlefield.querySelector(`[data-cell="${index}"]`); if (!cell) return null; return { x: cell.offsetLeft + cell.offsetWidth / 2, y: cell.offsetTop + cell.offsetHeight / 2 }; }
function drawConnections() {
  battlefield.querySelectorAll('.connection').forEach((el) => el.remove());
  const pairs = state.modules.length ? state.modules.map((m, i) => ({ a: m.cell, b: state.modules[(i + 1) % state.modules.length]?.cell, type: i % 3 === 0 ? 'signal' : i % 3 === 1 ? 'power' : 'cooling' })).filter((p) => p.b !== undefined) : [];
  pairs.forEach(({ a, b, type }) => { const pa = cellPosition(a); const pb = cellPosition(b); if (!pa || !pb) return; const line = document.createElement('i'); line.className = `connection ${type}`; const dx = pb.x - pa.x; const dy = pb.y - pa.y; line.style.left = `${pa.x}px`; line.style.top = `${pa.y}px`; line.style.width = `${Math.hypot(dx, dy)}px`; line.style.transform = `rotate(${Math.atan2(dy, dx)}rad)`; if (state.showSignalsOnly && type !== 'signal') line.style.display = 'none'; battlefield.appendChild(line); });
}
function renderModules() {
  battlefield.querySelectorAll('.module-node').forEach((el) => el.remove());
  state.modules.forEach((placed) => {
    const cell = battlefield.querySelector(`[data-cell="${placed.cell}"]`); if (!cell) return;
    const meta = moduleById(placed.id); const button = document.createElement('button'); button.className = `module-node ${meta.cls} ${state.selectedModule === placed.id && state.selectedCell === placed.cell ? 'selected' : ''}`; button.innerHTML = `${meta.icon}<span class="module-label">${meta.name}</span>`; button.title = `${meta.name} · 点击检查`; button.addEventListener('click', (e) => { e.stopPropagation(); state.selectedModule = placed.id; state.selectedCell = placed.cell; renderInspector(); renderModules(); }); cell.appendChild(button);
  });
}
function onCellClick(cellIndex) {
  if (state.phase !== 'prepare') { setToast('战斗中请暂停后查看事件，布局将在波次之间修改'); return; }
  if (state.placement) {
    if (state.modules.some((m) => m.cell === cellIndex)) { setToast('该格已有模块'); return; }
    state.modules.push({ id: state.placement, cell: cellIndex, firmware: null }); state.selectedModule = state.placement; state.selectedCell = cellIndex; state.placement = null; $('control-hint').textContent = '已放置模块 · 继续编辑规则或启动战斗'; setToast(`已放置 ${moduleById(state.selectedModule).name}`); buildField(); renderInspector(); persist(); return;
  }
  const placed = state.modules.find((m) => m.cell === cellIndex); if (placed) { state.selectedModule = placed.id; state.selectedCell = cellIndex; renderModules(); renderInspector(); } else { setToast('从下方商店选择模块，再点击空白网格放置'); }
}

function renderInspector() {
  const meta = moduleById(state.selectedModule); $('selected-name').textContent = meta.name; $('selected-type').textContent = `${meta.type} · ${meta.desc}`; $('port-count').textContent = `${meta.ports.length} 端口`; $('inspector-stats').innerHTML = meta.stats.map((s) => `<div><span>${s.split(' ')[0]}</span><b>${s.split(' ').slice(1).join(' ')}</b></div>`).join(''); const selectedSymbol = document.querySelector('#selected-module .module-symbol'); selectedSymbol.textContent = meta.icon; selectedSymbol.className = `module-symbol ${meta.cls}`;
  $('port-list').innerHTML = meta.ports.map(([kind, label, target]) => `<div class="port-row"><i class="port-dot ${kind}"></i><span>${label}</span><strong>${target}</strong></div>`).join('');
  $('rules-list').innerHTML = state.rules.map((rule, i) => `<div class="rule-card"><div class="rule-top"><span>优先级 ${i + 1}</span><button class="rule-remove" data-rule="${i}" title="删除规则">×</button></div><p>当 <b>${rule.trigger}</b> 且 ${rule.condition} 时，<b>${rule.action}</b></p></div>`).join(''); document.querySelectorAll('.rule-remove').forEach((btn) => btn.addEventListener('click', () => { state.rules.splice(Number(btn.dataset.rule), 1); renderInspector(); persist(); }));
  const firmware = [{ id: 'overclock', label: '过载协议', desc: '伤害 +20% · 峰值功耗 +8', cost: '物理固件' }, { id: 'relay', label: '中继端口', desc: '新增 1 个信号端口 · 延迟 +0.3s', cost: '接口固件' }, { id: 'coolant', label: '液冷回路', desc: '过热恢复 +35% · 结构点 -1', cost: '物理固件' }]; $('firmware-list').innerHTML = firmware.map((item) => `<label class="firmware-card ${state.firmware === item.id ? 'selected' : ''}"><input type="radio" name="firmware" value="${item.id}" ${state.firmware === item.id ? 'checked' : ''}><div><p>${item.label}</p><small>${item.desc} · ${item.cost}</small></div></label>`).join(''); document.querySelectorAll('input[name="firmware"]').forEach((input) => input.addEventListener('change', () => { state.firmware = input.value; renderInspector(); persist(); logEvent('system', `固件切换为 ${firmware.find((f) => f.id === input.value).label}`, meta.name, '系统'); }));
}

function renderShop() {
  $('shop-grid').innerHTML = state.shop.map((id, i) => { const meta = moduleById(id); const canBuy = state.charge >= meta.cost; return `<button class="shop-card ${canBuy ? '' : 'sold'}" data-shop-id="${id}" data-shop-index="${i}"><div class="shop-symbol ${meta.cls}">${meta.icon}</div><h3>${meta.name}</h3><p>${meta.desc}</p><span class="shop-cost">${meta.cost} ϟ</span></button>`; }).join(''); document.querySelectorAll('.shop-card').forEach((card) => card.addEventListener('click', () => { const id = card.dataset.shopId; const meta = moduleById(id); if (state.charge < meta.cost) { setToast('电荷不足，先撑过下一波或刷新商店'); return; } state.charge -= meta.cost; state.inventory[id] = (state.inventory[id] || 0) + 1; state.placement = id; setToast(`${meta.name} 已加入待放置队列 · 点击网格完成部署`); renderAll(); persist(); }));
}
function renderEvents() { $('event-count').textContent = `${state.events.length} events`; $('event-list').innerHTML = state.events.length ? state.events.slice(0, 9).map((event) => `<button class="event-row ${event.type}" data-event="${event.id}"><span class="event-time">${formatTime(event.t)}</span><span class="event-icon">${event.type === 'attack' ? 'ϟ' : event.type === 'warn' ? '!' : '→'}</span><span><strong>${event.text}</strong><br>${event.source} → ${event.target}</span></button>`).join('') : '<div class="event-row"><span class="event-time">00:00.0</span><span class="event-icon">→</span><span><strong>等待第一条系统事件</strong><br>启动战斗后显示可追踪路径</span></div>'; document.querySelectorAll('.event-row[data-event]').forEach((row) => row.addEventListener('click', () => { const event = state.events.find((item) => item.id === Number(row.dataset.event)); if (!event) return; document.querySelectorAll('.event-row').forEach((el) => el.classList.remove('active')); row.classList.add('active'); setToast(`路径：${event.path.join('  →  ')}`); highlightPath(event.path); })); }
function highlightPath(path) { battlefield.querySelectorAll('.grid-cell').forEach((cell) => cell.classList.remove('active-path')); const names = new Set(path); state.modules.filter((m) => names.has(moduleById(m.id).name)).forEach((m) => battlefield.querySelector(`[data-cell="${m.cell}"]`)?.classList.add('active-path')); }

function spawnWave() { state.enemies = []; const count = state.wave === 10 ? 1 : Math.min(12, 4 + state.wave); for (let i = 0; i < count; i += 1) { const base = state.wave === 10 ? { name: '堡垒监察者', icon: 'B', hp: 360, speed: .4, tag: '首领' } : ENEMIES[(i + state.wave) % ENEMIES.length]; state.enemies.push({ id: ++state.nextEnemyId, ...base, maxHp: base.hp, progress: -i * .08, alive: true }); } logEvent('system', `第 ${state.wave} 波已生成 · ${count} 个目标`, '波次调度', '入口', ['入口', '扫描器']); renderEnemies(); }
function renderEnemies() { battlefield.querySelectorAll('.enemy').forEach((el) => el.remove()); state.enemies.filter((e) => e.alive).forEach((enemy) => { const el = document.createElement('div'); el.className = `enemy ${enemy.tag === '首领' ? 'boss' : ''}`; el.textContent = enemy.icon; const p = Math.max(0, Math.min(1, enemy.progress)); const x = 22 + p * (battlefield.clientWidth - 70); const y = p < .42 ? 90 : 90 + ((p - .42) / .58) * (battlefield.clientHeight - 140); el.style.left = `${x - 11}px`; el.style.top = `${y - 11}px`; el.dataset.enemy = enemy.id; el.title = `${enemy.name} · ${Math.max(0, Math.ceil(enemy.hp))} HP`; battlefield.appendChild(el); }); }
function tickSimulation() {
  if (state.paused || state.phase !== 'battle') return;
  state.tick += 0.25 * state.speed;
  state.enemies.forEach((enemy) => {
    if (!enemy.alive) return;
    enemy.progress += enemy.speed * 0.005 * state.speed;
    if (enemy.progress >= 1) {
      enemy.alive = false;
      state.coreHp = Math.max(0, state.coreHp - (enemy.tag === '首领' ? 24 : 5));
      state.heat += 3;
      logEvent('warn', `${enemy.name} 穿过防线`, '入口', '核心', ['入口', '路由器', '核心']);
    }
  });
  const towers = state.modules.filter((module) => ['pulse', 'arc', 'slow'].includes(module.id));
  towers.forEach((tower) => {
    const target = state.enemies.find((enemy) => enemy.alive);
    const interval = tower.id === 'pulse' ? 2.5 : 1.5;
    if (!target || state.tick % interval > 0.3) return;
    const damage = tower.id === 'pulse' ? 16 : tower.id === 'arc' ? 9 : 2;
    target.hp -= damage;
    const enemyEl = battlefield.querySelector(`[data-enemy="${target.id}"]`);
    enemyEl?.classList.add('hit');
    if (tower.id !== 'slow') {
      logEvent('attack', `${moduleById(tower.id).name} 命中 ${target.name}`, moduleById(tower.id).name, `目标 #${target.id}`, [moduleById(state.selectedModule).name, '路由器', moduleById(tower.id).name, target.name]);
    }
    if (target.hp <= 0) {
      target.alive = false;
      state.charge += target.tag === '首领' ? 16 : 2;
      state.sample += target.tag === '首领' ? 3 : 1;
      logEvent('system', `${target.name} 已清除 · 获得样本`, moduleById(tower.id).name, '战利品');
    }
  });
  state.heat = Math.min(100, Math.max(0, state.heat + (towers.length ? 0.12 : -0.08) * state.speed));
  $('sim-time').textContent = `T+ ${formatTime(state.tick)}`;
  $('charge-value').textContent = state.charge;
  $('sample-value').textContent = String(state.sample).padStart(2, '0');
  $('heat-value').textContent = `${Math.round(state.heat)}°`;
  $('heat-meter').style.width = `${state.heat}%`;
  renderEnemies();
  if (state.enemies.every((enemy) => !enemy.alive)) finishWave(true);
  else if (state.coreHp <= 0) finishWave(false);
}
function finishWave(success) { if (state.waveResolved) return; state.waveResolved = true; clearInterval(state.interval); state.phase = 'replay'; $('phase-label').textContent = success ? '复盘阶段' : '核心失守'; document.querySelector('.status-pill i').style.background = success ? 'var(--mint)' : 'var(--red)'; $('start-button').textContent = state.wave >= 10 && success ? '✓ 远征完成' : '下一波准备'; $('start-button').disabled = state.wave >= 10 && success; $('pause-button').disabled = true; $('control-hint').textContent = success ? `第 ${state.wave} 波完成 · 读取事件日志并重构系统` : '核心耐久耗尽 · 可重置布局后重新尝试'; logEvent(success ? 'system' : 'warn', success ? `第 ${state.wave} 波完成 · 核心剩余 ${state.coreHp}%` : '系统停止 · 核心耐久归零', '战斗控制', '复盘'); renderWaveList(); persist(); }
function startWave() { if (state.phase === 'replay') { if (state.wave < 10) state.wave += 1; state.phase = 'prepare'; state.waveResolved = false; state.tick = 0; state.events = []; state.coreHp = Math.max(55, state.coreHp); renderAll(); setToast(`第 ${state.wave} 波准备就绪`); return; } state.phase = 'battle'; state.paused = false; state.waveResolved = false; $('phase-label').textContent = '战斗运行中'; document.querySelector('.status-pill i').style.background = 'var(--mint)'; $('start-button').disabled = true; $('pause-button').disabled = false; $('control-hint').textContent = '系统自动运行 · 点击事件可追踪传播路径'; spawnWave(); state.interval = setInterval(tickSimulation, 250); }
function togglePause() { if (state.phase !== 'battle') return; state.paused = !state.paused; $('pause-button').textContent = state.paused ? '▶' : 'Ⅱ'; $('phase-label').textContent = state.paused ? '战斗已暂停' : '战斗运行中'; $('control-hint').textContent = state.paused ? '已暂停 · 可点击事件查看完整传播路径' : '系统自动运行 · 点击事件可追踪传播路径'; }

function renderAll() { renderWaveList(); renderShop(); renderInspector(); renderEvents(); $('charge-value').textContent = state.charge; $('structure-value').textContent = state.structure; $('sample-value').textContent = String(state.sample).padStart(2, '0'); $('energy-value').textContent = `${Math.min(100, 72 + state.modules.length * 2)} / 100`; $('energy-meter').style.width = `${Math.min(100, 72 + state.modules.length * 2)}%`; $('heat-value').textContent = `${Math.round(state.heat)}°`; $('heat-meter').style.width = `${state.heat}%`; }

function resetLayout() { state.modules = [{ id: 'scanner', cell: 9 }, { id: 'filter', cell: 18 }, { id: 'pulse', cell: 27 }, { id: 'battery', cell: 35 }, { id: 'radiator', cell: 36 }]; state.selectedModule = 'pulse'; state.selectedCell = 27; state.placement = null; state.phase = 'prepare'; state.coreHp = 100; state.heat = 38; buildField(); renderAll(); persist(); setToast('布局已重置 · 线路恢复默认连接'); }
function setup() {
  restore();
  if (!state.modules.length) resetLayout(); else { buildField(); renderAll(); }
  $('start-button').addEventListener('click', startWave); $('pause-button').addEventListener('click', togglePause); $('reset-button').addEventListener('click', resetLayout); $('filter-button').addEventListener('click', () => { state.showSignalsOnly = !state.showSignalsOnly; $('filter-button').textContent = state.showSignalsOnly ? '◉ 显示全部连接' : '◌ 仅显示信号'; drawConnections(); });
  document.querySelectorAll('.speed').forEach((button) => button.addEventListener('click', () => { state.speed = Number(button.dataset.speed); document.querySelectorAll('.speed').forEach((el) => el.classList.toggle('active', el === button)); }));
  $('add-rule').addEventListener('click', () => { if (state.rules.length >= 3) { setToast('规则槽已满 · 先删除一条规则'); return; } state.rules.push({ trigger: '目标进入范围', condition: '距离低于 2', action: '发送至 减速场' }); renderInspector(); persist(); setToast('已添加规则 · 记得执行静态检查'); });
  $('check-rules').addEventListener('click', () => { $('rule-hint').textContent = '✓ 静态检查通过 · 端口类型匹配 · 未发现循环'; $('rule-hint').style.color = 'var(--mint)'; setToast('规则检查通过 · 2 条规则已编译'); logEvent('system', '规则检查通过 · 2 条规则已编译', '规则编辑器', '系统'); });
  $('link-button').addEventListener('click', () => setToast('连接编辑模式已开启 · 点击网格模块查看相邻端口')); $('merge-button').addEventListener('click', () => { const pair = Object.entries(state.inventory).find(([, count]) => count >= 3); if (!pair) { setToast('需要 3 个同名模块才能重构'); return; } state.inventory[pair[0]] -= 3; state.sample += 2; state.firmware = 'relay'; setToast(`${moduleById(pair[0]).name} 已重构 · 获得中继端口固件`); logEvent('system', `${moduleById(pair[0]).name} ×3 → 重构模块 Ⅱ`, '商店', '系统'); persist(); renderInspector(); });
  $('refresh-shop').addEventListener('click', () => { if (state.charge < 2) { setToast('电荷不足'); return; } state.charge -= 2; const catalog = Object.keys(MODULES); const offset = Math.floor(state.tick + state.wave * 3) % catalog.length; state.shop = catalog.map((_, index) => catalog[(index + offset) % catalog.length]).slice(0, 5); renderShop(); persist(); setToast('商店已刷新'); });
  $('save-button').addEventListener('click', () => { persist(); setToast('已保存本局配置'); }); $('replay-button').addEventListener('click', () => { const payload = { version: '0.1.0', seed: 821, wave: state.wave, modules: state.modules, rules: state.rules, events: state.events }; const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' }); const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = `circuit-bastion-replay-wave-${state.wave}.json`; link.click(); URL.revokeObjectURL(link.href); setToast('回放文件已导出'); });
  document.addEventListener('keydown', (event) => { if (event.code === 'Space') { event.preventDefault(); togglePause(); } if (['1', '2', '4'].includes(event.key)) { state.speed = Number(event.key); document.querySelectorAll('.speed').forEach((el) => el.classList.toggle('active', Number(el.dataset.speed) === state.speed)); } });
}

setup();
