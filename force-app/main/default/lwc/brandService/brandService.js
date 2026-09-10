import APPLE_RESOURCE from '@salesforce/resourceUrl/tbimagesApple';
import DELL_RESOURCE from '@salesforce/resourceUrl/tbimagesDell';
import HP_RESOURCE from '@salesforce/resourceUrl/tbimagesHp';
import LENOVO_RESOURCE from '@salesforce/resourceUrl/tbimagesLenovo';
import ASUS_RESOURCE from '@salesforce/resourceUrl/tbimagesAsus';
import ACER_RESOURCE from '@salesforce/resourceUrl/tbimagesAcer';
import SAMSUNG_RESOURCE from '@salesforce/resourceUrl/tbimagesSamsung';

/**
 * brandService — single source of truth for laptop brand definitions AND
 * product photo resolution.
 *
 * Each brand's `images` array lists every real photo file inside that
 * brand's own dedicated static resource (tbimagesApple, tbimagesDell, etc.
 * — each brand's photo folder is deployed as its own folder-type static
 * resource, split out from a single shared one so each stays comfortably
 * under Salesforce's 5MB-per-resource limit). Photos are never shared
 * across brands: a product's gallery is built entirely from its own
 * brand's resource, never from another brand's or from a generic pool, so
 * a MacBook can never show a Dell photo and vice versa.
 */
