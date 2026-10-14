/* Impact Analyzer dashboard.
 *
 * Reads the same ImpactReport JSON that the CLI prints and the MCP server
 * serves, so the human view and the agent view can never disagree.
 * No framework, no outbound network: cytoscape is vendored locally. */
(function () {
  'use strict';

  var state = {
    report: null,
    baselineSeverity: null,
    cy: null,
    filter: '',
    activeTab: 'impacted',
    selectedPath: null,
    // Symbols used to crowd the file graph; keep them opt-in.
    view: 'layered',
    activeViewEl: null
  };

  var BAND_RANK = { low: 1, medium: 2, high: 3, critical: 4 };

  var BAND_COLOR = {
    low: '#3fb950',
    medium: '#d9a441',
    high: '#f0883e',
    critical: '#f2545b'
  };

  // ------------------------------------------------------------------ utils

  function $(id) { return document.getElementById(id); }
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }
  function clear(node) { while (node.firstChild) node.removeChild(node.firstChild); }

  function toast(message) {
    var t = $('toast');
    t.textContent = message;
    t.hidden = false;
    clearTimeout(toast._timer);
    toast._timer = setTimeout(function () { t.hidden = true; }, 2200);
  }

  function getJson(path) {
    return fetch(path, { headers: { accept: 'application/json' } }).then(function (r) {
      return r.json().then(function (body) {
        if (!r.ok) throw new Error((body && body.message) || ('HTTP ' + r.status));
        return body;
      });
    });
  }

  function copyText(text, label) {
    var done = function () { toast(label + ' copied to clipboard'); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { fallbackCopy(text, done); });
    } else {
      fallbackCopy(text, done);
    }
  }

  function fallbackCopy(text, done) {
    var ta = el('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); done(); } catch (e) { toast('copy failed'); }
    document.body.removeChild(ta);
  }

  // ----------------------------------------------------------------- render

  function render(report) {
    state.report = report;
    state.baselineSeverity = report.severity.band;

    $('repo-path').textContent = report.rootPath || '';
    $('repo-path').title = report.rootPath || '';

    renderHero(report);
    renderMetrics(report);
    renderTables(report);
    renderGraph(report);
    renderNotes(report);
  }

  function renderHero(report) {
    var band = report.severity.band;
    var bandNode = $('severity-band');
    bandNode.textContent = band;
    bandNode.style.setProperty('--band', BAND_COLOR[band] || '#9aa7b4');
    $('hero').style.setProperty('--band', BAND_COLOR[band] || '#9aa7b4');
    $('severity-score').textContent = report.severity.score.toFixed(2);

    var m = report.metrics;
    $('hero-line').textContent =
      m.changedFileCount + ' files changed · ' +
      m.impactedFileCount + ' files impacted · ' +
      m.impactedClassCount + ' classes impacted';

    var rationale = $('rationale');
    clear(rationale);
    (report.severity.rationale || []).forEach(function (r) {
      rationale.appendChild(el('li', null, r));
    });

    var conf = $('confidence-chip');
    conf.textContent = 'confidence ' + report.confidence.band;
    conf.title = (report.confidence.notes || []).join('\n') || 'No confidence notes.';
    $('git-chip').textContent =
      (report.git.branch || 'detached') + ' @ ' + (report.git.head || 'no commits');
  }

  function renderMetrics(report) {
    var m = report.metrics;
    var host = $('metrics');
    clear(host);

    var tiles = [
      { label: 'changed', value: m.changedFileCount, hint: 'dart files in the change set' },
      { label: 'impacted', value: m.impactedFileCount, hint: 'files that may be affected' },
      { label: 'classes', value: m.impactedClassCount, hint: 'changed + referenced types' },
      { label: 'direct', value: m.directCount, hint: 'one hop away', hot: m.directCount > 8 },
      { label: 'transitive', value: m.transitiveCount, hint: 'two or more hops' },
      { label: 'public api', value: m.publicApiHits, hint: 'non-src lib/ symbols', hot: m.publicApiHits > 0 },
      { label: 'tests', value: m.impactedTestCount, hint: 'tests in the impact set' },
      { label: 'depth', value: m.maxDepthReached, hint: 'deepest hop reached' },
      { label: 'analyzed', value: m.analyzedFileCount, hint: 'dart files indexed' }
    ];

    tiles.forEach(function (t) {
      var node = el('div', 'metric' + (t.hot ? ' is-hot' : ''));
      node.appendChild(el('div', 'metric-label', t.label));
      node.appendChild(el('div', 'metric-value', String(t.value)));
      node.appendChild(el('div', 'metric-hint', t.hint));
      host.appendChild(node);
    });
  }

  function matchesFilter(path) {
    if (!state.filter) return true;
    return path.toLowerCase().indexOf(state.filter.toLowerCase()) !== -1;
  }

  function renderTables(report) {
    var impactedBody = $('impacted-body');
    var changedBody = $('changed-body');
    clear(impactedBody);
    clear(changedBody);

    var impacted = (report.impactedFiles || []).filter(function (f) {
      return matchesFilter(f.path);
    });
    var changed = (report.changedFiles || []).filter(function (f) {
      return matchesFilter(f.path);
    });

    $('count-impacted').textContent = String(impacted.length);
    $('count-changed').textContent = String(changed.length);

    impacted.forEach(function (f) {
      var tr = el('tr');
      tr.dataset.path = f.path;
      tr.appendChild(el('td', 'rel rel-' + f.relation, f.relation));
      var pathTd = el('td', 'path-cell', f.path);
      tr.appendChild(pathTd);
      tr.appendChild(el('td', 'sym', (f.impactedSymbols || []).join(', ') || '—'));
      tr.appendChild(el('td', 'muted', f.reason || ''));
      tr.addEventListener('click', function () { selectPath(f.path, true); });
      impactedBody.appendChild(tr);
    });

    changed.forEach(function (f) {
      var tr = el('tr');
      tr.dataset.path = f.path;
      tr.appendChild(el('td', 'rel st-' + f.status, f.status));
      tr.appendChild(el('td', 'path-cell', f.path));
      tr.appendChild(el('td', 'sym', (f.symbols || []).join(', ') || '—'));
      tr.appendChild(el('td', 'muted', f.oldPath ? 'was ' + f.oldPath : ''));
      tr.addEventListener('click', function () { selectPath(f.path, true); });
      changedBody.appendChild(tr);
    });

    var anyRows = impacted.length + changed.length;
    $('table-empty').hidden = anyRows > 0;
  }

  function renderNotes(report) {
    var host = $('notes-body');
    clear(host);
    var notes = [];

    (report.confidence.notes || []).forEach(function (n) { notes.push({ text: n, warn: false }); });
    (report.warnings || []).forEach(function (w) { notes.push({ text: w, warn: true }); });

    if (!notes.length) {
      host.appendChild(el('p', 'table-empty', 'No warnings or confidence notes.'));
    } else {
      notes.forEach(function (n) {
        host.appendChild(el('div', 'note' + (n.warn ? ' is-warn' : ''), n.text));
      });
    }
    $('count-warnings').textContent = String(notes.length);
  }

  // ------------------------------------------------------------------ graph

  /** Destroy whatever view is mounted, whether Cytoscape or plain DOM. */
  function destroyGraph() {
    if (state.cy) { state.cy.destroy(); state.cy = null; }
    var host = $('graph');
    if (host) {
      clear(host);
      state.activeViewEl = null;
    }
  }

  function renderGraph(report) {
    var graph = report.graph || { nodes: [], edges: [], truncated: false };
    var host = $('graph');

    $('truncation-badge').hidden = !graph.truncated;
    if (graph.truncated) {
      $('truncation-badge').title =
        'Showing ' + (graph.nodes || []).length + ' of ' + graph.totalNodes + ' nodes.';
    }

    if (!graph.nodes || graph.nodes.length === 0) {
      $('graph-empty').hidden = false;
      destroyGraph();
      return;
    }
    $('graph-empty').hidden = true;

    var view = ImpactViews.list[state.view] || ImpactViews.list.layered;
    var usesCy = view.usesCy;

    // Files/symbol toggles only mean something for the node-link views that
    // can actually draw symbols. The matrix, tree and ring views are
    // file-scoped by construction.
    var graphToggles = $('graph-toggles');
    if (graphToggles) graphToggles.hidden = !usesCy || view.toggles === false;

    destroyGraph();

    var ix = ImpactViews.index(report);
    ix.report = report;

    var ctx = {
      host: host,
      report: report,
      index: ix,
      elk: window.ELK ? new window.ELK() : null,
      showFiles: $('toggle-files') ? $('toggle-files').checked : true,
      showSymbols: $('toggle-symbols') ? $('toggle-symbols').checked : false,
      status: function (msg) { $('view-status').textContent = msg; },
      onSelect: function (path) { selectPath(path, false); }
    };

    if (view.usesCy && !ctx.elk && state.view === 'sugiyama') {
      ctx.status('elkjs not loaded');
    }

    try {
      state.cy = view.render(ctx) || null;
    } catch (e) {
      host.appendChild(el('pre', 'graph-error',
        'View "' + state.view + '" failed to render: ' + e.message + '\n\n' + (e.stack || '')));
      state.cy = null;
    }

    if (state.cy) {
      state.cy.on('tap', 'node', function (evt) {
        var node = evt.target;
        if (node.data('kind') === 'file') selectPath(node.id(), false);
      });
      if (state.selectedPath) {
        var n = state.cy.$id(state.selectedPath);
        if (n && n.length) focusNode(n);
      }
    }
  }

  function setView(name) {
    if (!ImpactViews.list[name] || state.view === name) return;
    state.view = name;
    var tabs = document.querySelectorAll('.view-tab');
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].classList.toggle('is-active', tabs[i].dataset.view === name);
    }
    $('btn-relayout').hidden = !ImpactViews.list[name].usesCy ||
      name === 'rings' || name === 'sugiyama';
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, '', '#' + name);
    }
    if (state.report) renderGraph(state.report);
  }

  /** #matrix, #tree, ... deep-link the active view. */
  function viewFromHash() {
    var name = (window.location.hash || '').replace(/^#/, '');
    return ImpactViews.list[name] ? name : null;
  }

  function shortPath(path) {
    if (!path) return '';
    var parts = path.split('/');
    return parts.length <= 2 ? path : '…/' + parts.slice(-2).join('/');
  }

  function focusNode(node) {
    if (!state.cy) return;
    state.cy.elements().addClass('dimmed');
    node.removeClass('dimmed').addClass('focused');
    node.connectedEdges().removeClass('dimmed');
    node.neighborhood('node').removeClass('dimmed');
    state.cy.animate({ center: { eles: node }, duration: 220 });
  }

  function clearSelection() {
    var rows = document.querySelectorAll('table.files tbody tr, .tree-row.is-selected');
    for (var i = 0; i < rows.length; i++) rows[i].classList.remove('is-selected');
    if (state.cy) state.cy.elements().removeClass('dimmed focused');
  }

  /** Keeps the graph and the tables pointing at the same file. */
  function selectPath(path, fromTable) {
    state.selectedPath = path;

    var rows = document.querySelectorAll('table.files tbody tr');
    for (var i = 0; i < rows.length; i++) {
      rows[i].classList.toggle('is-selected', rows[i].dataset.path === path);
    }

    if (!state.cy) {
      // DOM-backed view: highlight the matching tree row if it is mounted.
      var treeRows = document.querySelectorAll('.tree-file');
      for (var j = 0; j < treeRows.length; j++) {
        treeRows[j].classList.toggle('is-selected', treeRows[j].title.indexOf(path) === 0);
      }
      return;
    }

    var node = state.cy.$id(path);
    if (node && node.length) {
      focusNode(node);
    } else {
      // The file is filtered out of this view (e.g. symbol-only mode).
      state.cy.elements().removeClass('dimmed focused');
    }
  }

  // ------------------------------------------------------------------- plan

  function severityDelta(from, to) {
    var a = BAND_RANK[from] || 0;
    var b = BAND_RANK[to] || 0;
    if (b > a) return { text: '▲ ' + (b - a) + ' band vs working tree', cls: 'delta-up' };
    if (b < a) return { text: '▼ ' + (a - b) + ' band vs working tree', cls: 'delta-down' };
    return { text: '= same band as working tree', cls: 'delta-flat' };
  }

  function renderPlanResult(report) {
    var host = $('plan-result');
    clear(host);

    if (!report || report.error) {
      host.appendChild(el('p', 'plan-empty', report ? (report.code + ': ' + report.message) : 'No plan analysed yet.'));
      return;
    }

    var delta = severityDelta(state.baselineSeverity, report.severity.band);

    var headline = el('div', 'plan-headline');
    var band = el('span', 'plan-band', report.severity.band);
    band.style.color = BAND_COLOR[report.severity.band] || '#9aa7b4';
    headline.appendChild(band);
    headline.appendChild(el('span', 'muted', 'score ' + report.severity.score.toFixed(2)));
    host.appendChild(headline);

    host.appendChild(el('div', 'delta ' + delta.cls, delta.text));

    var m = report.metrics;
    host.appendChild(el('div', 'muted',
      m.impactedFileCount + ' files impacted · ' +
      m.impactedClassCount + ' classes · ' +
      m.impactedTestCount + ' tests'));

    if (report.confidence && (report.confidence.notes || []).length) {
      (report.confidence.notes).forEach(function (n) {
        host.appendChild(el('div', 'note is-warn', n));
      });
    }
  }

  var SAMPLE_PLAN = [
    '{',
    '  "title": "Refactor auth token refresh",',
    '  "steps": [',
    '    {',
    '      "description": "Extract refresh logic",',
    '      "files": ["lib/src/auth/token_service.dart"],',
    '      "symbols": ["TokenService.refreshToken"]',
    '    }',
    '  ]',
    '}'
  ].join('\n');

  // ------------------------------------------------------------------ wiring

  function loadContract() {
    getJson('/api/contract').then(function (contract) {
      state.contract = contract;
      var lines = [];
      (contract.endpoints || []).forEach(function (e) {
        var line = e.method + '  ' + e.path;
        if (e.hasBody) line += '   (body)';
        lines.push(line);
        lines.push('       ' + e.description);
        if (e.queryParams) {
          Object.keys(e.queryParams).forEach(function (k) {
            lines.push('         ?' + k + ' = ' + e.queryParams[k]);
          });
        }
        lines.push('');
      });
      lines.push('severity bands : ' + (contract.severityBands || []).join(', '));
      lines.push('confidence     : ' + (contract.confidenceBands || []).join(', '));
      lines.push('error codes    : ' + (contract.errorCodes || []).join(', '));
      $('agent-contract').textContent = lines.join('\n');
    }).catch(function () {
      $('agent-contract').textContent = 'Could not load the API contract.';
    });
  }

  function analyze() {
    var btn = $('btn-reanalyze');
    btn.disabled = true;
    btn.textContent = 'Analyzing…';
    getJson('/api/impact/working-tree')
      .then(render)
      .catch(function (e) { toast('Analysis failed: ' + e.message); })
      .finally(function () {
        btn.disabled = false;
        btn.textContent = 'Re-analyze';
      });
  }

  function runPlan() {
    var text = $('plan-input').value.trim();
    if (!text) { toast('Paste a plan first'); return; }
    var btn = $('btn-run-plan');
    btn.disabled = true;
    btn.textContent = 'Running…';

    var payload;
    try {
      payload = JSON.parse(text);
    } catch (e) {
      payload = { planText: text };
    }

    fetch('/api/impact/plan', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload)
    })
      .then(function (r) {
        return r.json().then(function (body) { return { ok: r.ok, body: body }; });
      })
      .then(function (res) { renderPlanResult(res.body); })
      .catch(function (e) { toast('Plan failed: ' + e.message); })
      .finally(function () {
        btn.disabled = false;
        btn.textContent = 'Run plan';
      });
  }

  function switchTab(name) {
    state.activeTab = name;
    var tabs = document.querySelectorAll('.tab');
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].classList.toggle('is-active', tabs[i].dataset.tab === name);
    }
    var panes = document.querySelectorAll('.table-wrap');
    for (var j = 0; j < panes.length; j++) {
      panes[j].hidden = panes[j].dataset.pane !== name;
    }
  }

  function init() {
    $('btn-reanalyze').addEventListener('click', analyze);
    $('btn-export').addEventListener('click', function () {
      if (!state.report) return;
      copyText(JSON.stringify(state.report, null, 2), 'Report JSON');
    });
    $('btn-run-plan').addEventListener('click', runPlan);
    $('btn-sample-plan').addEventListener('click', function () {
      $('plan-input').value = SAMPLE_PLAN;
    });
    $('btn-copy-contract').addEventListener('click', function () {
      if (!state.contract) return;
      copyText(JSON.stringify(state.contract, null, 2), 'API contract');
    });
    $('btn-copy-report').addEventListener('click', function () {
      if (!state.report) return;
      copyText(JSON.stringify(state.report, null, 2), 'Report JSON');
    });

    var tabs = document.querySelectorAll('.tab');
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].addEventListener('click', function (e) { switchTab(e.currentTarget.dataset.tab); });
    }

    $('file-filter').addEventListener('input', function (e) {
      state.filter = e.target.value;
      if (state.report) renderTables(state.report);
    });

    $('toggle-files').addEventListener('change', function () { if (state.report) renderGraph(state.report); });
    $('toggle-symbols').addEventListener('change', function () { if (state.report) renderGraph(state.report); });
    $('btn-relayout').addEventListener('click', function () {
      if (state.view === 'rings' || state.view === 'sugiyama') { renderGraph(state.report); return; }
      if (!state.cy) return;
      state.cy.layout({
        name: 'breadthfirst',
        directed: true,
        nodeDimensionsIncludeLabels: true,
        nodeSeparation: 70,
        spacingFactor: 1.7,
        padding: 40,
        fit: true,
        animate: true,
        animationDuration: 400
      }).run();
    });

    var viewTabs = document.querySelectorAll('.view-tab');
    for (var v = 0; v < viewTabs.length; v++) {
      viewTabs[v].addEventListener('click', function (e) {
        setView(e.currentTarget.dataset.view);
      });
    }

    $('btn-clear-selection').addEventListener('click', function () {
      state.selectedPath = null;
      clearSelection();
    });

    var hashed = viewFromHash();
    if (hashed) setView(hashed);

    loadContract();
    analyze();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();