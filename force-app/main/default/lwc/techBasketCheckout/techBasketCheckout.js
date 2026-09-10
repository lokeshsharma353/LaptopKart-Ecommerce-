import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getPaymentRef, getShopRef, getAccountRef } from 'c/navigationService';
import { getCart } from 'c/cartService';
import { saveDraft, encodeHandoff } from 'c/checkoutService';
import { saveAddress } from 'c/addressService';
import { isLoggedIn } from 'c/authService';

/** Step labels shown in the 5-step progress indicator. */
const STEP_LABELS = ['Shipping', 'Billing', 'Shipping Method', 'Payment', 'Review & Confirm'];

/**
 * TechBasketCheckout — the multi-step checkout flow.
 * Internally sequences: Shipping → (Billing, if different address) → Shipping Method,
 * then saves the draft and hands off to the separate Payment page.
 * Steps 4-5 (Payment, Review) live on the Payment page, shown as upcoming here.
 */
export default class TechBasketCheckout extends NavigationMixin(LightningElement) {
    /** Current step key: 'shipping' | 'billing' | 'shippingMethod'. */
    @track step = 'shipping';
    /** Shipping address collected from techBasketShippingForm. */
    @track shippingAddress = null;
    /** Billing address collected from techBasketBillingForm (null if same as shipping). */
    @track billingAddress = null;

    /** Cart items snapshot — used to detect an empty cart on load. */
    items = [];

    /**
     * Lifecycle: loads the current cart to check whether it is empty.
     * An empty cart shows a "nothing to checkout" notice instead of the form steps.
     */
    connectedCallback() {
        this.items = getCart();
    }

    /**
     * True when nobody is logged in via the custom Login_Credentials__c
     * system (see authService) — checkout requires an account so the order
     * can be tied to it and the shipping address saved to it. Checked ahead
     * of the empty-cart state so an unauthenticated shopper always sees
     * "log in to continue" first, regardless of what's in their cart.
     */
    get isLoggedOut() { return !isLoggedIn(); }

    /** True when the cart is empty — shows the empty-cart notice. */
    get isEmptyCart()        { return this.items.length === 0; }
    /** True when the Shipping step is active. */
    get isShippingStep()     { return this.step === 'shipping'; }
    /** True when the Billing step is active. */
    get isBillingStep()      { return this.step === 'billing'; }
    /** True when the Shipping Method step is active. */
    get isShippingMethodStep() { return this.step === 'shippingMethod'; }

    /**
     * Builds the 5-step progress indicator array.
     * Steps before the current one are marked complete (✓); the current step is highlighted.
     */
    get progressSteps() {
        const order = ['shipping', 'billing', 'shippingMethod', 'payment', 'review'];
        const currentIndex = order.indexOf(this.step);
        return STEP_LABELS.map((label, index) => {
            let className = 'tb-progress-step';
            let icon = String(index + 1);
            if (index < currentIndex) {
                className += ' tb-progress-step-done';
                icon = '✓';
            } else if (index === currentIndex) {
                className += ' tb-progress-step-active';
            }
            return { label, className, icon };
        });
    }

    /**
     * Handles the "next" event from techBasketShippingForm.
     * If "use same address for billing" is checked, skips the Billing step.
     * @param {CustomEvent} event - detail contains the completed shipping address
     */
    handleShippingNext(event) {
        this.shippingAddress = event.detail;
        this.billingAddress = event.detail.useSameForBilling ? event.detail : null;
        this.step = event.detail.useSameForBilling ? 'shippingMethod' : 'billing';

        // Every checkout now requires being logged in (see isLoggedOut), so
        // the shipping address is always saved to the shopper's account —
        // no separate opt-in needed. It shows up under My Account > Saved
        // Addresses the same way an explicit save from that page would.
        saveAddress({
            fullName: event.detail.fullName,
            phone: event.detail.phone,
            line1: event.detail.address1,
            address2: event.detail.address2,
            city: event.detail.city,
            state: event.detail.state,
            postalCode: event.detail.postalCode,
            country: event.detail.country
        });
    }

    /** Handles the "back" event from techBasketBillingForm — returns to Shipping. */
    handleBillingBack() {
        this.step = 'shipping';
    }

    /**
     * Handles the "next" event from techBasketBillingForm.
     * @param {CustomEvent} event - detail contains the completed billing address
     */
    handleBillingNext(event) {
        this.billingAddress = event.detail;
        this.step = 'shippingMethod';
    }

    /**
     * Handles the "back" event from techBasketShippingMethod.
     * Returns to Billing if it was shown, otherwise straight back to Shipping.
     */
    handleShippingMethodBack() {
        this.step = this.shippingAddress && !this.shippingAddress.useSameForBilling ? 'billing' : 'shipping';
    }

    /**
     * Handles the "next" event from techBasketShippingMethod.
     * Saves the completed checkout draft to localStorage and navigates to the Payment page.
     * @param {CustomEvent} event - detail contains the selected shipping method
     */
    handleShippingMethodNext(event) {
        const draft = {
            shippingAddress: this.shippingAddress,
            billingAddress: this.billingAddress,
            shippingMethod: event.detail
        };
        saveDraft(draft);
        // Cart + draft also travel in the Payment page's URL state as a
        // fallback in case localStorage doesn't carry over (see
        // checkoutService.encodeHandoff for why).
        this[NavigationMixin.Navigate](getPaymentRef(encodeHandoff(this.items, draft)));
    }

    /** Navigates back to the Product Catalog page. */
    handleContinueShopping() {
        this[NavigationMixin.Navigate](getShopRef());
    }

    /** Navigates to the Account page to log in or sign up before continuing checkout. */
    handleGoToLogin() {
        this[NavigationMixin.Navigate](getAccountRef());
    }
}