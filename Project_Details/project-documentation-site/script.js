/* LaptopKart Project Documentation — interactivity + data-driven rendering. */
(function () {
  'use strict';

  function el(tag, className, html) {
    const e = document.createElement(tag);
    if (className) e.className = className;
    if (html !== undefined) e.innerHTML = html;
    return e;
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }
  const TAG_LABEL = { live: 'Live', dead: 'Unused', limitation: 'Limitation', object: 'Object' };

  /* ---------------- Navigation / tab switching ---------------- */
  function initNav() {
    const btns = Array.from(document.querySelectorAll('.nav-btn'));
    const pages = Array.from(document.querySelectorAll('section.page'));

    function activate(id, push) {
      let found = false;
      pages.forEach((p) => {
        const on = p.id === id;
        p.classList.toggle('active', on);
        if (on) found = true;
      });
      if (!found && pages.length) { pages[0].classList.add('active'); id = pages[0].id; }
      btns.forEach((b) => b.classList.toggle('active', b.dataset.target === id));
      window.scrollTo({ top: 0, behavior: 'instant' in window ? 'instant' : 'auto' });
      if (push) history.replaceState(null, '', '#' + id);
    }

    btns.forEach((b) => {
      b.addEventListener('click', () => activate(b.dataset.target, true));
    });

    const initial = (window.location.hash || '').replace('#', '') || (pages[0] && pages[0].id);
    activate(initial, false);
  }

  /* ---------------- Sidebar search (filters nav items by label) ---------------- */
  function initSidebarSearch() {
    const input = document.getElementById('navSearch');
    if (!input) return;
    const items = Array.from(document.querySelectorAll('.nav-list li'));
    input.addEventListener('input', () => {
      const q = input.value.trim().toLowerCase();
      items.forEach((li) => {
        const text = li.textContent.toLowerCase();
        li.style.display = !q || text.includes(q) ? '' : 'none';
      });
      document.querySelectorAll('.nav-group-label').forEach((label) => {
        const group = label.nextElementSibling;
        const anyVisible = group && Array.from(group.children).some((li) => li.style.display !== 'none');
        label.style.display = anyVisible ? '' : 'none';
      });
    });
  }

  /* ---------------- Accordion (event delegation) ---------------- */
  function initAccordions() {
    document.addEventListener('click', (e) => {
      const head = e.target.closest('.ref-card-head');
      if (!head) return;
      head.closest('.ref-card').classList.toggle('open');
    });
  }

  /* ---------------- Generic reference-list filter wiring ---------------- */
  function wireFilter(inputId, listId, countId) {
    const input = document.getElementById(inputId);
    const list = document.getElementById(listId);
    const count = document.getElementById(countId);
    if (!input || !list) return;
    function apply() {
      const q = input.value.trim().toLowerCase();
      let visible = 0;
      let total = 0;
      Array.from(list.querySelectorAll('[data-search]')).forEach((card) => {
        total++;
        const match = !q || card.dataset.search.includes(q);
        card.style.display = match ? '' : 'none';
        if (match) visible++;
      });
      if (count) count.textContent = q ? `${visible} of ${total}` : `${total} total`;
    }
    input.addEventListener('input', apply);
    apply();
  }

  /* ---------------- Renderers ---------------- */

  function fieldRow(f) {
    return `<tr>
      <td class="fname">${esc(f.api)}</td>
      <td>${esc(f.label)}</td>
      <td class="ftype">${esc(f.type)}</td>
      <td class="fnotes">${esc(f.notes)}${f.required ? ' <span class="tag tag-trigger" style="margin-left:6px;">Required</span>' : ''}</td>
    </tr>`;
  }

  function renderObjects() {
    const wrap = document.getElementById('objectsList');
    if (!wrap) return;
    OBJECTS.forEach((o) => {
      const card = el('div', 'ref-card');
      card.dataset.search = (o.name + ' ' + o.label + ' ' + o.desc + ' ' + o.fields.map((f) => f.api + ' ' + f.label).join(' ')).toLowerCase();
      const vr = (o.validationRules || []).map((v) => `<li><span class="node-mono" style="color:var(--danger)">${esc(v.name)}</span><span class="m-desc">${esc(v.formula)} → “${esc(v.message)}”</span></li>`).join('');
      card.innerHTML = `
        <div class="ref-card-head">
          <div class="ref-card-title">
            <span class="ref-name">${esc(o.name)}</span>
            <span class="ref-label">${esc(o.label)}</span>
          </div>
          <div class="ref-tags">
            <span class="tag tag-object">Object</span>
            <svg class="chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M9 6l6 6-6 6"/></svg>
          </div>
        </div>
        <div class="ref-card-body">
          <p class="ref-desc">${o.desc}</p>
          <dl class="kv-list">
            <dt>Sharing</dt><dd>${esc(o.sharing)}</dd>
            <dt>Name field</dt><dd>${esc(o.namePattern)}</dd>
            <dt>Field count</dt><dd>${o.fields.length}</dd>
          </dl>
          <div class="table-wrap">
            <table class="schema">
              <thead><tr><th>API Name</th><th>Label</th><th>Type</th><th>Notes</th></tr></thead>
              <tbody>${o.fields.map(fieldRow).join('')}</tbody>
            </table>
          </div>
          ${vr ? `<p class="ref-desc" style="margin-top:14px;"><strong>Validation rules</strong></p><ul class="method-list">${vr}</ul>` : ''}
        </div>`;
      wrap.appendChild(card);
    });
  }

  function renderApex() {
    const wrap = document.getElementById('apexList');
    if (!wrap) return;
    const groups = [];
    APEX.forEach((c) => { if (!groups.includes(c.group)) groups.push(c.group); });
    groups.forEach((g) => {
      wrap.appendChild(el('h3', 'section-h', esc(g)));
      APEX.filter((c) => c.group === g).forEach((c) => {
        const card = el('div', 'ref-card');
        card.dataset.search = (c.name + ' ' + c.desc + ' ' + c.methods.map((m) => m.sig).join(' ')).toLowerCase();
        const tagClass = c.tag === 'dead' ? 'tag-dead' : c.tag === 'limitation' ? 'tag-service' : 'tag-live';
        const tagText = c.tag === 'dead' ? 'Unused' : c.tag === 'limitation' ? 'Limitation' : 'Live';
        const methods = c.methods.map((m) => `<li><span class="node-mono">${esc(m.sig)}</span>${m.desc ? `<span class="m-desc">${esc(m.desc)}</span>` : ''}</li>`).join('');
        const calls = (c.calls || []).map((x) => `<span class="chip">→ ${esc(x)}</span>`).join('');
        const calledBy = (c.calledBy || []).map((x) => `<span class="chip">← ${esc(x)}</span>`).join('');
        card.innerHTML = `
          <div class="ref-card-head">
            <div class="ref-card-title">
              <span class="ref-name">${esc(c.name)}</span>
              <span class="ref-label">${esc(c.sharing)}</span>
            </div>
            <div class="ref-tags">
              <span class="tag tag-apex">Apex</span>
              <span class="tag ${tagClass}">${tagText}</span>
              <svg class="chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M9 6l6 6-6 6"/></svg>
            </div>
          </div>
          <div class="ref-card-body">
            <p class="ref-desc">${c.desc}</p>
            ${methods ? `<ul class="method-list">${methods}</ul>` : ''}
            ${calls || calledBy ? `<div class="calls-row">${calls}${calledBy}</div>` : ''}
          </div>`;
        wrap.appendChild(card);
      });
    });
  }

  function renderTriggers() {
    const tbody = document.getElementById('triggersTableBody');
    if (!tbody) return;
    tbody.innerHTML = TRIGGERS.map((t) => `<tr>
      <td class="fname">${esc(t.name)}</td>
      <td class="ftype">${esc(t.object)}</td>
      <td>${esc(t.events)}</td>
      <td class="fnotes">${esc(t.handler)}<br><span style="color:var(--ink-subtle);font-size:11.5px;">${esc(t.note)}</span></td>
      <td><span class="tag ${t.tag === 'dead' ? 'tag-dead' : 'tag-live'}">${t.tag === 'dead' ? 'Unused' : 'Live'}</span></td>
    </tr>`).join('');
  }

  function renderRoutes() {
    const tbody = document.getElementById('routesTableBody');
    if (!tbody) return;
    tbody.innerHTML = ROUTES.map((r) => `<tr>
      <td class="fname">${esc(r.fn)}</td>
      <td class="ftype">${esc(r.page)}</td>
      <td class="fname">${esc(r.state)}</td>
      <td class="fnotes">${esc(r.notes)}</td>
    </tr>`).join('');
  }

  function renderLwcPages() {
    const wrap = document.getElementById('lwcPagesList');
    if (!wrap) return;
    LWC_PAGES.forEach((c) => {
      const card = el('div', 'ref-card');
      card.dataset.search = (c.name + ' ' + c.desc + ' ' + c.route).toLowerCase();
      const tagClass = c.tag === 'dead' ? 'tag-dead' : 'tag-lwc';
      const children = c.children.length ? `<dt>Children</dt><dd>${c.children.map((x) => `<span class="chip">${esc(x)}</span>`).join(' ')}</dd>` : '';
      const apex = c.apex.length ? `<dt>Apex calls</dt><dd>${c.apex.map((x) => `<span class="chip">${esc(x)}</span>`).join(' ')}</dd>` : '';
      const services = c.services.length ? `<dt>Services used</dt><dd>${c.services.map((x) => `<span class="chip">${esc(x)}</span>`).join(' ')}</dd>` : '';
      card.innerHTML = `
        <div class="ref-card-head">
          <div class="ref-card-title">
            <span class="ref-name">${esc(c.name)}</span>
            <span class="ref-label">${esc(c.route)}</span>
          </div>
          <div class="ref-tags">
            <span class="tag ${tagClass}">${c.tag === 'dead' ? 'Unused' : 'LWC'}</span>
            <svg class="chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M9 6l6 6-6 6"/></svg>
          </div>
        </div>
        <div class="ref-card-body">
          <p class="ref-desc">${esc(c.desc)}</p>
          <dl class="kv-list" style="grid-template-columns: 120px 1fr;">${children}${apex}${services}</dl>
        </div>`;
      wrap.appendChild(card);
    });
  }

  function renderLwcServices() {
    const wrap = document.getElementById('lwcServicesList');
    if (!wrap) return;
    LWC_SERVICES.forEach((s) => {
      const card = el('div', 'ref-card');
      card.dataset.search = (s.name + ' ' + s.desc + ' ' + s.fns.join(' ')).toLowerCase();
      const fns = s.fns.map((f) => `<li><span class="node-mono">${esc(f)}</span></li>`).join('');
      card.innerHTML = `
        <div class="ref-card-head">
          <div class="ref-card-title">
            <span class="ref-name">${esc(s.name)}</span>
          </div>
          <div class="ref-tags">
            <span class="tag tag-service">Service</span>
            <svg class="chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M9 6l6 6-6 6"/></svg>
          </div>
        </div>
        <div class="ref-card-body">
          <p class="ref-desc">${esc(s.desc)}</p>
          <ul class="method-list">${fns}</ul>
        </div>`;
      wrap.appendChild(card);
    });
  }

  function renderIssues() {
    const wrap = document.getElementById('issuesList');
    if (!wrap) return;
    const sevLabel = { bug: 'Bug', design: 'Design Decision', limitation: 'Limitation', resolved: 'Resolved' };
    ISSUES.forEach((i) => {
      const card = el('div', 'issue-card');
      card.innerHTML = `
        <div class="issue-head">
          <span class="tag tag-severity-${esc(i.severity)}">${sevLabel[i.severity]}</span>
          <span class="issue-title">${esc(i.title)}</span>
        </div>
        <div class="issue-body">${esc(i.body)}</div>`;
      wrap.appendChild(card);
    });
  }

  function renderStats() {
    const stats = [
      { num: OBJECTS.length, label: 'Objects documented' },
      { num: APEX.filter((c) => c.tag !== 'dead').length, label: 'Active Apex classes' },
      { num: TRIGGERS.filter((t) => t.tag === 'live').length + '/' + TRIGGERS.length, label: 'Live triggers' },
      { num: LWC_PAGES.length, label: 'LWC components' },
      { num: LWC_SERVICES.length, label: 'Service modules' },
      { num: ROUTES.length, label: 'Site routes' },
    ];
    const wrap = document.getElementById('overviewStats');
    if (!wrap) return;
    stats.forEach((s) => {
      const c = el('div', 'stat-card');
      c.innerHTML = `<div class="stat-num">${s.num}</div><div class="stat-label">${s.label}</div>`;
      wrap.appendChild(c);
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    renderStats();
    renderObjects();
    renderApex();
    renderTriggers();
    renderRoutes();
    renderLwcPages();
    renderLwcServices();
    renderIssues();

    wireFilter('objectsFilter', 'objectsList', 'objectsCount');
    wireFilter('apexFilter', 'apexList', 'apexCount');
    wireFilter('lwcPagesFilter', 'lwcPagesList', 'lwcPagesCount');
    wireFilter('lwcServicesFilter', 'lwcServicesList', 'lwcServicesCount');

    initAccordions();
    initSidebarSearch();
    initNav();
  });
})();
