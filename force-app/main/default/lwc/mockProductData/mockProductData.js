// Frontend-only mock catalog. Fields match the conceptual product model:
// productId, productName, image, price, originalPrice, rating, reviewCount,
// stock, category, description, specifications. No Salesforce fields implied.
export const PRODUCTS = [
    { productId: 'p1', productName: 'AeroSound Wireless Headphones', image: null, price: 4999, originalPrice: 6499, rating: 4.5, reviewCount: 312, stock: 24, category: 'Audio', description: 'Over-ear wireless headphones with active noise cancellation and 30-hour battery life.', specifications: { 'Battery Life': '30 hours', 'Connectivity': 'Bluetooth 5.2', 'Weight': '250g' } },
    { productId: 'p2', productName: 'PulseFit Smartwatch Series 3', image: null, price: 7999, originalPrice: 9999, rating: 4.2, reviewCount: 198, stock: 15, category: 'Wearables', description: 'Fitness smartwatch with heart-rate monitoring, GPS, and 7-day battery.', specifications: { 'Display': '1.4" AMOLED', 'Water Resistance': '5 ATM', 'Battery Life': '7 days' } },
    { productId: 'p3', productName: 'NovaBook Pro 14 Laptop', image: null, price: 68999, originalPrice: 74999, rating: 4.7, reviewCount: 89, stock: 8, category: 'Laptops', description: '14-inch ultrabook with 16GB RAM, 512GB SSD, and all-day battery life.', specifications: { 'Processor': 'Octa-core 3.2GHz', 'RAM': '16GB', 'Storage': '512GB SSD' } },
    { productId: 'p4', productName: 'ClickMax Wireless Mouse', image: null, price: 799, originalPrice: 999, rating: 4.0, reviewCount: 542, stock: 120, category: 'Accessories', description: 'Ergonomic wireless mouse with silent clicks and 18-month battery life.', specifications: { 'Connectivity': '2.4GHz + Bluetooth', 'DPI': '1600', 'Battery Life': '18 months' } },
    { productId: 'p5', productName: 'VividView 27" 4K Monitor', image: null, price: 24999, originalPrice: 29999, rating: 4.6, reviewCount: 156, stock: 0, category: 'Monitors', description: '27-inch 4K UHD monitor with HDR support and 99% sRGB coverage.', specifications: { 'Resolution': '3840x2160', 'Refresh Rate': '60Hz', 'Panel': 'IPS' } },
    { productId: 'p6', productName: 'SnapCase Phone Case (Universal)', image: null, price: 399, originalPrice: 599, rating: 3.8, reviewCount: 921, stock: 300, category: 'Accessories', description: 'Shockproof protective case with raised edges for screen protection.', specifications: { 'Material': 'TPU + Polycarbonate', 'Compatibility': 'Universal fit' } },
    { productId: 'p7', productName: 'InfinityCharge 20000mAh Power Bank', image: null, price: 1899, originalPrice: 2499, rating: 4.4, reviewCount: 267, stock: 45, category: 'Accessories', description: 'High-capacity power bank with fast charging and dual USB output.', specifications: { 'Capacity': '20000mAh', 'Output': '18W Fast Charge', 'Ports': '2x USB-A, 1x USB-C' } },
    { productId: 'p8', productName: 'Quantum X Gaming Laptop', image: null, price: 124999, originalPrice: 139999, rating: 4.8, reviewCount: 64, stock: 5, category: 'Laptops', description: '15.6-inch gaming laptop with dedicated graphics and 144Hz display.', specifications: { 'Processor': 'Octa-core 3.8GHz', 'RAM': '32GB', 'GPU': 'Dedicated 8GB' } },
    { productId: 'p9', productName: 'EchoBuds Pro Earbuds', image: null, price: 3499, originalPrice: 4499, rating: 4.3, reviewCount: 410, stock: 60, category: 'Audio', description: 'True wireless earbuds with adaptive noise cancellation.', specifications: { 'Battery Life': '6h (24h with case)', 'Connectivity': 'Bluetooth 5.3' } },
    { productId: 'p10', productName: 'FrameTab 10.5" Tablet', image: null, price: 18999, originalPrice: 21999, rating: 4.1, reviewCount: 133, stock: 22, category: 'Tablets', description: '10.5-inch tablet with stylus support and all-day battery.', specifications: { 'Display': '10.5" LCD', 'Storage': '128GB', 'Battery Life': '10 hours' } },
    { productId: 'p11', productName: 'KeyForge Mechanical Keyboard', image: null, price: 3999, originalPrice: 4999, rating: 4.6, reviewCount: 288, stock: 34, category: 'Accessories', description: 'RGB backlit mechanical keyboard with hot-swappable switches.', specifications: { 'Switch Type': 'Mechanical Blue', 'Backlight': 'RGB', 'Connectivity': 'USB-C' } },
    { productId: 'p12', productName: 'StreamCam HD Webcam', image: null, price: 2299, originalPrice: 2999, rating: 4.0, reviewCount: 176, stock: 0, category: 'Accessories', description: '1080p webcam with auto-focus and built-in noise-cancelling mic.', specifications: { 'Resolution': '1080p @ 30fps', 'Field of View': '90°' } }
];

export function getAllProducts() {
    return PRODUCTS;
}

export function getProductById(productId) {
    return PRODUCTS.find((p) => p.productId === productId) || null;
}

export function getProductsByCategory(category) {
    return PRODUCTS.filter((p) => p.category === category);
}

export function searchProducts(term) {
    const q = (term || '').trim().toLowerCase();
    if (!q) {
        return [];
    }
    return PRODUCTS.filter(
        (p) =>
            p.productName.toLowerCase().includes(q) ||
            p.category.toLowerCase().includes(q)
    );
}

export function getCategories() {
    const map = new Map();
    PRODUCTS.forEach((p) => {
        map.set(p.category, (map.get(p.category) || 0) + 1);
    });
    return Array.from(map.entries()).map(([name, itemCount]) => ({ name, itemCount }));
}
