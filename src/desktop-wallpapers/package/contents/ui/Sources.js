.pragma library
// Helpers shared by the wallpaper and its settings page.
//
// Settings model: { default: entry, desktops: { "<desktop id>": entry } }
// entry: { mode: "image" | "folder", url, order: "sequential" | "reverse" | "random", interval: seconds }
// ("sequential" is alphabetical order, "reverse" the same backwards)
// A desktop without an entry uses the default one.

const imagePattern = /\.(jpe?g|png|webp|avif|jxl|bmp|gif|tiff?|svgz?)$/i;
const nameFilters = ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif", "*.jxl", "*.bmp", "*.gif", "*.tif", "*.tiff", "*.svg", "*.svgz"];

function isImage(url) {
    return imagePattern.test(String(url));
}

function normalize(entry) {
    const e = entry || {};
    return {
        mode: e.mode === "image" ? "image" : "folder",
        url: String(e.url || ""),
        order: e.order === "random" || e.order === "reverse" ? e.order : "sequential",
        interval: Math.max(60, Number(e.interval) || 86400),
    };
}

function defaultEntry() {
    return normalize({ mode: "folder", url: "file:///usr/share/wallpapers/" });
}

function parse(settings) {
    let raw = {};
    try {
        raw = JSON.parse(settings || "{}") || {};
    } catch (e) {
        raw = {};
    }
    const model = { default: raw.default ? normalize(raw.default) : defaultEntry(), desktops: {} };
    for (const id of Object.keys(raw.desktops || {})) {
        model.desktops[id] = normalize(raw.desktops[id]);
    }
    return model;
}

function stringify(model) {
    return JSON.stringify(model);
}

function effective(model, desktopId) {
    return model.desktops[desktopId] || model.default;
}

// The folder a source lives in: the folder itself, or the one holding the single image.
function folderOf(entry) {
    if (!entry.url) {
        return "";
    }
    return entry.mode === "folder" ? entry.url.replace(/\/?$/, "/") : entry.url.replace(/[^/]*$/, "");
}

function path(url) {
    return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
}

function fileName(url) {
    return path(url).replace(/\/$/, "").replace(/^.*\//, "");
}

// A stable number from a string, well mixed: strings that differ by one character
// must not give numbers that agree in their low bits, which is all a small folder uses.
function hash(text) {
    let h = 2166136261;
    for (let i = 0; i < text.length; ++i) {
        h = Math.imul(h ^ text.charCodeAt(i), 16777619) >>> 0;
    }
    h ^= h >>> 16;
    h = Math.imul(h, 0x85ebca6b) >>> 0;
    h ^= h >>> 13;
    h = Math.imul(h, 0xc2b2ae35) >>> 0;
    h ^= h >>> 16;
    return h >>> 0;
}

// The number of the interval that `now` (seconds since the epoch) is in. Intervals are
// counted in local time, so that "every day" changes at midnight and not at midnight UTC.
function tick(entry, now) {
    const local = now - new Date(now * 1000).getTimezoneOffset() * 60;
    return Math.floor(local / entry.interval);
}

// Which of a folder's `count` images to show in interval `tick`. `key` differs per screen and
// desktop, so each one goes its own way. `held` is the index of the image shown until now, or
// -1 if there was none or it is gone: in order, the next (or previous) one follows it; at random, it is
// not picked twice in a row.
function next(entry, count, key, tick, held) {
    if (count <= 0) {
        return -1;
    }
    if (entry.order === "random") {
        const index = hash(key + "#" + tick) % count;
        return index === held && count > 1 ? (index + 1) % count : index;
    }
    if (entry.order === "reverse") {
        return held >= 0 ? (held - 1 + count) % count : count - 1 - (hash(key) + tick) % count;
    }
    return held >= 0 ? (held + 1) % count : (hash(key) + tick) % count;
}

// The remembered picks: { "<desktop id>": { url, tick, folder, order } }
function parseState(text) {
    try {
        const state = JSON.parse(text || "{}");
        return state && typeof state === "object" ? state : {};
    } catch (e) {
        return {};
    }
}

// ["id=url", ...] -> { id: url }
function toMap(list) {
    const map = {};
    for (const item of (list || [])) {
        const at = String(item).indexOf("=");
        if (at > 0) {
            map[item.slice(0, at)] = item.slice(at + 1);
        }
    }
    return map;
}
