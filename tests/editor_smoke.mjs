#!/usr/bin/env node
// editor_smoke.mjs -- run the editor page's script against a stub DOM.
//
// assets/editor.html is the only part of Macroforge whose behaviour Lua cannot
// observe: it renders the macro sidebar, writes the dynamic window title and
// switches between the form and JSON views. This harness feeds the page's own
// script a minimal DOM plus the payload the HTTP API would return, then
// asserts on what the script actually produced.
//
// Usage: node tests/editor_smoke.mjs <fixture.json> <editor.html>
// The fixture carries { catalog, macros, errors } exactly as the two API
// endpoints would answer them; tests/test_editor_runtime.lua builds it.

import { readFileSync } from "node:fs";

const [fixturePath, htmlPath] = process.argv.slice(2);
if (!fixturePath || !htmlPath) {
  console.error("usage: editor_smoke.mjs <fixture.json> <editor.html>");
  process.exit(2);
}

const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));
const html = readFileSync(htmlPath, "utf8");

// ---------------------------------------------------------------- stub DOM
function matches(el, selector) {
  // Supports: tag, .class, tag.class, [attr="value"], tag[attr="value"].
  let rest = selector;
  const tag = /^[a-zA-Z]+/.exec(rest);
  if (tag) {
    if (el.tagName && el.tagName.toLowerCase() !== tag[0].toLowerCase()) return false;
    rest = rest.slice(tag[0].length);
  }
  for (const attr of rest.match(/\[[a-z-]+="[^"]*"\]/g) || []) {
    const m = /\[([a-z-]+)="([^"]*)"\]/.exec(attr);
    if (el.getAttribute(m[1]) !== m[2]) return false;
  }
  for (const cls of rest.match(/\.[a-zA-Z0-9_-]+/g) || []) {
    if (!el.className.split(/\s+/).includes(cls.slice(1))) return false;
  }
  return true;
}

function makeElement(tag) {
  const el = {
    tagName: String(tag).toUpperCase(),
    id: "",
    className: "",
    dataset: {},
    children: [],
    parentNode: null,
    attributes: {},
    style: {},
    value: "",
    checked: false,
    hidden: false,
    title: "",
    type: "",
    disabled: false,
    textContent: "",
    innerHTML: "",
    listeners: {},
    classList: null,
  };
  el.classList = {
    add: (...c) => { el.className = [...new Set([...el.className.split(/\s+/).filter(Boolean), ...c])].join(" "); },
    remove: (...c) => { el.className = el.className.split(/\s+/).filter((x) => x && !c.includes(x)).join(" "); },
    contains: (c) => el.className.split(/\s+/).includes(c),
    toggle: (c) => { el.classList.contains(c) ? el.classList.remove(c) : el.classList.add(c); },
  };
  el.appendChild = (child) => {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = el;
    el.children.push(child);
    return child;
  };
  el.insertBefore = (child, ref) => {
    child.parentNode = el;
    const at = ref ? Math.max(0, el.children.indexOf(ref)) : el.children.length;
    el.children.splice(at, 0, child);
    return child;
  };
  el.removeChild = (child) => {
    const at = el.children.indexOf(child);
    if (at >= 0) el.children.splice(at, 1);
    child.parentNode = null;
    return child;
  };
  el.remove = () => { if (el.parentNode) el.parentNode.removeChild(el); };
  el.setAttribute = (name, value) => { el.attributes[name] = String(value); };
  el.getAttribute = (name) => (name in el.attributes ? el.attributes[name] : null);
  el.hasAttribute = (name) => name in el.attributes;
  el.addEventListener = (type, fn) => { (el.listeners[type] = el.listeners[type] || []).push(fn); };
  el.removeEventListener = () => {};
  el.dispatch = (type, event) => {
    const fake = Object.assign({ type, target: el, currentTarget: el, stopPropagation() {}, preventDefault() {} }, event);
    for (const fn of el.listeners[type] || []) fn(fake);
    // The page listens on ancestors too, so let the event bubble.
    let node = el.parentNode;
    while (node) {
      for (const fn of node.listeners[type] || []) fn(fake);
      node = node.parentNode;
    }
    return fake;
  };
  el.click = () => el.dispatch("click");
  el.closest = (selector) => {
    let node = el;
    while (node) { if (matches(node, selector)) return node; node = node.parentNode; }
    return null;
  };
  el.querySelector = (selector) => el.querySelectorAll(selector)[0] || null;
  el.querySelectorAll = (selector) => {
    const out = [];
    const walk = (node) => {
      for (const child of node.children) {
        if (matches(child, selector)) out.push(child);
        walk(child);
      }
    };
    walk(el);
    return out;
  };
  el.contains = (other) => {
    let node = other;
    while (node) { if (node === el) return true; node = node.parentNode; }
    return false;
  };
  el.focus = () => {};
  el.blur = () => {};
  el.scrollIntoView = () => {};
  el.getBoundingClientRect = () => ({ top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0 });
  // textContent / innerHTML need getters, so re-define them on the instance.
  Object.defineProperty(el, "textContent", {
    get() { return el.__text !== undefined ? el.__text : el.children.map((c) => c.textContent || "").join(""); },
    set(v) { el.__text = String(v); el.children.length = 0; },
  });
  Object.defineProperty(el, "innerHTML", {
    get() { return el.__html !== undefined ? el.__html : ""; },
    set(v) { el.__html = String(v); el.children.length = 0; },
  });
  return el;
}