const BRANDS = [
    {
        id: 'b1', name: 'Apple',
        keywords: ['macbook', 'apple', 'm1 laptop', 'm5 pro'],
        resourceUrl: APPLE_RESOURCE,
        images: [
            'Apple  5.webp',
            'Apple M1.webp',
            'Apple m5 pro chip.webp',
            'Apple MacBook Air 15 M2.webp',
            'Apple MacBook Air M3 16GB.webp',
            'Apple MacBook Air M3.webp',
            'Apple MacBook Pro 16 Max.webp',
            'Apple other 1.webp',
            'Apple Other 2.webp',
            'Apple other 3.webp',
            'Apple Other 5.webp',
            'Apple Other 6.webp',
            'Apple Other 7.webp',
            'Apple other 9.webp',
            'Apple Other4.webp'
        ]
    },
    {
        id: 'b2', name: 'Dell',
        keywords: ['dell', 'xps', 'inspiron', 'vostro', 'alienware', 'latitude'],
        resourceUrl: DELL_RESOURCE,
        images: [
            'Dell 5420.webp',
            'Dell Alienware m17.webp',
            'Dell G15.webp',
            'Dell Inspiron 14.avif',
            'Dell Inspiron 15.webp',
            'Dell Latitude 5000.jpg',
            'Dell other 11.avif',
            'Dell Other 12.avif',
            'Dell Other 3.webp',
            'Dell Other 4.webp',
            'Dell Other 5.webp',
            'Dell Other 6.webp',
            'Dell Other 7.webp',
            'Dell Vostro 15.avif',
            'Dell XPS 13 Plus other 3.avif',
            'Dell XPS 13 Plus other 4.avif',
            'Dell XPS 13 Plus other.avif',
            'Dell XPS 13 Plus ther 2.avif',
            'Dell XPS 13 Plus.avif',
            'Dell XPS 15.avif',
            'Dellother 1.webp',
            'Other 1.webp'
        ]
    },
    {
        id: 'b3', name: 'HP',
        keywords: ['hp', 'spectre', 'pavilion', 'envy', 'elitebook', 'probook', 'omen', 'victus', 'zbook'],
        resourceUrl: HP_RESOURCE,
        images: [
            'HP EliteBook 840.webp',
            'HP EliteBook 860.jpg',
            'HP Envy 14.jpg',
            'HP Omen 16 other 1.avif',
            'HP Omen 16 other 3.avif',
            'HP Omen 16 other.avif',
            'HP Omen 16.avif',
            'Hp other 1.webp',
            'Hp other 2.jpg',
            'Hp other 3.jpg',
            'Hp other 4.jpg',
            'Hp other 5.jpg',
            'Hp other 8.webp',
            'Hp other 9.webp',
            'Hp other6.jpg',
            'HP Pavilion 15.webp',
            'HP ProBook 440.webp',
            'HP ProBook 450.jpg',
            'HP Spectre x360.webp',
            'HP Victus 15.webp',
            'HP ZBook Fury 16.webp'
        ]
    },
    {
        id: 'b4', name: 'Lenovo',
        keywords: ['lenovo', 'thinkpad', 'ideapad', 'legion', 'yoga'],
        resourceUrl: LENOVO_RESOURCE,
        images: [
            'Lenovo IdeaPad 5 Pro.jpg',
            'Lenovo IdeaPad Gaming 3.avif',
            'Lenovo IdeaPad Gaming 3.jpg',
            'Lenovo Legion 5 Pro.avif',
            'Lenovo other.jpg',
            'Lenovo other0.jpg',
            'Lenovo other2.jpg',
            'Lenovo other3.jpg',
            'Lenovo other4.jpg',
            'Lenovo other5.jpg',
            'Lenovo other6.jpg',
            'Lenovo other7.jpg',
            'Lenovo ThinkPad E15.avif',
            'Lenovo ThinkPad T14s.webp',
            'Lenovo ThinkPad X1 Carbon.avif',
            'Lenovo Yoga 2 other 1.avif',
            'Lenovo Yoga 2 other 2.avif',
            'Lenovo Yoga 2.avif',
            'Lenovo Yoga 9 Pro.avif',
            'Lenovo Yoga other 1.jpg',
            'Lenovo Yoga other 2.jpg',
            'Lenovo Yoga other 3.jpg',
            'Lenovo Yoga other 4.jpg',
            'Lenovo Yoga.webp'
        ]
    },
    {
        id: 'b5', name: 'ASUS',
        // 'chromebook' deliberately excluded — Acer also makes Chromebooks
        // ("Acer Chromebook 315"), and since ASUS is checked first, a shared
        // keyword would have misclassified Acer's as ASUS. Real product
        // names always lead with the actual brand name ("Asus Chromebook
        // 14"), so 'asus' alone already catches every real ASUS model.
        keywords: ['asus', 'zenbook', 'vivobook', 'rog', 'tuf', 'expertbook'],
        resourceUrl: ASUS_RESOURCE,
        // The original folder also contained a saved product page's site
        // assets (icons, css, js, and unrelated CDN images like a printer
        // photo) — those were deleted from disk, and only the genuine,
        // clearly-named ASUS product photos remain, so a laptop card can
        // never end up showing a Flipkart nav icon.
        images: [
            'Asus Chromebook 14.webp',
            'Asus ExpertBook B6.webp',
            'Asus Other 1.webp',
            'Asus Other 10.webp',
            'Asus Other 11.webp',
            'Asus Other 12.webp',
            'Asus Other 2.webp',
            'Asus other 3.webp',
            'Asus Other 4.webp',
            'Asus Other 5.webp',
            'Asus Other 6.webp',
            'Asus Other 7.webp',
            'Asus Other 8.webp',
            'Asus ROG Zephyrus other.webp',
            'Asus ROG Zephyrus.webp',
            'Asus TUF Gaming A15.webp',
            'Asus TUF.webp',
            'Asus VivoBook 15.webp',
            'Asus Vivobook.webp',
            'Asus ZenBook 13.webp',
            'Asus ZenBook Pro.webp'
        ]
    },
    {
        id: 'b6', name: 'Acer',
        keywords: ['acer', 'aspire', 'nitro', 'predator', 'swift', 'travelmate'],
        resourceUrl: ACER_RESOURCE,
        images: [
            'Acer Aspire 3.png',
            'Acer aspire 5.png',
            'Acer Chromebook 315.webp',
            'Acer Detail 1.webp',
            'Acer Detail 2.webp',
            'Acer Detail 3.webp',
            'Acer Detail 4.webp',
            'Acer Detail 5.webp',
            'Acer Detail 6.webp',
            'Acer Detail 7.webp',
            'Acer Detail 8.webp',
            'Acer Nitro V 15.webp',
            'Acer Predator Helios Neo 16.webp',
            'Acer Swift Go 14.webp',
            'aspire_7--core_5_1_un.dwcsi.001.webp'
        ]
    },
    {
        id: 'b7', name: 'Samsung',
        keywords: ['samsung', 'galaxy book'],
        resourceUrl: SAMSUNG_RESOURCE,
        images: [
            'Samsung Galaxy Book Flex2.jpg',
            'Samsung Galaxy Book Ion.webp',
            'Samsung Galaxy Book2 Pro.jpg',
            'Samsung Galaxy Book2.jpg',
            'Samsung Galaxy Book3 Pro other1.jpg',
            'Samsung Galaxy Book3 Pro.jpg',
            'Samsung Galaxy Book3 Ultra.avif',
            'Samsung Galaxy Book3.jpg',
            'Samsung Galaxy Book4 Pro other.jpg',
            'Samsung Galaxy Book4 Pro.jpg',
            'Samsung Galaxy Book4 Ultra other 1.avif',
            'Samsung Galaxy Book4 Ultra other 2.avif',
            'Samsung Galaxy Book4 Ultra other.avif',
            'Samsung Galaxy Book4 Ultra.webp',
            'Samsung Galaxy Book4.png',
            'Samsung Other.jpg',
            'Samsung Other1.jpg',
            'Samsung Other10.jpg',
            'Samsung Other2.jpg',
            'Samsung Other3.jpg',
            'Samsung Other5.jpg',
            'Samsung Other6.jpg',
            'Samsung Other7.jpg',
            'Samsung Other8.jpg'
        ]
    }
];

