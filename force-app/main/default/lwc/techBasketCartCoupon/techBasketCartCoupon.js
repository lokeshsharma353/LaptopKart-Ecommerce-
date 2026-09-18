import { LightningElement, track } from 'lwc';
import { getCart, subscribe as subscribeCart } from 'c/cartService';
import { getSession } from 'c/authService';
import { getAppliedCoupon, setAppliedCoupon } from 'c/couponService';
import previewOrderTotals from '@salesforce/apex/CheckoutController.previewOrderTotals';
import getAvailableCoupons from '@salesforce/apex/DiscountService.getAvailableCoupons';

/**
 * TechBasketCartCoupon — lets a shopper preview a coupon discount right on
 * the Cart page, before committing to Checkout. Uses the exact same server
 * pricing engine as the Payment page (CheckoutController.previewOrderTotals)
 * so the discount shown here is real, not a frontend guess — only the GST/
 * shipping-state fields aren't shown here since shipping isn't chosen yet
 * at this point in the flow. The applied code is carried forward via
 * couponService so it's already filled in by the time the shopper reaches
 * Payment, instead of having to retype it.
 */
export default class TechBasketCartCoupon extends LightningElement {
    /** Coupon code currently typed in the input (not yet necessarily applied). */
    @track couponInput = '';
    /** Coupon code that has actually been applied to the live server preview — null when none. */
    @track appliedCouponCode = null;
    /** Message from the last coupon validation (success or rejection reason). */
    @track couponMessage = '';
    /** True when the last coupon validation succeeded. */
    @track couponValid = false;
    /** Discount amount from the last successful validation. */
    @track discountAmount = 0;
    /** True while a validation call is in flight. */
    @track isApplying = false;
    /** Every currently usable coupon code, shown under the input. */
    @track availableCoupons = [];
    /** True while the available-coupons list is expanded. */
    @track showAvailableCoupons = false;

    unsubscribeCart;

    connectedCallback() {
        this.unsubscribeCart = subscribeCart(() => {
            // Cart contents changed (qty/remove) — re-validate a still-applied
            // coupon against the new subtotal so the shown discount never goes stale.
            if (this.appliedCouponCode) {
                this.applyCode(this.appliedCouponCode);
            }
        });

        getAvailableCoupons()
            .then((coupons) => { this.availableCoupons = coupons || []; })
            .catch(() => { this.availableCoupons = []; });

        const stored = getAppliedCoupon();
        if (stored) {
            this.couponInput = stored;
            this.applyCode(stored);
        }
    }

    disconnectedCallback() {
        if (this.unsubscribeCart) { this.unsubscribeCart(); }
    }

    /** True once at least one available coupon has been loaded. */
    get hasAvailableCoupons() { return this.availableCoupons.length > 0; }

    /** The "View Coupons" toggle only appears when there's something to show and no coupon is already applied. */
    get showViewCouponsButton() { return this.hasAvailableCoupons && !this.appliedCouponCode; }

    /** Label flips between "View Coupons" and "Hide Coupons". */
    get viewCouponsLabel() { return this.showAvailableCoupons ? 'Hide Coupons' : 'View Coupons'; }

    /** CSS class for the coupon message — green when applied, red when rejected. */
    get couponMessageClass() {
        return this.couponValid ? 'tb-promo-message tb-promo-message-success' : 'tb-promo-message tb-promo-message-error';
    }

    get discountDisplay() {
        return Number(this.discountAmount || 0).toFixed(2);
    }

    /**
     * Validates a coupon code against the current cart via the real pricing
     * engine and updates state accordingly. Shared by connectedCallback
     * (re-applying a carried-over code), handleApplyCoupon, and the cart
     * subscription (re-validating after a quantity change).
     * @param {string} code
     */
    applyCode(code) {
        const items = getCart();
        if (!items.length) {
            return;
        }
        const session = getSession();
        this.isApplying = true;

        const requestJson = JSON.stringify({
            items: items.map((item) => ({ productId: item.productId, quantity: item.quantity })),
            shippingState: null,
            accountId: session ? session.id : null,
            couponCode: code,
            pointsToRedeem: null
        });

        previewOrderTotals({ requestJson })
            .then((result) => {
                this.isApplying = false;
                this.couponValid = result.couponValid;
                this.couponMessage = result.couponMessage;
                this.discountAmount = result.discountAmount;
                if (result.couponValid) {
                    this.appliedCouponCode = code;
                    setAppliedCoupon(code);
                } else {
                    // Invalid/expired since it was first applied — drop it
                    // rather than silently keep showing a stale discount.
                    this.appliedCouponCode = null;
                    setAppliedCoupon(null);
                }
            })
            .catch(() => {
                this.isApplying = false;
                this.couponValid = false;
                this.couponMessage = 'Could not validate this coupon right now. Please try again.';
            });
    }

    handleCouponInput(event) {
        this.couponInput = event.target.value;
    }

    handleApplyCoupon() {
        if (!this.couponInput || !this.couponInput.trim()) {
            return;
        }
        this.applyCode(this.couponInput.trim().toUpperCase());
    }

    handleToggleAvailableCoupons() {
        this.showAvailableCoupons = !this.showAvailableCoupons;
    }

    handleSelectAvailableCoupon(event) {
        const code = event.currentTarget.dataset.code;
        this.couponInput = code;
        this.showAvailableCoupons = false;
        this.applyCode(code);
    }

    handleRemoveCoupon() {
        this.appliedCouponCode = null;
        this.couponInput = '';
        this.couponMessage = '';
        this.couponValid = false;
        this.discountAmount = 0;
        setAppliedCoupon(null);
    }
}