const byId = new Map();
const document = {
  body: makeElement("body"),
  documentElement: makeElement("html"),
  activeElement: null,
  listeners: {},
  getElementById(id) {
    if (!byId.has(id)) { const el = makeElement("div"); el.id = id; byId.set(id, el); }
    return byId.get(id);
  },
  createElement: (tag) => makeElement(tag),
  createTextNode: (text) => { const el = makeElement("#text"); el.textContent = text; return el; },
  addEventListener: (type, fn) => { (document.listeners[type] = document.listeners[type] || []).push(fn); },
  dispatch: (type, event) => { for (const fn of document.listeners[type] || []) fn(Object.assign({ type }, event)); },
  querySelector: () => null,
  querySelectorAll: () => [],
};
const window = {
  listeners: {},
  addEventListener: (type, fn) => { (window.listeners[type] = window.listeners[type] || []).push(fn); },
  removeEventListener: () => {},
  matchMedia: () => ({ matches: false, addEventListener() {}, addListener() {} }),
  location: { href: "http://127.0.0.1:8099/macroforge/", hash: "" },
};

const fetchStub = (url) => {
  const payload = String(url).includes("/api/catalog")
    ? fixture.catalog
    : { macros: fixture.macros, errors: fixture.errors };
  return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(JSON.stringify(payload)) });
};

// ------------------------------------------------------------------ run it
const scriptMatch = /<script>\s*([\s\S]*?)<\/script>/.exec(html);
if (!scriptMatch) {
  console.error("FAIL smoke: no inline <script> found in the editor page");
  process.exit(1);
}

const runPage = new Function(
  "document", "window", "fetch", "location", "navigator", "console", "setTimeout", "clearTimeout",
  scriptMatch[1]
);
runPage(document, window, fetchStub, window.location, { userAgent: "node" }, console, setTimeout, clearTimeout);

const settle = () => new Promise((resolve) => setTimeout(resolve, 5));
await settle();
await settle();

// --------------------------------------------------------------- assertions
let failures = 0;
function check(name, condition, detail) {
  if (condition) {
    console.log("ok   smoke: " + name);
  } else {
    failures++;
    console.log("FAIL smoke: " + name + (detail === undefined ? "" : "\n  " + detail));
  }
}
function byIdOf(id) { return document.getElementById(id); }

const list = byIdOf("macro-list");
const rows = list.children.filter((c) => c.className.split(/\s+/).includes("macro-item"));
const expectedIds = fixture.macros.map((m) => m.id).sort();
const renderedIds = rows.map((r) => r.dataset.id).sort();

check("the sidebar renders one row per macro",
  rows.length === fixture.macros.length && String(renderedIds) === String(expectedIds),
  "expected " + JSON.stringify(expectedIds) + ", got " + JSON.stringify(renderedIds));

const iconOf = (row) => row.children.find((c) => c.className.split(/\s+/).includes("mi-icon")) || null;
const everyRowHasIcon = rows.every((row) => iconOf(row));
check("every row carries a trigger icon", everyRowHasIcon,
  rows.filter((r) => !iconOf(r)).map((r) => r.dataset.id).join(", ") + " have none");
