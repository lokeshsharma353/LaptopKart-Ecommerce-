import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getOrderConfirmationRef, getCheckoutRef } from 'c/navigationService';
import { getCart, clearCart } from 'c/cartService';
import { calculateTotals } from 'c/cartCalculations';
import { getDraft, saveDraft, clearDraft, decodeHandoff } from 'c/checkoutService';
import { rememberOrder, rememberEmail } from 'c/orderService';
import { getSession } from 'c/authService';
import { getProductImages } from 'c/brandService';
import { getAppliedCoupon, setAppliedCoupon } from 'c/couponService';
import submitOrder from '@salesforce/apex/CheckoutController.submitOrder';
import createRazorpayPaymentLink from '@salesforce/apex/CheckoutController.createRazorpayPaymentLink';
import previewOrderTotals from '@salesforce/apex/CheckoutController.previewOrderTotals';
import getAvailableCoupons from '@salesforce/apex/DiscountService.getAvailableCoupons';

/** Human-readable labels for each payment method id. */
const METHOD_LABELS = { online: 'Online Payment', cod: 'Cash on Delivery' };
/** Maps the LWC method id to the exact Payment_Method__c picklist value in Salesforce. */
const METHOD_TO_PICKLIST = { online: 'Online', cod: 'Cash' };
/** Bumped on every deploy so the browser console proves which build is actually running. */
const BUILD_TAG = 'payment-pricing-engine-2026-09-18-1';

/**
 * TechBasketPayment — the standalone Payment page.
 * Reads the checkout draft and cart saved by TechBasketCheckout, collects a
 * payment method, an optional coupon code and loyalty-point redemption, and
 * shows the REAL server-calculated order total (subtotal, coupon discount,
 * GST breakdown, loyalty discount, amount payable) via
 * CheckoutController.previewOrderTotals — never a frontend approximation,
 * since discounts/tax must always be validated and calculated server-side
 * (Feature Expansion Plan §1.7/§3.7).
 *  - Online: redirects the shopper to a Razorpay-hosted payment page (live
 *    UPI QR / card / netbanking — Razorpay auto-detects completion there),
 *    then Razorpay redirects back to this exact page with its own query
 *    params appended. This page detects those params on load and completes
 *    the order automatically. A full-page redirect rather than an embedded
 *    popup because this org's Lightning Web Security blocks the dynamic
 *    <script> injection Razorpay's Checkout.js widget needs — confirmed no
 *    CSP Trusted Site script-src option exists here even in Setup — so the
 *    gateway's own JS never needs to load inside this page at all.
 *  - Cash on Delivery: unchanged — submits immediately.
 */
export default class TechBasketPayment extends NavigationMixin(LightningElement) {
    /** Currently selected payment method id: 'online' | 'cod'. */
    @track methodId = 'online';
    /** True while the Apex call / gateway redirect / order submission is in progress. */
    @track isProcessing = false;
    /** Error message shown below the Place Order button on Apex failure. */
    @track paymentError = '';

    /** Coupon code the shopper has typed in (not yet necessarily applied). */
    @track couponInput = '';
    /** Coupon code that has actually been applied to the live server preview — null when none. */
    @track appliedCouponCode = null;
    /** Message from the last coupon validation (success or rejection reason). */
    @track couponMessage = '';
    /** True when the last coupon validation succeeded. */
    @track couponValid = false;
    /** Every currently usable coupon code (DiscountService.getAvailableCoupons), shown under the input so a shopper doesn't have to already know one. */
    @track availableCoupons = [];

    /** How many loyalty points the shopper wants to redeem. */
    @track pointsInput = '';
    /** Points actually applied to the live server preview. */
    @track appliedPoints = 0;
    /** Message from the last loyalty redemption preview. */
    @track loyaltyMessage = '';

    /** Server-calculated pricing breakdown (CheckoutController.previewOrderTotals) — the source of truth for everything shown and charged on this page. */
    @track pricing = null;
    /** True while a pricing preview call is in flight — disables re-triggering it. */
    @track isPricingLoading = false;

