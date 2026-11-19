/**
 * Interactive family tree: expand/collapse ancestors, descendants, siblings per person.
 * Expects window.FAMILY_TREE_DATA from arbol-data.js
 */
(function () {
  const data = window.FAMILY_TREE_DATA;
  if (!data) {
    console.error("FAMILY_TREE_DATA missing");
    return;
  }

  const peopleById = Object.fromEntries(data.people.map((p) => [p.id, p]));
  const families = data.families;

  /** @type {Record<string, { ancestors: boolean, descendants: boolean, siblings: boolean }>} */
  const expanded = {};

  let rootId = data.focus;
  let orientation = "vertical";
  let selectedId = null;
  let detailHandler = null;

  function stateFor(id) {
    if (!expanded[id]) {
      expanded[id] = { ancestors: false, descendants: false, siblings: false };
    }
    return expanded[id];
  }

  function stripAccents(s) {
    return String(s || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/ñ/g, "n")
      .replace(/Ñ/g, "N")
      .replace(/–|—/g, "-");
  }

  function years(p) {
    const b = stripAccents(p.birth || "?");
    const d = p.death ? stripAccents(p.death) : null;
    return d ? `${b}-${d}` : `${b}-`;
  }

  function escapeHtml(s) {
    return stripAccents(String(s || "")).replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
    );
  }

  function spouseFamilies(personId) {
    return families
      .filter((f) => f.husband === personId || f.wife === personId)
      .sort((a, b) => (b.children?.length || 0) - (a.children?.length || 0));
  }

  function getSpouse(personId) {
    const fams = spouseFamilies(personId);
    const primary = fams[0];
    if (!primary) return null;
    const spouseId = primary.husband === personId ? primary.wife : primary.husband;
    return spouseId && peopleById[spouseId] ? peopleById[spouseId] : null;
  }

  function getChildrenIds(personId) {
    return [...new Set(spouseFamilies(personId).flatMap((f) => f.children || []))].filter(
      (id) => peopleById[id]
    );
  }

  function getParents(personId) {
    const person = peopleById[personId];
    if (!person?.famc) return { father: null, mother: null, family: null };
    const fam = families.find((f) => f.id === person.famc);
    if (!fam) return { father: null, mother: null, family: null };
    return {
      father: fam.husband && peopleById[fam.husband] ? peopleById[fam.husband] : null,
      mother: fam.wife && peopleById[fam.wife] ? peopleById[fam.wife] : null,
      family: fam
    };
  }

  function getSiblingIds(personId) {
    const { family } = getParents(personId);
    if (!family) return [];
    return (family.children || []).filter((id) => id !== personId && peopleById[id]);
  }

  function hasAncestors(personId) {
    const { father, mother } = getParents(personId);
    return !!(father || mother);
  }

  function hasDescendants(personId) {
    return getChildrenIds(personId).length > 0;
  }

  function hasSiblings(personId) {
    return getSiblingIds(personId).length > 0;
  }

  function cardHtml(p, opts = {}) {
    const selected = selectedId === p.id ? " selected" : "";
    const compact = opts.compact ? " compact" : "";
    return `<button type="button" class="card ${p.sex}${selected}${compact}" data-id="${p.id}" data-action="select">
      <span class="name">${escapeHtml(p.name)}</span>
      <span class="years">${escapeHtml(years(p))}</span>
      ${p.birthPlace && !opts.compact ? `<span class="place">${escapeHtml(p.birthPlace)}</span>` : ""}
    </button>`;
  }

  function toggleBtn(kind, personId, active, enabled, label, arrow) {
    if (!enabled) {
      return `<span class="tog disabled" title="Sin ${label}">${arrow}</span>`;
    }
    return `<button type="button" class="tog ${active ? "on" : ""}" data-action="toggle" data-kind="${kind}" data-id="${personId}" title="${active ? "Ocultar" : "Mostrar"} ${label}" aria-pressed="${active}">${arrow}</button>`;
  }

  // hideSpouse avoids father+mother each bringing the other as spouse (duplicate couples)
  function renderPerson(personId, trail, opts = {}) {
    const hideSpouse = !!opts.hideSpouse;
    const person = peopleById[personId];
    if (!person) return "";
    if (trail.has(personId)) {
      return `<div class="person-unit cycle"><div class="pair">${cardHtml(person)}</div></div>`;
    }

    const nextTrail = new Set(trail);
    nextTrail.add(personId);
    const st = stateFor(personId);
    const spouse = hideSpouse ? null : getSpouse(personId);
    const canA = hasAncestors(personId);
    const canD = hasDescendants(personId);
    const canS = hasSiblings(personId);

    let ancestorsHtml = "";
    if (st.ancestors && canA) {
      const { father, mother } = getParents(personId);
      // Show parents once as a couple (not two mirrored spouse pairs)
      const parentCards = [];
      if (father) parentCards.push(renderPerson(father.id, nextTrail, { hideSpouse: true }));
      if (mother) parentCards.push(renderPerson(mother.id, nextTrail, { hideSpouse: true }));
      ancestorsHtml = `<div class="branch-panel ancestors">
        <div class="branch-label">Antepasados</div>
        <div class="branch-row">
          ${parentCards.join("")}
        </div>
      </div>`;
    }

    let siblingsHtml = "";
    if (st.siblings && canS) {
      const sibs = getSiblingIds(personId);
      siblingsHtml = `<div class="branch-panel siblings">
        <div class="branch-label">Hermanos</div>
        <div class="branch-row">
          ${sibs.map((id) => renderPerson(id, nextTrail, { hideSpouse: true })).join("")}
        </div>
      </div>`;
    }

    let descendantsHtml = "";
    if (st.descendants && canD) {
      const kids = getChildrenIds(personId);
      descendantsHtml = `<div class="branch-panel descendants">
        <div class="branch-label">Descendientes</div>
        <div class="branch-row">
          ${kids.map((id) => renderPerson(id, nextTrail)).join("")}
        </div>
      </div>`;
    }

    const spouseHtml = spouse
      ? `<span class="amp">&amp;</span>${cardHtml(spouse)}`
      : "";

    return `<div class="person-unit" data-unit="${personId}">
      ${ancestorsHtml}
      <div class="mid">
        <div class="toggles" role="group" aria-label="Expandir relaciones">
          ${toggleBtn("ancestors", personId, st.ancestors, canA, "antepasados", "▲")}
          ${toggleBtn("siblings", personId, st.siblings, canS, "hermanos", "↔")}
          ${toggleBtn("descendants", personId, st.descendants, canD, "descendientes", "▼")}
        </div>
        <div class="pair">
          ${cardHtml(person)}
          ${spouseHtml}
        </div>
      </div>
      ${siblingsHtml}
      ${descendantsHtml}
    </div>`;
  }

  function renderInto(container) {
    if (!container) return;
    container.className = `interactive-tree ${orientation}`;
    container.innerHTML = renderPerson(rootId, new Set());
  }

  function expandRootDefaults() {
    const st = stateFor(rootId);
    // Open one useful level by default for the root
    if (hasDescendants(rootId)) st.descendants = true;
  }

  function bindContainer(container) {
    container.addEventListener("click", (e) => {
      const tog = e.target.closest("[data-action='toggle']");
      if (tog) {
        e.preventDefault();
        e.stopPropagation();
        const id = tog.dataset.id;
        const kind = tog.dataset.kind;
        const st = stateFor(id);
        st[kind] = !st[kind];
        renderInto(container);
        return;
      }

      const card = e.target.closest("[data-action='select']");
      if (card) {
        selectedId = card.dataset.id;
        if (typeof detailHandler === "function") {
          detailHandler(selectedId);
        }
        renderInto(container);
      }
    });
  }

  function fillRootSelect(selectEl) {
    if (!selectEl) return;
    selectEl.innerHTML = "";
    [...data.people]
      .sort((a, b) => stripAccents(a.name).localeCompare(stripAccents(b.name), "es"))
      .forEach((p) => {
        const opt = document.createElement("option");
        opt.value = p.id;
        opt.textContent = stripAccents(p.name);
        if (p.id === rootId) opt.selected = true;
        selectEl.appendChild(opt);
      });
  }

  function setRoot(id, container) {
    if (!peopleById[id]) return;
    rootId = id;
    expandRootDefaults();
    renderInto(container);
  }

  function setOrientation(value, container) {
    orientation = value === "horizontal" ? "horizontal" : "vertical";
    renderInto(container);
  }

  function getPerson(id) {
    return peopleById[id] || null;
  }

  function collapseAll(container) {
    Object.keys(expanded).forEach((id) => {
      expanded[id] = { ancestors: false, descendants: false, siblings: false };
    });
    expandRootDefaults();
    renderInto(container);
  }

  function expandAllVisible(container, depthLimit = 2) {
    function walk(id, depth, trail) {
      if (depth > depthLimit || trail.has(id)) return;
      trail.add(id);
      const st = stateFor(id);
      if (hasAncestors(id) && depth < 1) st.ancestors = true;
      if (hasDescendants(id)) st.descendants = true;
      if (hasSiblings(id) && depth === 0) st.siblings = true;
      getChildrenIds(id).forEach((cid) => walk(cid, depth + 1, new Set(trail)));
      const { father, mother } = getParents(id);
      if (father) walk(father.id, depth + 1, new Set(trail));
      if (mother) walk(mother.id, depth + 1, new Set(trail));
    }
    walk(rootId, 0, new Set());
    renderInto(container);
  }

  window.FamilyTreeUI = {
    data,
    peopleById,
    get rootId() {
      return rootId;
    },
    get orientation() {
      return orientation;
    },
    get selectedId() {
      return selectedId;
    },
    set selectedId(v) {
      selectedId = v;
    },
    years,
    escapeHtml,
    getPerson,
    fillRootSelect,
    setRoot,
    setOrientation,
    renderInto,
    bindContainer,
    expandRootDefaults,
    collapseAll,
    expandAllVisible,
    onDetail(fn) {
      detailHandler = fn;
    },
    source: data.source
  };
})();
