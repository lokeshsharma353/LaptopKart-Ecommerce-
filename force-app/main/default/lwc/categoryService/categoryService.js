/**
 * categoryService — infers a real shopping category (Gaming, Business,
 * Ultrabook, 2-in-1 & Convertible, Chromebook, Everyday) from a product's
 * name, since ProductCatalogController.getProducts() only ever returns the
 * single hardcoded category "Laptops" — there's no real category field on
 * Product2 to read from. Same keyword-matching pattern as brandService.
 * Order matters: earlier entries win when a name could match more than one
 * (e.g. "HP Spectre x360" matches 2-in-1's "x360" before it could ever be
 * considered a plain Ultrabook).
 */
const CATEGORIES = [
    {
        id: 'cat-2in1', name: '2-in-1 & Convertible', icon: '🔄',
        keywords: ['yoga', 'x360', 'flip', 'spin', 'galaxy book flex']
    },
    {
        id: 'cat-gaming', name: 'Gaming', icon: '🎮',
        keywords: ['alienware', 'omen', 'legion', 'predator', 'nitro', 'rog', 'tuf gaming', 'helios', 'triton', 'ideapad gaming', 'victus']
    },
    {
        id: 'cat-business', name: 'Business', icon: '💼',
        keywords: ['elitebook', 'probook', 'latitude', 'thinkpad', 'expertbook', 'travelmate', 'zbook']
    },
    {
        id: 'cat-chromebook', name: 'Chromebook', icon: '🌐',
        keywords: ['chromebook']
    },
    {
        id: 'cat-ultrabook', name: 'Ultrabook & Slim', icon: '⚡',
        keywords: ['xps', 'zenbook', 'swift', 'macbook air', 'macbook pro', 'vivobook']
    }
];

/** Fallback category for names that don't match any keyword above. */
const DEFAULT_CATEGORY = { id: 'cat-everyday', name: 'Everyday', icon: '💻' };

/**
 * Returns the category list for UI display (Home page grid, header dropdown) —
 * the "Everyday" fallback is intentionally excluded from this list since it's
 * a catch-all, not a distinct shopping intent someone would browse for.
 * @returns {Array} array of {id, name, icon}
 */
export function getCategories() {
    return CATEGORIES.map((c) => ({ id: c.id, name: c.name, icon: c.icon }));
}

/**
 * Determines the category name for a single product name.
 * @param {string} productName - e.g. "HP Spectre x360"
 * @returns {string} category name, or "Everyday" if nothing matches
 */
export function getCategoryForProduct(productName) {
    if (!productName) {
        return DEFAULT_CATEGORY.name;
    }
    const lower = productName.toLowerCase();
    const match = CATEGORIES.find((c) => c.keywords.some((k) => lower.includes(k)));
    return match ? match.name : DEFAULT_CATEGORY.name;
}