    /** Cart items snapshot — used to render totals and detect an empty cart on load. */
    items = [];
    /** Checkout draft (shipping/billing/shipping method) loaded from localStorage. */
    draft = null;

    _handoffApplied = false;
    _gatewayReturnHandled = false;

    /** Set once Razorpay's redirect hands back a payment id — passed through to submitOrder. */
    razorpayPaymentId = null;

    /**
     * Warms up the connection to Razorpay's domain the moment this page
     * loads — before the shopper has even picked a payment method — so the
     * DNS lookup / TLS handshake is already done by the time they click
     * Place Order and get redirected there. Shaves real latency off that
     * redirect; does not affect how fast Razorpay's own page renders once
     * you land on it, since that part is entirely outside this app.
     */
    connectedCallback() {
        const preconnect = document.createElement('link');
        preconnect.rel = 'preconnect';
        preconnect.href = 'https://checkout.razorpay.com';
        document.head.appendChild(preconnect);

        getAvailableCoupons()
            .then((coupons) => { this.availableCoupons = coupons || []; })
            .catch(() => { this.availableCoupons = []; });
    }

    /**
     * Loads the cart/draft the Checkout page handed off, then checks
     * whether this page load IS Razorpay redirecting the shopper back
     * (its own query params — razorpay_payment_id,
     * razorpay_payment_link_status — appended to this same page's URL).
     * Prefers the payload encoded in the page's own URL state (survives
     * even if localStorage doesn't carry over between Checkout and
     * Payment); falls back to localStorage for direct reloads/back-
     * navigation where no state is present. Redirects to Checkout only if
     * neither source has a draft.
     * @param {Object} pageRef - current LWR page reference
     */
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        // eslint-disable-next-line no-console
        console.log('[TechBasketPayment] build:', BUILD_TAG);
        if (this._handoffApplied) {
            return;
        }
        const handoff = decodeHandoff(pageRef && pageRef.state && pageRef.state.d);

        this.items = (handoff && handoff.cart && handoff.cart.length) ? handoff.cart : getCart();
        this.draft = (handoff && handoff.draft) ? handoff.draft : getDraft();

        if (!this.draft) {
            this[NavigationMixin.Navigate](getCheckoutRef());
            return;
        }

        // Re-save so localStorage stays in sync for the "Back" button / a
        // page refresh that drops the URL state.
        saveDraft(this.draft);
        this._handoffApplied = true;

        // Pick up a coupon already applied on the Cart page (couponService)
        // so the shopper doesn't have to retype it here — still re-validated
        // for real by refreshPricing() below, never trusted at face value.
        if (!this.appliedCouponCode) {
            const carriedOverCode = getAppliedCoupon();
            if (carriedOverCode) {
                this.appliedCouponCode = carriedOverCode;
                this.couponInput = carriedOverCode;
            }
        }

