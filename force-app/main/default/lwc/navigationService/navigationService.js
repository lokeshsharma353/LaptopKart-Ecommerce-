/**
 * navigationService — centralised LWR page reference factory.
 * All page API names are defined here so a single change updates every component.
 * Names must match the API Name configured in Experience Builder exactly
 * (auto-generated as "Label_With_Underscores__c", except the system Home page).
 */
const PAGES = {
    home:              'Home',
    about:             'About__c',
    shop:              'Product_Catalog__c',
    product:           'Product_Detail__c',
    cart:              'Shopping_Cart__c',
    checkout:          'Checkout__c',
    payment:           'Payment__c',
    orderConfirmation: 'Order_Confirmation__c',
    account:           'My_Account__c',
    orderHistory:      'Order_History__c',
    orderTracking:     'Order_Tracking__c',
    contact:           'Contact_Us__c',
    signUp:            'Sign_Up_c'
};

/**
 * Builds a comm__namedPage reference object for LWR Experience Cloud navigation.
 * @param {string} name - Experience Builder page API name
 * @param {Object} [state] - optional state object passed as URL query parameters
 * @returns {Object} LWR page reference object
 */
function namedPageRef(name, state) {
    const ref = { type: 'comm__namedPage', attributes: { name } };
    if (state) { ref.state = state; }
    return ref;
}

/** @returns {Object} page reference for the Home page */
export function getHomeRef() { return namedPageRef(PAGES.home); }

/** @returns {Object} page reference for the About Us page */
export function getAboutRef() { return namedPageRef(PAGES.about); }

/**
 * @param {string} [searchOrCategory] - optional search term or brand name to pre-filter the catalog
 * @returns {Object} page reference for the Product Catalog page
 */
export function getShopRef(searchOrCategory) {
    return namedPageRef(PAGES.shop, searchOrCategory ? { category: searchOrCategory } : undefined);
}

/**
 * Navigates to the Product Catalog pre-filtered by a real shopping category
 * (Gaming, Business, Ultrabook & Slim, 2-in-1 & Convertible, Chromebook — see
 * categoryService). Uses a distinct state key ("cat") from getShopRef's
 * "category" key, which despite its name is actually brand search text —
 * keeping them separate avoids a category card and a brand card fighting
 * over the same navigation state key.
 * @param {string} categoryName - exact category name from categoryService.getCategories()
 * @returns {Object} page reference for the Product Catalog page
 */
export function getShopRefByCategory(categoryName) {
    return namedPageRef(PAGES.shop, { cat: categoryName });
}

/**
 * @param {string} productId - Salesforce Product2 Id
 * @returns {Object} page reference for the Product Detail page
 */
export function getProductRef(productId) {
    return namedPageRef(PAGES.product, { productId });
}

/** @returns {Object} page reference for the Shopping Cart page */
export function getCartRef() { return namedPageRef(PAGES.cart); }

/** @returns {Object} page reference for the Checkout page */
export function getCheckoutRef() { return namedPageRef(PAGES.checkout); }

/**
 * @param {string} [cartPayload] - optional JSON-encoded cart+draft carried in the URL
 *   itself (see checkoutService.encodeHandoff) so the Payment page can load the cart
 *   even if localStorage doesn't carry over from the Checkout page.
 * @returns {Object} page reference for the Payment page
 */
export function getPaymentRef(cartPayload) {
    return namedPageRef(PAGES.payment, cartPayload ? { d: cartPayload } : undefined);
}

/**
 * @param {string} [orderId] - Salesforce Order Id to display on the confirmation page
 * @returns {Object} page reference for the Order Confirmation page
 */
export function getOrderConfirmationRef(orderId) {
    return namedPageRef(PAGES.orderConfirmation, orderId ? { orderId } : undefined);
}

/** @returns {Object} page reference for the My Account page */
export function getAccountRef() { return namedPageRef(PAGES.account); }

/** @returns {Object} page reference for the Order History page */
export function getOrderHistoryRef() { return namedPageRef(PAGES.orderHistory); }

/**
 * @param {string} [orderId] - Salesforce Order Id to pre-load on the tracking page
 * @returns {Object} page reference for the Order Tracking page
 */
export function getOrderTrackingRef(orderId) {
    return namedPageRef(PAGES.orderTracking, orderId ? { orderId } : undefined);
}

/** @returns {Object} page reference for the Contact Us page */
export function getContactRef() { return namedPageRef(PAGES.contact); }

/** @returns {Object} page reference for the Sign Up page */
export function getSignUpRef() { return namedPageRef(PAGES.signUp); }

/**
 * Returns a reference to Salesforce's built-in secure Login page for this site.
 * Password handling stays entirely inside Salesforce's own login flow.
 * @returns {Object} comm__loginPage reference
 */
export function getLoginRef() {
    return { type: 'comm__loginPage', attributes: { actionName: 'login' } };
}