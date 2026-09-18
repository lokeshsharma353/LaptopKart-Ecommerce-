# LaptopKart — Project Details

A practical map of this project: every Lightning Web Component, every Apex class, and — most importantly — **"if I want to change X, which file do I edit?"**

This file is a plain-text reference (safe to open in any editor, GitHub, or print). For a fully interactive click-to-expand version with diagrams, see the architecture guide saved earlier to your Desktop (`LaptopKart-Architecture-Guide.html`).

---

## 1. "If you want to change..." — quick lookup

| I want to change... | Edit this |
|---|---|
| Home page hero background images / their order | `force-app/main/default/lwc/techBasketHome/techBasketHome.js` — the `ALL_HERO_FILES` array (order) and `PRIORITY_COUNT` (how many always lead) |
| Home page hero look/animation (Ken Burns zoom, overlay darkness, fonts) | `force-app/main/default/lwc/techBasketHome/techBasketHome.css` |
| Which actual image files exist to use as hero backgrounds | Static resource `tbimages` (zip) — `force-app/main/default/staticresources/tbimages.zip` / `tbimages/` |
| Site logo | Static resource `AppLogo` — referenced from `techBasketHeader.js`, `techBasketFooter.js`, `techBasketMyAccount.js`, `techBasketAboutUs.js` |
| Header nav links, search, cart badge, mobile menu | `force-app/main/default/lwc/techBasketHeader/` |
| Footer links, social icons, copyright | `force-app/main/default/lwc/techBasketFooter/` |
| Colors / dark theme tokens for a given page | Each component has its **own** `.css` file with its own `:host { --dark, --cyan, --purple, --gold, ... }` variables — there is no single shared theme file yet, so a color change usually needs to be repeated per component's CSS |
| Product catalog (what's for sale, price, stock) | **Not in code** — comes live from Salesforce: `Product2` + `PricebookEntry` records, read by `ProductCatalogController.cls` (`getProducts()`), cached by `force-app/main/default/lwc/productDataService/productDataService.js` |
| Old unused mock/demo product list | `force-app/main/default/lwc/mockProductData/mockProductData.js` — **not wired into the real site**, kept as leftover/reference only |
| Product category labels (Gaming, Business, Ultrabook, etc.) | `force-app/main/default/lwc/categoryService/categoryService.js` (keyword-matches product names — Apex only ever returns "Laptops") |
| Which brand a product belongs to / which photos show for it | `force-app/main/default/lwc/brandService/brandService.js` |
| Brand product photo files themselves | Static resources `tbimagesApple`, `tbimagesDell`, `tbimagesHp`, `tbimagesLenovo`, `tbimagesAsus`, `tbimagesAcer`, `tbimagesSamsung` |
| Shopping cart logic (add/remove/update qty, persistence) | `force-app/main/default/lwc/cartService/cartService.js` |
| Cart totals / tax rate math | `force-app/main/default/lwc/cartCalculations/cartCalculations.js` (flat 5% tax placeholder) |
| Checkout steps and their order | `force-app/main/default/lwc/techBasketCheckout/techBasketCheckout.js` (orchestrator) |
| Shipping address form + its validation | `force-app/main/default/lwc/techBasketShippingForm/` |
| Billing address form + its validation | `force-app/main/default/lwc/techBasketBillingForm/` |
| Shipping method options & their price/ETA (Standard/Express/Overnight) | `force-app/main/default/lwc/techBasketShippingMethod/techBasketShippingMethod.js` — the `METHODS` array |
| Field validation rules (10-digit phone, email, PIN code, name format) — **the shared rules used site-wide** | `force-app/main/default/lwc/formValidators/formValidators.js` |
| Payment method choices (Online / Cash on Delivery) | `force-app/main/default/lwc/techBasketPaymentMethod/` |
| Payment page (QR code, UTR entry, Place Order) | `force-app/main/default/lwc/techBasketPayment/` |
| What actually happens in Salesforce when an order is placed | `CheckoutController.cls` → `submitOrder()` (see Section 5, "the automation chain") |
| Order confirmation page content | `force-app/main/default/lwc/techBasketOrderConfirmation/` |
| PDF invoice content/layout | `OrderInvoiceController.cls` + its Visualforce page `OrderInvoice` |
| Order History (My Account) list | `force-app/main/default/lwc/techBasketOrderHistory/` |
| Order Tracking lookup page | `force-app/main/default/lwc/techBasketOrderTracking/` + `force-app/main/default/lwc/techBasketOrderProgress/` (the step tracker) |
| Login / Sign In / Sign Up forms on My Account | `force-app/main/default/lwc/techBasketMyAccount/` (LaptopKart's own custom system — see Section 5) |
| The separate "Create Your LaptopKart Account" page | `force-app/main/default/lwc/techBasketSignUp/` — this is a **different, real Salesforce user** system, not the same as My Account login |
| Forgot Password behavior | `LoginCredentialsController.requestPasswordReset()` — creates a Task for an admin to personally follow up; there's no automatic email reset link |
| Contact Us form fields / admin notification email | `force-app/main/default/lwc/techBasketContactUs/` + `ContactController.cls` |
| The "Welcome to LaptopKart" popup that captures a lead | `force-app/main/default/lwc/techBasketWelcomePopup/` + `WelcomeLeadController.cls` |
| Wishlist behavior | `force-app/main/default/lwc/wishlistService/wishlistService.js` |
| Toast/notification popups (success, error, info messages) | `force-app/main/default/lwc/toastService/toastService.js` (fires them) + `force-app/main/default/lwc/techBasketToast/` (renders them) |
| Saved addresses (My Account address book) | `force-app/main/default/lwc/addressService/addressService.js` |
| Page navigation targets / URLs | `force-app/main/default/lwc/navigationService/navigationService.js` — every page link is defined here in one place |
| Newsletter signup box (Home page footer section) | `techBasketHome.js` — `handleSubscribe`/`handleEmailInput` |
| Internal admin Order/Payment dashboard (Lightning Experience, not the public site) | `force-app/main/default/lwc/orderPaymentDashboard/` + `OrderPaymentController.cls` |
| Nightly safety-net that re-checks unpaid orders | `OrderPaymentReconciliationScheduler.cls` (the cron job) → `OrderPaymentReconciliationBatch.cls` (the actual work) |
| About Us page content | `force-app/main/default/lwc/techBasketAboutUs/` |

---

## 2. The four layers, top to bottom

```
Browser (shopper)
    │
    ▼
LWC pages (techBasket*)  ──uses──▶  Shared service modules (cartService, authService, etc. — all localStorage/pure-JS, no Apex)
    │
    │ @salesforce/apex calls
    ▼
Apex Controllers (CheckoutController, ProductCatalogController, LoginCredentialsController, ContactController, ...)
    │
    │ triggers fire automatically on DML
    ▼
Trigger Handlers → Service classes (OrderService, OrderTrackingService, PaymentService)
    │
    ▼
Salesforce Database (Lead, Account, Contact, Opportunity, Order, OrderItem, Payment__c, Order_Tracking__c, Login_Credentials__c, Contact_Us__c, Product2, PricebookEntry)
```

---

## 3. All LWC components (42)

### A. Full pages (what a shopper navigates to)

| Component | What it does |
|---|---|
| `techBasketHome` | Homepage — hero slideshow, brand selector, featured "Top Picks", Why LaptopKart, testimonials, newsletter |
| `techBasketAboutUs` | About Us — company story, stats, values, "Meet the Developers" |
| `techBasketProductCatalog` | Shop/Browse page — filters, sort, grid/list toggle, pagination |
| `techBasketProductDetail` | Single product page — gallery, tabs, related products |
| `techBasketCart` | Shopping Cart page |
| `techBasketCheckout` | Multi-step checkout: Shipping → Billing → Shipping Method, then hands off to Payment |
| `techBasketPayment` | Standalone Payment page — method choice, QR/UTR for Online, Place Order |
| `techBasketOrderConfirmation` | Post-checkout confirmation — summary, tracking, invoice download |
| `techBasketOrderHistory` | This shopper's past orders (My Account → Order History, and its own page) |
| `techBasketOrderTracking` | Order tracking lookup, by navigation or manual order-number search |
| `techBasketMyAccount` | Log In / Sign Up / Forgot Password, and the logged-in dashboard (Profile, Orders, Addresses, Wishlist, Settings) |
| `techBasketSignUp` | Separate "Create Account" page — a **real** Salesforce Experience Cloud user, different system from My Account |
| `techBasketContactUs` | Contact Us — message form, support info, FAQs |
| `orderPaymentDashboard` | Internal-only (Lightning Experience Order record page), not on the public site — shows order + payment history for admins |

### B. Site-wide layout

| Component | What it does |
|---|---|
| `techBasketHeader` | Logo, nav with category dropdown, search, cart badge, mobile drawer, login/logout links |
| `techBasketFooter` | Logo, quick links, customer-service links, social icons |
| `techBasketToast` | Renders toast notifications fired from anywhere via `toastService` |
| `techBasketWelcomePopup` | One-time "welcome" lead-capture modal shown shortly after Home loads |

### C. Reusable building blocks (children of the pages above)

| Component | Used inside |
|---|---|
| `techBasketProductCard` | Product grids (Catalog, Home "Top Picks", related products) |
| `techBasketCartItem` | Cart page, one row per item |
| `techBasketCategoryCard` | Home page category grid |
| `techBasketOrderProgress` | Order Confirmation and Order Tracking (step tracker) |
| `techBasketOrderSummary` | Cart page and Checkout sidebar (totals panel) |
| `techBasketPaymentMethod` | Payment page (Online / COD picker) |
| `techBasketShippingMethod` | Checkout (Standard/Express/Overnight picker) |
| `techBasketShippingForm` | Checkout step 1 |
| `techBasketBillingForm` | Checkout step 2 (only shown if billing ≠ shipping) |
| `techBasketQuantitySelector` | Cart items and Product Detail page |
| `techBasketRating` | Product cards and Product Detail (star display) |
| `techBasketSearch` | Inside the header (autocomplete search box) |
| `techBasketModal` | Generic confirm/cancel dialog (e.g. "Clear Cart?") |

### D. Service / utility modules (pure JS, no visible UI)

| Module | What it does |
|---|---|
| `cartService` | localStorage-backed cart CRUD + live subscription |
| `cartCalculations` | Subtotal / tax / total math |
| `wishlistService` | localStorage-backed wishlist |
| `addressService` | localStorage-backed saved address book |
| `authService` | Client-side "logged in" session for the custom login system |
| `checkoutService` | Bridges the Checkout and Payment pages (draft handoff) |
| `orderService` | Tracks which Order Ids this browser placed; fetches order details/history |
| `productDataService` | Loads/caches the real Apex product catalog, adds real categories |
| `categoryService` | Infers a shopping category from a product name |
| `brandService` | Matches a product to its brand and photo gallery |
| `navigationService` | Central place defining every page's navigation target |
| `toastService` | Pub-sub bus for toast notifications |
| `accountSettingsService` | localStorage-backed notification preferences |
| `formValidators` | Shared phone/email/name/PIN-code validation rules (see Section 1) |
| `mockProductData` | Old static demo catalog — **not used by the live site** |
| `firstComponents` | Leftover first-ever tutorial component (`name`/`company` only) — **not part of the real app** |

---

## 4. All Apex classes (44)

### A. LaptopKart's own live backend

| Class | What it does |
|---|---|
| `CheckoutController` | The big one — `submitOrder()` creates Lead → Account → Contact → Opportunity → Order → OrderItems → Payment in one transaction, plus `getOrders`, `getOrdersByEmail`, `cancelOrder` |
| `LoginCredentialsController` | LaptopKart's **own** custom login/signup (`Login_Credentials__c` object, plain-text password by design) — `signUp`, `logIn`, `requestPasswordReset` |
| `RegistrationController` | Creates a **real** Salesforce Experience Cloud user (`registerUser`) — used only by the separate Sign Up page, not My Account |
| `ContactController` | Saves a `Contact_Us__c` ticket + emails the admin (`submitMessage`) |
| `ProductCatalogController` | Returns the live product catalog (`getProducts`) |
| `WelcomeLeadController` | Creates a marketing Lead from the welcome popup (`submitWelcomeLead`) |
| `OrderPaymentController` | Read-only order/payment lookups for the internal admin dashboard |
| `OrderInvoiceController` | Builds the PDF invoice Visualforce page's data |
| `AccountTriggerHandler` | Only `updatePhone` is live — logs old/new phone to Description |
| `OpportunityTriggerHandler` | Detects Closed Won → calls `OrderService.createOrders` |
| `OrderService` | Creates the Order + copies OpportunityLineItems into OrderItems |
| `OrderTriggerHandler` | Detects Order status change → calls `OrderTrackingService` |
| `OrderTrackingService` | Creates/updates `Order_Tracking__c` when an Order activates or is cancelled |
| `PaymentTriggerHandler` | Validates payments, then calls `PaymentService` |
| `PaymentService` | Rejects overpayment, recalculates Order paid totals, sends confirmation emails |
| `OrderPaymentReconciliationScheduler` | Nightly cron job |
| `OrderPaymentReconciliationBatch` | The actual nightly re-check of unpaid Orders |

### B. Salesforce Experience Cloud boilerplate (auto-generated — NOT LaptopKart's real login)

These came with the Experience Cloud site template and back the *native* Salesforce login/registration pages, which this storefront doesn't actually use (it uses `LoginCredentialsController` + `authService` instead):

`ChangePasswordController`, `CommunitiesLandingController`, `CommunitiesLoginController`, `CommunitiesSelfRegConfirmController`, `CommunitiesSelfRegController`, `ForgotPasswordController`, `MicrobatchSelfRegController`, `MyProfilePageController`, `SiteLoginController`, `SiteRegisterController`

### C. Dead / legacy code (kept for reference, not live)

| Class | Why it's dead |
|---|---|
| `ContactSharing` | Would throw "field not writeable" if run — org's Contact sharing isn't Private |
| `contactSharingClass` | Duplicate of `ContactSharing`, same problem |
| `OpprtunityClosedWonHandler` | References Account fields that don't exist in this org |
| `Objs` | Scratch/practice class, not referenced anywhere |

### D. Test classes (16)

| Test class | Tests |
|---|---|
| `CheckoutControllerTest` | Full order pipeline (Order/OrderItem/Order_Tracking__c/Payment__c) for checkout |
| `LoginCredentialsControllerTest` | Sign-up/login round trip, duplicate-email blocking, wrong-password rejection |
| `ContactControllerTest` | Contact Us submission as Guest User |
| `OrderInvoiceControllerTest` | Invoice data visibility, exercised via `CheckoutController.submitOrder` |
| `PaymentServiceEmailTest` | Payment confirmation email fires correctly |
| `EmailContentTest` | Order confirmation email actually contains real order/product/shipping data |
| `ChangePasswordControllerTest`, `CommunitiesLandingControllerTest`, `CommunitiesLoginControllerTest`, `CommunitiesSelfRegConfirmControllerTest`, `CommunitiesSelfRegControllerTest`, `ForgotPasswordControllerTest`, `MicrobatchSelfRegControllerTest`, `MyProfilePageControllerTest`, `SiteLoginControllerTest`, `SiteRegisterControllerTest` | Standard stub tests for the Salesforce boilerplate classes above (exist only so those classes meet code-coverage requirements) |

---

## 5. The order automation chain (what happens when someone checks out)

```
1. Shopper clicks "Place Order" (techBasketPayment)
2. CheckoutController.submitOrder()
   → creates Lead, converts to Account + Contact + Opportunity (Closed Won)
3. OpportunityTriggerHandler (trigger) → OrderService.createOrders()
   → creates the Order + copies line items
4. OrderTriggerHandler (trigger, fires on Order activation) → OrderTrackingService
   → creates Order_Tracking__c (status "Pending")
5. PaymentTriggerHandler (trigger, fires on Payment__c insert) → PaymentService
   → validates the payment, recalculates the Order's paid total
6. Customer gets an automatic "we received your order" email (payment still pending confirmation)
7. Admin manually marks the Payment__c "Successful" once they've verified it
8. PaymentService.sendPaymentConfirmationEmails fires → customer gets "Your order is Confirmed!" email
```

## 6. Key data objects

| Object | Purpose |
|---|---|
| `Login_Credentials__c` (custom) | LaptopKart's own login system — email, plain-text password, name, phone, and `Cart_Items__c` (a live mirror of that shopper's cart, auto-updated by `cartService.js` on every add/remove/quantity change and on login) |
| `Cart_Activity__c` (custom) | Permanent, append-only history of every cart change — one record per add/remove/clear action (Action, Product Name, Quantity, Price, timestamped by CreatedDate), linked to the shopper's `Login_Credentials__c` record. Shows under that record's Related list. Logged by `LoginCredentialsController.logCartActivity`, called from `cartService.js` alongside the snapshot sync. |
| `Contact_Us__c` (custom) | Every Contact Us form submission |
| `Order_Tracking__c` (custom) | Delivery status per Order |
| `Payment__c` (custom) | One row per payment attempt against an Order |
| `Lead` → `Account`/`Contact`/`Opportunity` (standard) | Created automatically by checkout |
| `Order` / `OrderItem` (standard) | The actual order and its line items |
| `Product2` / `PricebookEntry` (standard) | The real product catalog |

---

## 7. Known, deliberate design decisions

- **Passwords stored in plain text** on `Login_Credentials__c` — an explicit choice for this project, not an oversight.
- **No real per-shopper Salesforce login** for My Account — every storefront visitor is the Site Guest User; "logged in" is just a client-side session (`authService`) layered on top of `LoginCredentialsController`. The separate Sign Up page (`techBasketSignUp` + `RegistrationController`) is the one place that creates a **real** Salesforce user.
- **`WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE`** appears throughout the checkout trigger chain because a Guest User's sharing visibility into records it just created hasn't recalculated yet within the same transaction — documented in each class's header comment.
- **Payment confirmation is manual** — there's no payment gateway integration; an admin looks at the UTR/UPI transaction and flips `Payment_Status__c` to "Successful" by hand (a good candidate to formalize as a Salesforce Approval Process, if you ever want that).

---

*Generated from a full read-through of every Apex class and LWC component in this project. For the interactive version with diagrams and click-to-expand detail, see the architecture guide on your Desktop.*