/** Fallback brand used when no keyword matches the product name at all. */
const DEFAULT_BRAND = { id: 'default', name: 'LaptopKart', resourceUrl: '', images: [] };

/**
 * Small deterministic string hash (djb2-style) — same input always maps to
 * the same rotation/pick, so a shopper doesn't see images reshuffle on
 * every page load, but two different product names almost always land on
 * different picks.
 * @param {string} str - input string to hash
 * @returns {number} non-negative integer hash
 */
function hashString(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        hash = (hash * 31 + str.charCodeAt(i)) >>> 0;
    }
    return hash;
}

/** Lowercases and strips everything but letters/digits, so "Acer Aspire 3" and "Acer  Aspire-3.png" compare equal. */
function normalize(str) {
    return (str || '').toLowerCase().replace(/[^a-z0-9]/g, '');
}

/** Strips the file extension off a filename. */
function stripExt(filename) {
    return filename.replace(/\.[a-z0-9]+$/i, '');
}

/**
 * Matches a trailing "other N" / "otherN" / "ther N" (a typo present in a
 * few real filenames, e.g. "Dell XPS 13 Plus ther 2.avif") / "detail N"
 * suffix, with or without the space, with or without the number.
 */
const OTHER_SUFFIX_RE = /\s*(?:o?ther|detail)\s*\d*$/i;

/**
 * Identifies which specific product (if any) a photo belongs to.
 *
 * Extra shots were downloaded per-model, named like the model plus an
 * "other N" suffix — e.g. "Dell XPS 13 Plus other 3.avif" or "HP Omen 16
 * other 1.avif" belong ONLY to that exact model, never to a different one.
 * Separately, some brands also have plain brand-wide filler shots with no
 * model name at all (e.g. "Apple other 1.webp", "Acer Detail 1.webp") —
 * those are the only images allowed to be used as a generic fallback.
 *
 * @param {string} filename - image filename
 * @param {Object} brand - brand definition (used to recognize brand-only filenames)
 * @returns {{ coreNorm: string, isGeneric: boolean }} the normalized model
 *   name this photo depicts (coreNorm), and whether it's brand-wide filler
 *   with no specific model identity (isGeneric)
 */
function classifyImage(filename, brand) {
    const core = stripExt(filename).replace(OTHER_SUFFIX_RE, '');
    const coreNorm = normalize(core);
    const brandNorm = normalize(brand.name);
    const isGeneric = coreNorm === '' || coreNorm === brandNorm;
    return { coreNorm, isGeneric };
}

/**
 * True when an image (already classified) actually depicts the given
 * product — either its dedicated main photo or one of ITS OWN "other N"
 * shots — using the same exact/prefix rule as the lead photo match.
 * @param {string} coreNorm - the image's classified core model name
 * @param {string} targetNorm - the product name being matched, normalized
 * @returns {boolean}
 */
function coreMatchesProduct(coreNorm, targetNorm) {
    if (!coreNorm) return false;
    if (coreNorm === targetNorm) return true;
    return coreNorm.length >= 6 && targetNorm.startsWith(coreNorm);
}

/** Builds the absolute URL for one file inside a brand's own static resource. */
function buildUrl(resourceUrl, filename) {
    return `${resourceUrl}/${encodeURIComponent(filename)}`;
}

