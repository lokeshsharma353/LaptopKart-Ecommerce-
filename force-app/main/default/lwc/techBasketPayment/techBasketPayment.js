import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getOrderConfirmationRef, getCheckoutRef } from 'c/navigationService';
import { getCart, clearCart } from 'c/cartService';
import { calculateTotals } from 'c/cartCalculations';
import { getDraft, saveDraft, clearDraft, decodeHandoff } from 'c/checkoutService';
import { rememberOrder, rememberEmail } from 'c/orderService';
import submitOrder from '@salesforce/apex/CheckoutController.submitOrder';
import PAYMENT_QR from '@salesforce/resourceUrl/GooglePay_QR';

/** Human-readable labels for each payment method id. */
const METHOD_LABELS = { online: 'Online Payment', cod: 'Cash on Delivery' };
/** Maps the LWC method id to the exact Payment_Method__c picklist value in Salesforce. */
const METHOD_TO_PICKLIST = { online: 'Online', cod: 'Cash' };
/** Bumped on every deploy so the browser console proves which build is actually running. */
const BUILD_TAG = 'payment-qr-utr-2026-09-08-1';
/** UTR is trusted at face value (no gateway to verify against) — just a
 *  loose sanity check so an empty/obviously-wrong entry doesn't sail through. */
const MIN_UTR_LENGTH = 6;

/**
 * TechBasketPayment — the standalone Payment page.
 * Reads the checkout draft and cart saved by TechBasketCheckout, collects a
 * payment method:
 *  - Online: shows a QR code step first — the shopper scans and pays via
 *    any UPI app, then types in the UTR (transaction reference) their app
 *    gave them. There's no gateway API here to verify that UTR against —
 *    it's recorded as the Payment's transaction id at face value, and the
 *    admin reconciles it manually against their own UPI account.
 *  - Cash on Delivery: unchanged — submits immediately.
 */
export default class TechBasketPayment extends NavigationMixin(LightningElement) {
    /** Currently selected payment method id: 'online' | 'cod'. */
    @track methodId = 'online';
    /** True while the Apex call is in progress. */
    @track isProcessing = false;
    /** Error message shown below the Place Order button on Apex failure. */
    @track paymentError = '';
    /** True once "Place Order" has been clicked for Online — shows the QR/UTR step instead of the method picker. */
    @track showQrStep = false;
    /** UTR the shopper typed in after paying via the QR code. */
    @track utrNumber = '';
    /** Validation error for the UTR field. */
    @track utrError = '';

    /** Cart items snapshot loaded on connect — used to render totals. */
    items = [];
    /** Checkout draft (shipping/billing/shipping method) loaded from localStorage. */
    draft = null;

    _handoffApplied = false;

    /** Public URL of the UPI QR code image shown on the Online Payment step. */
    qrImageUrl = PAYMENT_QR;

    /**
     * Loads the cart/draft the Checkout page handed off. Prefers the payload
     * encoded in the page's own URL state (survives even if localStorage
     * doesn't carry over between Checkout and Payment); falls back to
     * localStorage for direct reloads/back-navigation where no state is
     * present. Redirects to Checkout only if neither source has a draft.
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
    }

    /**
     * Calculates the order totals including the selected shipping method cost.
     * Used by the order summary panel on this page. Purely for display — the
     * actual order submission re-reads the cart fresh (see completeOrder).
     */
    get totals() {
        const shippingCost = this.draft && this.draft.shippingMethod ? this.draft.shippingMethod.price : 0;
        return calculateTotals(this.items, { shippingCost });
    }

    /** Human-readable label for the currently selected payment method. */
    get methodLabel() {
        return METHOD_LABELS[this.methodId] || 'your selected method';
    }

    /** True while the method picker (not the QR/UTR step) should be shown. */
    get showMethodStep() {
        return !this.showQrStep;
    }

    /** Place Order button label — changes to "Placing Order..." while in flight. */
    get payButtonLabel() {
        return this.isProcessing ? 'Placing Order...' : 'Place Order';
    }

    /** True when the Place Order button should be disabled. */
    get payDisabled() {
        return this.isProcessing;
    }

    /** Confirm Payment button label — changes to "Placing Order..." while in flight. */
    get confirmButtonLabel() {
        return this.isProcessing ? 'Placing Order...' : 'I\'ve Paid — Confirm Order';
    }

    /**
     * Handles a method selection event from techBasketPaymentMethod.
     * @param {CustomEvent} event - detail.methodId contains the selected method id
     */
    handleMethodSelect(event) {
        this.methodId = event.detail.methodId;
        this.paymentError = '';
    }

    /** Navigates back to the Checkout page; the saved draft lets the shopper resume. */
    handleBack() {
        this[NavigationMixin.Navigate](getCheckoutRef());
    }

    /** Returns from the QR/UTR step back to the method picker without placing the order. */
    handleBackFromQr() {
        this.showQrStep = false;
        this.utrError = '';
        this.paymentError = '';
    }

    /** Updates the UTR field as the shopper types, clearing any previous error. */
    handleUtrInput(event) {
        this.utrNumber = event.target.value;
        this.utrError = '';
    }

    /**
     * "Place Order" click. Cash on Delivery submits immediately, same as
     * always. Online shows the QR/UTR step first instead of submitting —
     * the actual order is only created once the shopper confirms they've
     * paid and enters a UTR (see handleConfirmPayment).
     */
    handlePayNow() {
        this.paymentError = '';
        if (this.methodId === 'online') {
            this.showQrStep = true;
            return;
        }
        this.isProcessing = true;
        this.completeOrder();
    }

    /**
     * "I've Paid — Confirm Order" click on the QR/UTR step. Validates the
     * UTR was actually entered (a loose length check only — there's no
     * gateway to verify it against, so this never blocks a genuine
     * payment over formatting), then places the order.
     */
    handleConfirmPayment() {
        const utr = this.utrNumber.trim();
        if (utr.length < MIN_UTR_LENGTH) {
            this.utrError = 'Enter the UTR / transaction reference number from your UPI app.';
            return;
        }
        this.utrError = '';
        this.isProcessing = true;
        this.paymentError = '';
        this.completeOrder();
    }

    /**
     * Calls CheckoutController.submitOrder with the cart, shipping details,
     * and (for Online) the UTR entered on the QR step.
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
        const input = {
            customerName: shipping.fullName,
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
            items: freshCart.map((item) => ({
                productId: item.productId,
                quantity: item.quantity
            })),
            ...(this.methodId === 'online' ? { utrNumber: this.utrNumber.trim() } : {})
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
