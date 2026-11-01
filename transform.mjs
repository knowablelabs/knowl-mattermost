// The Knowl changes to Mattermost that are mechanical rather than patches: "Channel" is
// "Topic" in the English strings, Public Sans and JetBrains Mono replace Mattermost's fonts,
// and the font files are copied in. docs/guides/agent-workspace-design.md, Topics and Brand.
// Run by build.sh on a checkout of Mattermost's source: node transform.mjs <source>.
import { copyFileSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

// --- Topics ------------------------------------------------------------------------------

const WORDS = [
  ["CHANNELS", "TOPICS"],
  ["CHANNEL", "TOPIC"],
  ["Channels", "Topics"],
  ["Channel", "Topic"],
  ["channels", "topics"],
  ["channel", "topic"],
];
const URL = /https?:\/\/[^\s"'<>)]+/g;
// A direct or group message is a conversation, not a Topic.
const KEEP_AFTER = /(direct message|group message|message|DM|GM)\s*$/i;

// One string: every Channel word outside ICU argument names and URLs.
export function topics(text) {
  let out = "";
  let last = 0;
  for (const url of text.matchAll(URL)) {
    out += topicWords(text.slice(last, url.index));
    out += url[0];
    last = url.index + url[0].length;
  }
  return out + topicWords(text.slice(last));
}

function topicWords(text) {
  return text.replace(/\b(CHANNELS|CHANNEL|Channels|Channel|channels|channel)\b/g, (word, _w, at) => {
    const before = text.slice(0, at);
    const after = text[at + word.length] ?? "";
    // {channel} or {channel, select, …}: an argument's name, not text.
    if (before.endsWith("{") && (after === "}" || after === ",")) return word;
    if (KEEP_AFTER.test(before)) return word;
    return WORDS.find(([from]) => from === word)[1];
  });
}

function relabel(path) {
  const strings = JSON.parse(readFileSync(path, "utf8"));
  let changed = 0;
  if (Array.isArray(strings)) {
    // The server's i18n: [{id, translation}], translation a string or {one, other}.
    for (const item of strings) {
      if (typeof item.translation === "string") {
        const next = topics(item.translation);
        if (next !== item.translation) ((item.translation = next), changed++);
      } else if (item.translation && typeof item.translation === "object") {
        for (const key of Object.keys(item.translation)) {
          const next = topics(item.translation[key]);
          if (next !== item.translation[key]) ((item.translation[key] = next), changed++);
        }
      }
    }
  } else {
    for (const [key, value] of Object.entries(strings)) {
      const next = topics(value);
      if (next !== value) ((strings[key] = next), changed++);
    }
  }
  writeFileSync(path, JSON.stringify(strings, null, 2) + "\n");
  return changed;
}

// --- fonts -------------------------------------------------------------------------------

const STYLE_FILES = new Set([".scss", ".css", ".tsx", ".ts", ".jsx", ".js"]);
const FONT_FACE = /@font-face\s*\{[^}]*\}/g;

export function fonts(text) {
  // @font-face blocks declare the files; only the uses are renamed.
  let out = "";
  let last = 0;
  for (const face of text.matchAll(FONT_FACE)) {
    out += fontUses(text.slice(last, face.index)) + face[0];
    last = face.index + face[0].length;
  }
  return out + fontUses(text.slice(last));
}

function fontUses(text) {
  return text
    .replace(/(['"])Open Sans\1/g, "$1Public Sans$1")
    .replace(/(['"])Metropolis\1/g, "$1Public Sans$1")
    .replace(/(font-family:\s*)Metropolis\b/g, "$1'Public Sans'")
    .replace(/(font-family:\s*)(Menlo|Monaco|Consolas|monospace)\b/g, "$1'JetBrains Mono', $2");
}

function walk(dir, visit) {
  for (const name of readdirSync(dir)) {
    if (name === "node_modules" || name === "dist" || name.startsWith(".")) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walk(full, visit);
    else if (STYLE_FILES.has(extname(name)) && !/\.test\.|__snapshots__/.test(full)) visit(full);
  }
}

function restyle(root) {
  let changed = 0;
  walk(root, (path) => {
    const text = readFileSync(path, "utf8");
    if (!/Open Sans|Metropolis|Menlo|Monaco|Consolas|monospace/.test(text)) return;
    const next = fonts(text);
    if (next !== text) (writeFileSync(path, next), changed++);
  });
  return changed;
}

// Add our notice without replacing the upstream copyright. Mattermost's customization
// guidance asks that its login/About notices remain. See organization-hosting-pilot.md.
function brandCopyright(source) {
  const path = join(source, "webapp/channels/src/components/header_footer_route/footer.tsx");
  const original = "{`© ${new Date().getFullYear()} Mattermost Inc.`}";
  const replacement = "{`© ${new Date().getFullYear()} Knowable Labs Inc. · © ${new Date().getFullYear()} Mattermost Inc.`}";
  const text = readFileSync(path, "utf8");
  if (text.includes(replacement)) return;
  if (!text.includes(original)) throw new Error("Pinned Mattermost footer changed; review copyright notices");
  writeFileSync(path, text.replace(original, replacement));
}

// --- main --------------------------------------------------------------------------------

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const source = process.argv[2];
  if (!source) throw new Error("usage: node transform.mjs <mattermost source>");
  brandCopyright(source);
  const webapp = relabel(join(source, "webapp/channels/src/i18n/en.json"));
  const server = relabel(join(source, "server/i18n/en.json"));
  const styled = restyle(join(source, "webapp/channels/src")) + restyle(join(source, "webapp/platform/components/src"));
  const target = join(source, "webapp/channels/src/fonts/knowl");
  mkdirSync(target, { recursive: true });
  for (const name of readdirSync(join(here, "fonts"))) copyFileSync(join(here, "fonts", name), join(target, name));
  process.stdout.write(`topics: ${webapp} webapp strings, ${server} server strings; fonts: ${styled} files\n`);
}
