import getProducts from '@salesforce/apex/ProductCatalogController.getProducts';
import { getCategoryForProduct } from 'c/categoryService';

// Fetches the real Product2/PricebookEntry-backed catalog once per page session
// and caches it; every consuming component works from this shared list.
let productsPromise = null;

export function loadProducts() {
    if (!productsPromise) {
        productsPromise = getProducts()
            .then((products) =>
                // ProductCatalogController.getProducts() always returns
                // category="Laptops" for every product (there's no real
                // category field on Product2) — overridden here with a real
                // inferred category so every existing category-aware
                // consumer (catalog filter, related products, extractCategories)
                // works correctly with no further changes.
                products.map((p) => ({ ...p, category: getCategoryForProduct(p.productName) }))
            )
            .catch((err) => {
                productsPromise = null; // reset so next call retries
                return Promise.reject(err);
            });
    }
    return productsPromise;
}

// Pure helpers operate on an already-loaded array — no fetching here,
// so components stay in control of loading/error state.
export function findById(products, productId) {
    return products.find((p) => p.productId === productId) || null;
}

export function filterByCategory(products, category) {
    return products.filter((p) => p.category === category);
}

export function filterBySearch(products, term) {
    const q = (term || '').trim().toLowerCase();
    if (!q) {
        return [];
    }
    return products.filter(
        (p) =>
            p.productName.toLowerCase().includes(q) ||
            (p.category && p.category.toLowerCase().includes(q))
    );
}

export function extractCategories(products) {
    const counts = new Map();
    products.forEach((p) => {
        const category = p.category || 'Other';
        counts.set(category, (counts.get(category) || 0) + 1);
    });
    return Array.from(counts.entries()).map(([name, itemCount]) => ({ name, itemCount }));
}