check("icons are inline svg", rows.every((row) => (iconOf(row).innerHTML || "").trim().startsWith("<svg")),
  (iconOf(rows[0]) || {}).innerHTML);

const disabled = fixture.macros.filter((m) => m.enabled === false).map((m) => m.id);
check("a disabled macro's icon is marked off",
  disabled.every((id) => { const row = rows.find((r) => r.dataset.id === id); return row && iconOf(row).className.includes(" off"); }),
  "expected .off on " + disabled.join(", "));

const triggerTypes = [...new Set(fixture.macros.filter((m) => m.trigger).map((m) => m.trigger.type))];
check("icon classes carry the trigger type",
  triggerTypes.every((t) => rows.some((r) => iconOf(r).className.split(/\s+/).includes(t))),
  "no row for " + triggerTypes.join(", "));

const sortedNames = fixture.macros.map((m) => m.name).sort((a, b) => a.localeCompare(b));
check("the window title shows the first macro",
  byIdOf("window-title").textContent === sortedNames[0],
  "expected " + JSON.stringify(sortedNames[0]) + ", got " + JSON.stringify(byIdOf("window-title").textContent));
check("the row count is reported",
  byIdOf("count").textContent === fixture.macros.length + " / " + fixture.macros.length,
  byIdOf("count").textContent);

// Selecting another row must move the window title.
const second = rows.slice().sort((a, b) => a.textContent.localeCompare(b.textContent))[1];
second.dispatch("click", { target: second });
await settle();
const selected = fixture.macros.find((m) => m.id === second.dataset.id);
check("clicking a row moves the window title",
  byIdOf("window-title").textContent === selected.name,
  "expected " + JSON.stringify(selected.name) + ", got " + JSON.stringify(byIdOf("window-title").textContent));

// Mode switch: the [hidden] attribute is what the Apple UI relies on, so this
// exercises the guard the CSS depends on.
check("the empty state is hidden once a macro is loaded", byIdOf("empty-state").hidden === true, String(byIdOf("empty-state").hidden));
check("the form is shown and JSON is hidden by default",
  byIdOf("form-wrap").hidden === false && byIdOf("json-wrap").hidden === true,
  "form=" + byIdOf("form-wrap").hidden + " json=" + byIdOf("json-wrap").hidden);

byIdOf("mode-json").click();
await settle();
check("switching to JSON hides the form and fills the editor",
  byIdOf("form-wrap").hidden === true && byIdOf("json-wrap").hidden === false
  && byIdOf("json-view").value.includes('"id"') && byIdOf("json-view").value.includes(second.dataset.id),
  "json=" + JSON.stringify((byIdOf("json-view").value || "").slice(0, 80)));
check("the JSON mode button reports pressed",
  byIdOf("mode-json").getAttribute("aria-pressed") === "true" && byIdOf("mode-form").getAttribute("aria-pressed") === "false",
  "form=" + byIdOf("mode-form").getAttribute("aria-pressed") + " json=" + byIdOf("mode-json").getAttribute("aria-pressed"));

byIdOf("mode-form").click();
await settle();
check("switching back to the form restores the form",
  byIdOf("form-wrap").hidden === false && byIdOf("json-wrap").hidden === true,
  "form=" + byIdOf("form-wrap").hidden + " json=" + byIdOf("json-wrap").hidden);

// The form is built from the catalog, so a missing action type or a broken
// parameter table shows up here rather than in a browser.
const actionCards = byIdOf("actions").querySelectorAll(".action");
check("the form renders one card per action",
  actionCards.length === selected.actions.length,
  "expected " + selected.actions.length + " cards, got " + actionCards.length);
const selects = byIdOf("actions").querySelectorAll("select");
check("action cards expose a type picker",
  selects.every((s) => s.children.length > 1),
  selects.map((s) => s.children.length).join(","));

// The datalist is created at runtime, which is why the id looks absent from the
// markup -- keep it working or the name field loses its suggestions.
check("the datalist is created at runtime", !!byIdOf("macro-id-list"), "macro-id-list missing");

console.log(failures === 0
  ? "editor script smoke: all assertions passed"
  : "editor script smoke: " + failures + " assertion(s) failed");
process.exit(failures === 0 ? 0 : 1);