        this.refreshPricing();
        this.checkForGatewayReturn();
    }

    /**
     * Reads the real browser URL (not the LWR PageReference abstraction —
     * Razorpay appends plain query params to whatever callback_url it was
     * given, so the raw address bar is the reliable source) for Razorpay's
     * redirect-back params. If present, completes the order automatically
     * instead of showing the payment method picker again.
     */
    checkForGatewayReturn() {
        if (this._gatewayReturnHandled) {
            return;
        }
        const params = new URLSearchParams(window.location.search);
        const paymentId = params.get('razorpay_payment_id');
        const linkStatus = params.get('razorpay_payment_link_status');

        if (!paymentId) {
            return;
        }
        this._gatewayReturnHandled = true;

        if (linkStatus !== 'paid') {
            // Cancelled or failed on Razorpay's page — back to the method
            // picker so they can try again, nothing submitted.
            this.paymentError = 'Payment was not completed. Please try again.';
            return;
        }

        this.razorpayPaymentId = paymentId;
        this.methodId = 'online';
        this.isProcessing = true;
        this.completeOrder();
    }

    /**
     * Calls the real pricing engine (CheckoutController.previewOrderTotals)
     * with the current cart, shipping state, logged-in Account id, applied
     * coupon and requested points — the exact same inputs submitOrder will
     * use, so this preview and the final charge always agree (barring the
     * cart/coupon/balance genuinely changing in between, which submitOrder
     * re-verifies for real regardless). Called on load and whenever the
     * coupon or points selection changes.
     */
    refreshPricing() {
        const shipping = this.draft && this.draft.shippingAddress;
        if (!shipping || !this.items || this.items.length === 0) {
            return;
        }
        const session = getSession();
        this.isPricingLoading = true;

        const requestJson = JSON.stringify({
            items: this.items.map((item) => ({ productId: item.productId, quantity: item.quantity })),
            shippingState: shipping.state,
            accountId: session ? session.id : null,
            couponCode: this.appliedCouponCode,
            pointsToRedeem: this.appliedPoints || null,
            shippingMethodId: this.draft.shippingMethod ? this.draft.shippingMethod.id : null
        });

        previewOrderTotals({ requestJson })
            .then((result) => {
                this.pricing = result;
                this.isPricingLoading = false;
                if (this.appliedCouponCode) {
                    this.couponValid = result.couponValid;
                    this.couponMessage = result.couponMessage;
                    // The coupon turned out invalid on re-check (expired,
                    // limit reached since it was first applied) — drop it
                    // rather than silently keep charging without it.
                    if (!result.couponValid) {
                        this.appliedCouponCode = null;
                        setAppliedCoupon(null);
                    }
                }
                if (this.appliedPoints) {
                    this.loyaltyMessage = result.loyaltyMessage;
                    this.appliedPoints = result.pointsUsed || 0;
                }
            })
            .catch(() => {
                this.isPricingLoading = false;
                // Preview failing is never fatal — completeOrder always
                // re-derives the real charge server-side regardless. The
                // frontend estimate (this.totals) still renders in the
                // meantime.
            });
    }

    /**
     * Calculates the order totals including the selected shipping method cost.
     * Frontend fallback estimate shown only until the real server preview
     * (this.pricing) loads — that server figure is always what's actually
     * charged and verified.
     */
    get totals() {
        const shippingCost = this.draft && this.draft.shippingMethod ? this.draft.shippingMethod.price : 0;
        return calculateTotals(this.items, { shippingCost });
    }

    /** "N items in your order" label under the Review Your Order heading. */
    get itemsCountLabel() {
        const count = this.items.length;
        return `${count} item${count === 1 ? '' : 's'} in your order`;
    }

    /** Cart items with a resolved product thumbnail added, for the order review list. */
    get itemsWithImages() {
        return this.items.map((item) => ({
            ...item,
            imageUrl: getProductImages(item.productName)[0],
            lineTotal: (item.price * item.quantity).toFixed(2)
        }));
    }

    /** True once the cart items are known — guards the order review list before connectedCallback populates it. */
    get hasItems() {
        return this.items && this.items.length > 0;
    }

    /** True once the real server pricing breakdown has loaded. */
    get hasPricing() {
        return !!this.pricing;
    }

    /** The amount actually due — server figure once loaded, frontend estimate before that. */
    get amountDue() {
        return this.pricing ? this.pricing.amountPayable : this.totals.total;
    }

    get pricingSubtotal() {
        return this.pricing ? this.pricing.subtotal.toFixed(2) : this.totals.subtotal.toFixed(2);
    }

    get hasDiscount() {
        return this.pricing && this.pricing.discountAmount > 0;
    }

    get discountDisplay() {
        return this.pricing ? this.pricing.discountAmount.toFixed(2) : '0.00';
    }

    get taxableDisplay() {
        return this.pricing ? this.pricing.taxableAmount.toFixed(2) : '0.00';
    }

    /** True once the real server pricing has loaded and shipping actually costs something (Standard is free and stays hidden from the line-item list). */
    get hasShippingCost() {
        return !!this.pricing && this.pricing.shippingCost > 0;
    }

    get shippingCostDisplay() {
        return this.pricing ? this.pricing.shippingCost.toFixed(2) : '0.00';
    }

    get shippingMethodLabel() {
        return this.pricing ? this.pricing.shippingMethodLabel : '';
    }

    get isIntrastate() {
        return this.pricing && this.pricing.igstAmount === 0;
    }

    get cgstDisplay() {
        return this.pricing ? this.pricing.cgstAmount.toFixed(2) : '0.00';
    }

    get sgstDisplay() {
        return this.pricing ? this.pricing.sgstAmount.toFixed(2) : '0.00';
    }

    get igstDisplay() {
        return this.pricing ? this.pricing.igstAmount.toFixed(2) : '0.00';
    }

    get hasLoyaltyDiscount() {
        return this.pricing && this.pricing.loyaltyDiscount > 0;
    }

    get loyaltyDiscountDisplay() {
        return this.pricing ? this.pricing.loyaltyDiscount.toFixed(2) : '0.00';
    }

    get amountDueDisplay() {
        return this.amountDue.toFixed(2);
    }

    /** Loyalty point balance shown next to the redeem input — only meaningful once logged in and a preview has run. */
    get loyaltyBalance() {
        return this.pricing ? this.pricing.loyaltyBalance : 0;
    }

    get isLoggedIn() {
        return !!getSession();
    }

    /** CSS class for the coupon message — green when applied, red when rejected. */
    get couponMessageClass() {
        return this.couponValid ? 'tb-promo-message tb-promo-message-success' : 'tb-promo-message tb-promo-message-error';
    }

    /** Handles typing in the coupon code input. */
    handleCouponInput(event) {
        this.couponInput = event.target.value;
    }

    /** Validates and applies the typed coupon code via the real server preview. */
    handleApplyCoupon() {
        if (!this.couponInput || !this.couponInput.trim()) {
            return;
        }
        this.appliedCouponCode = this.couponInput.trim().toUpperCase();
        setAppliedCoupon(this.appliedCouponCode);
        this.refreshPricing();
    }

    /** True once at least one available coupon has been loaded. */
    get hasAvailableCoupons() { return this.availableCoupons.length > 0; }

    /** True while the available-coupons list is expanded (toggled via the "View Coupons" button — collapsed by default so the offers card starts compact). */
    @track showAvailableCoupons = false;

    /** The "View Coupons" toggle only appears once there's something to show and no coupon is already applied. */
    get showViewCouponsButton() { return this.hasAvailableCoupons && !this.appliedCouponCode; }

    /** Label flips between "View Coupons" and "Hide Coupons" depending on toggle state. */
    get viewCouponsLabel() { return this.showAvailableCoupons ? 'Hide Coupons' : 'View Coupons'; }

    /** Expands/collapses the available-coupons list. */
    handleToggleAvailableCoupons() {
        this.showAvailableCoupons = !this.showAvailableCoupons;
    }

    /** Picking a suggested coupon fills the input and applies it immediately — same validated path as typing it in and pressing Apply. */
    handleSelectAvailableCoupon(event) {
        const code = event.currentTarget.dataset.code;
        this.couponInput = code;
        this.appliedCouponCode = code;
        setAppliedCoupon(code);
        this.showAvailableCoupons = false;
        this.refreshPricing();
    }

    /** Removes the applied coupon. */
    handleRemoveCoupon() {
        this.appliedCouponCode = null;
        this.couponInput = '';
        this.couponMessage = '';
        this.couponValid = false;
        this.showAvailableCoupons = false;
        setAppliedCoupon(null);
        this.refreshPricing();
    }

    /** Handles typing in the loyalty points input. */
    handlePointsInput(event) {
        this.pointsInput = event.target.value;
    }

    /** Applies the requested point redemption via the real server preview, which caps it against the true balance/limit. */
    handleApplyPoints() {
        const requested = parseInt(this.pointsInput, 10);
        if (!requested || requested <= 0) {
            return;
        }
        this.appliedPoints = requested;
        this.refreshPricing();
    }

    /** Removes the applied loyalty point redemption. */
    handleRemovePoints() {
        this.appliedPoints = 0;
        this.pointsInput = '';
        this.loyaltyMessage = '';
        this.refreshPricing();
    }

    /**
     * The name attached to this order — the logged-in shopper's own account
     * name (authService session), NOT the shipping form's free-text full
     * name field. Checkout requires being logged in before reaching this
     * page, so a session is always expected here; the shipping form's name
     * is a delivery-recipient field (could be a gift, a different person at
     * the address) and was never meant to double as the customer's identity
     * — using it there was what let CheckoutController's Account-name sync
     * drift to whatever was last typed rather than who actually placed the
     * order. Falls back to the shipping name only if no session is somehow
     * present.
     */
    get customerName() {
        const session = getSession();
        if (session && session.name) {
            return session.name;
        }
        return this.draft && this.draft.shippingAddress ? this.draft.shippingAddress.fullName : '';
    }

    /** Human-readable label for the currently selected payment method. */
    get methodLabel() {
        return METHOD_LABELS[this.methodId] || 'your selected method';
    }

    /** Place Order button label — changes while the redirect / Apex call is in flight. */
    get payButtonLabel() {
        return this.isProcessing ? 'Processing...' : 'Place Order';
    }

    /** True when the Place Order button should be disabled. */
    get payDisabled() {
        return this.isProcessing;
    }

    /**
     * Handles a method selection event from techBasketPaymentMethod.
     * @param {CustomEvent} event - detail.methodId contains the selected method id
     */
    handleMethodSelect(event) {
        this.methodId = event.detail.methodId;
        this.paymentError = '';
        // A previously-detected Razorpay redirect (checkForGatewayReturn)
        // only applies to the online payment it came back from — manually
        // switching away from Online must not let that stale id ride along
        // into a later Cash submission. Apex independently guards against
        // this too (see submitOrder), but clearing it here means it's never
        // even sent.
        if (this.methodId !== 'online') {
            this.razorpayPaymentId = null;
        }
    }

    /** Navigates back to the Checkout page; the saved draft lets the shopper resume. */
    handleBack() {
        this[NavigationMixin.Navigate](getCheckoutRef());
    }

    /**
     * "Place Order" click. Cash on Delivery submits immediately, same as
     * always. Online redirects to Razorpay's hosted payment page instead —
     * the order is only created in Salesforce once the shopper is back
     * here and Apex has re-verified the payment (see checkForGatewayReturn).
     */
    handlePayNow() {
        this.paymentError = '';
        if (this.methodId === 'online') {
            this.startRazorpayPayment();
            return;
        }
        this.isProcessing = true;
        this.completeOrder();
    }

    /**
     * Creates a Razorpay Payment Link for the current amount payable — the
     * real server-calculated figure (this.pricing.amountPayable, GST-
     * inclusive and net of any discount/loyalty redemption), not a frontend
     * estimate — and redirects the browser to it. submitOrder re-derives and
     * re-verifies this exact same figure server-side once the shopper is
     * back (see its STEP 9 comment), so this preview and that verification
     * always agree as long as the cart/coupon/points don't change in
     * between. The callback URL is this exact page, stripped of any
     * existing query string, so Razorpay's redirect lands back here cleanly.
     */
    async startRazorpayPayment() {
        this.isProcessing = true;
        try {
            const shipping = this.draft.shippingAddress;
            const callbackUrl = window.location.origin + window.location.pathname;

            if (!this.pricing) {
                // The preview hasn't resolved yet — wait for a fresh one
                // rather than charging a stale/estimated amount.
                await new Promise((resolve) => {
                    const check = () => (this.pricing ? resolve() : setTimeout(check, 150));
                    check();
                });
            }

            const result = await createRazorpayPaymentLink({
                amount: this.pricing.amountPayable,
                customerName: this.customerName,
                customerEmail: shipping.email,
                customerPhone: shipping.phone,
                callbackUrl
            });

            window.location.href = result.shortUrl;
        } catch (error) {
            this.isProcessing = false;
            this.paymentError = (error.body && error.body.message)
                ? error.body.message
                : (error.message || 'Could not start the payment. Please try again.');
        }
    }

    /**
     * Calls CheckoutController.submitOrder with the cart, shipping/billing
     * details, recipient, logged-in Account id, coupon code and points
     * requested — Apex revalidates and recalculates every one of those from
     * scratch (never trusts this page's own preview numbers).
     * The cart is re-read fresh from storage right here (rather than trusting
     * only the this.items snapshot loaded on connect) so a stale or lost
     * snapshot can never cause a false "cart is empty" failure at the moment
     * that actually matters — submission time.
     * On success: remembers the order id locally, clears cart and draft, navigates to confirmation.
     * On failure: shows the Apex error message below the Place Order button.
     */
    completeOrder() {
        const freshCart = (this.items && this.items.length) ? this.items : getCart();

        if (!freshCart || freshCart.length === 0) {
            this.isProcessing = false;
            this.paymentError = 'Your cart is empty.';
            return;
        }

        const shipping = this.draft.shippingAddress;
        const billing = this.draft.billingAddress;
        const session = getSession();

        const input = {
            customerName: this.customerName,
            customerEmail: shipping.email,
            customerPhone: shipping.phone,
            paymentMethod: METHOD_TO_PICKLIST[this.methodId] || 'Online',
            // Flat fields (not a nested shippingAddress object) — a nested
            // object here previously caused the request payload to arrive at
            // Apex with items missing/empty even though the cart was full.
            shippingStreet: shipping.address1,
            shippingCity: shipping.city,
            shippingState: shipping.state,
            shippingPostalCode: shipping.postalCode,
            shippingCountry: shipping.country,
            billingStreet: billing ? billing.address1 : shipping.address1,
            billingCity: billing ? billing.city : shipping.city,
            billingState: billing ? billing.state : shipping.state,
            billingPostalCode: billing ? billing.postalCode : shipping.postalCode,
            billingCountry: billing ? billing.country : shipping.country,
            recipientName: shipping.fullName,
            recipientPhone: shipping.phone,
            accountId: session ? session.id : null,
            couponCode: this.appliedCouponCode,
            pointsToRedeem: this.appliedPoints || null,
            shippingMethodId: this.draft.shippingMethod ? this.draft.shippingMethod.id : null,
            items: freshCart.map((item) => ({
                productId: item.productId,
                quantity: item.quantity
            })),
            ...(this.razorpayPaymentId ? { razorpayPaymentId: this.razorpayPaymentId } : {})
        };

        // eslint-disable-next-line no-console
        console.log('[TechBasketPayment] submitOrder input:', JSON.stringify(input));

        // Sent as a raw JSON string and deserialized manually in Apex — see
        // CheckoutController.submitOrder for why: automatic @AuraEnabled
        // parameter binding was unreliably dropping the items list for Guest
        // users even with a well-formed payload.
        submitOrder({ inputJson: JSON.stringify(input) })
            .then((result) => {
                rememberOrder(result.orderId);
                rememberEmail(shipping.email);
                clearCart();
                clearDraft();
                setAppliedCoupon(null);
                this.isProcessing = false;
                this[NavigationMixin.Navigate](getOrderConfirmationRef(result.orderId));
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.log('[TechBasketPayment] submitOrder error:', JSON.stringify(error));
                this.isProcessing = false;
                this.paymentError =
                    (error.body && error.body.message) ||
                    'Something went wrong placing your order. Please try again.';
            });
    }
}