/**
 * Picks the one photo in a brand's folder that best represents this exact
 * product, in three tiers:
 *   1. Exact match — the file's name (minus extension) normalizes to
 *      exactly the product name (e.g. "Dell XPS 15" ↔ "Dell XPS 15.avif").
 *   2. Prefix match — the file names a shorter/simpler variant of this
 *      product (e.g. "Apple M1.webp" for "Apple M1 Laptop") — the longest
 *      such match wins, so the most specific dedicated photo is preferred.
 *   3. No dedicated photo exists for this exact model: falls back to one of
 *      the brand's generic filler shots (filenames containing "other" or
 *      "detail") rather than borrowing another specific model's dedicated
 *      photo, so e.g. an unmatched Acer model never shows as a specific
 *      "Nitro V 15" instead. Picked deterministically by hash.
 * @param {string} productName - product name to match
 * @param {Object} brand - brand definition with a folder-scoped `images` array
 * @returns {string} the chosen filename
 */
function pickLeadFilename(productName, brand) {
    const targetNorm = normalize(productName);

    const exact = brand.images.find((f) => normalize(stripExt(f)) === targetNorm);
    if (exact) return exact;

    const prefixMatches = brand.images
        .map((f) => ({ f, n: normalize(stripExt(f)) }))
        .filter(({ n }) => n.length >= 6 && targetNorm.startsWith(n))
        .sort((a, b) => b.n.length - a.n.length);
    if (prefixMatches.length) return prefixMatches[0].f;

    // No dedicated photo for this exact model — fall back to a brand-wide
    // filler shot ONLY (no specific model name in it), never to another
    // model's dedicated "other N" shot, which would show as if it were a
    // real photo of THIS model.
    const generic = brand.images.filter((f) => classifyImage(f, brand).isGeneric);
    const pool = generic.length ? generic : brand.images;
    return pool[hashString(targetNorm) % pool.length];
}

/**
 * Returns the full list of supported brands.
 * @returns {Array} array of brand definition objects
 */
export function getBrands() {
    return BRANDS;
}

/**
 * Finds the brand that matches a product name by checking each brand's keywords.
 * Returns the DEFAULT_BRAND if no keyword matches.
 * @param {string} productName - product name string (e.g. "Apple MacBook Pro 14")
 * @returns {Object} matching brand definition object
 */
export function getBrandForProduct(productName) {
    if (!productName) return DEFAULT_BRAND;
    const lower = productName.toLowerCase();
    return BRANDS.find((b) => b.keywords.some((k) => lower.includes(k))) || DEFAULT_BRAND;
}

/**
 * Returns an array of full CDN image URLs for a product's photo gallery,
 * built entirely from that product's own brand's static resource — the
 * lead image (index 0) is the photo that actually matches this product's
 * name, and up to 4 more are pulled randomly (but deterministically, per
 * product) from the rest of the same brand's resource. Images are served
 * from static resources to comply with Experience Cloud CSP.
 * @param {string} productName - product name string used to identify the brand
 * @returns {string[]} array of absolute image URLs (up to 5)
 */
export function getProductImages(productName) {
    const brand = getBrandForProduct(productName);
    if (!brand.images || brand.images.length === 0) {
        return [];
    }

    const lead = pickLeadFilename(productName, brand);
    const targetNorm = normalize(productName);

    // The gallery's extra shots must be either THIS product's own "other N"
    // photos, or true brand-wide filler with no specific model identity —
    // never another model's dedicated photo (e.g. a Dell XPS 15 gallery
    // must never include one of the XPS 13 Plus's own "other" shots).
    const owned = [];
    const generic = [];
    for (const f of brand.images) {
        if (f === lead) continue;
        const { coreNorm, isGeneric } = classifyImage(f, brand);
        if (isGeneric) {
            generic.push(f);
        } else if (coreMatchesProduct(coreNorm, targetNorm)) {
            owned.push(f);
        }
        // else: belongs to a different specific model — excluded entirely.
    }
    const rest = [...owned, ...generic];

    const offset = rest.length ? hashString(targetNorm) % rest.length : 0;
    const rotated = [...rest.slice(offset), ...rest.slice(0, offset)];
    const extraCount = Math.min(4, rotated.length);

    return [lead, ...rotated.slice(0, extraCount)].map((f) => buildUrl(brand.resourceUrl, f));
}
