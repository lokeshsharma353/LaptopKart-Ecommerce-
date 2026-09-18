import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getOrder } from 'c/orderService';
import { getShopRef, getOrderHistoryRef, getOrderTrackingRef } from 'c/navigationService';
import { showToast } from 'c/toastService';

/**
 * TechBasketOrderConfirmation — shown immediately after a successful checkout.
 * Reads the real Order/OrderItem/Order_Tracking__c records created by
 * CheckoutController.submitOrder and displays the order summary, delivery date,
 * and tracking number.
 */
export default class TechBasketOrderConfirmation extends NavigationMixin(LightningElement) {
    /** The loaded order object, or null while loading / if not found. */
    @track order = null;
    /** True while the Apex getOrders call is in flight. */
    @track isLoading = true;

    /** Salesforce Order Id read from navigation state. */
    orderId;

    /**
     * Wire: reads the Order Id from navigation state (set by the Payment page after checkout).
     * Calls getOrder to load the full order details from Salesforce.
     * @param {Object} pageRef - LWR page reference object
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const orderId = pageRef && pageRef.state && pageRef.state.orderId;
        if (orderId && orderId !== this.orderId) {
            this.orderId = orderId;
            this.isLoading = true;
            getOrder(orderId)
                .then((result) => { this.order = result; this.isLoading = false; })
                .catch(() => { this.isLoading = false; });
        }
    }

    /**
     * True once payment is confirmed (Payment__c.Payment_Status__c is
     * 'Successful', which rolls Order.Payment_Status__c up to 'Fully Paid'
     * — see PaymentService). For an Online payment through Razorpay this
     * happens instantly — CheckoutController re-verifies it with Razorpay
     * before the Order is even created, so a shopper paying online lands
     * here already confirmed. Cash on Delivery still starts unconfirmed:
     * nothing has actually been collected yet, so it stays Pending until
     * an admin confirms it by hand.
     */
    get isPaymentConfirmed() {
        return !!this.order && this.order.paymentStatus === 'Fully Paid';
    }

    /**
     * True for a Cash on Delivery order (Payment_Method__c is 'Cash').
     * Nothing has been collected yet, but that's expected — not a payment
     * still being verified — so COD gets its own confirmed-looking state
     * instead of the "we're confirming your payment" copy meant for a
     * self-reported UTR still awaiting admin review.
     */
    get isCashOnDelivery() {
        return !!this.order && this.order.paymentMethod === 'Cash';
    }

    /** Heading text — Fully Paid and Cash on Delivery both read as confirmed; only a real payment still awaiting admin review shows the "received" copy. */
    get confirmationHeading() {
        if (this.isPaymentConfirmed || this.isCashOnDelivery) {
            return 'Thank You! Your Order is Confirmed';
        }
        return "We've Received Your Order";
    }

    /** Subheading text — three distinct states: paid online, pay on delivery, or still awaiting verification. */
    get confirmationSubheading() {
        if (this.isPaymentConfirmed) {
            return 'A confirmation email has been sent to you.';
        }
        if (this.isCashOnDelivery) {
            return `Pay ₹${this.order.totalAmount} in cash when your order arrives.`;
        }
        return "We're confirming your payment — you'll get an email the moment it's approved.";
    }

    /**
     * True once this order carries the real pricing breakdown (Discount/GST/
     * Amount Payable — see OrderPricingService) — every order created since
     * that engine shipped. Guards the detailed breakdown below so an older
     * order from before it existed still falls back to the plain
     * subtotal/paid figures instead of showing blank GST rows.
     */
    get hasPricingBreakdown() {
        return !!this.order && this.order.amountPayable != null;
    }

    get hasDiscount() {
        return !!this.order && this.order.discountAmount > 0;
    }

    get hasLoyaltyDiscount() {
        return !!this.order && this.order.pointsRedeemed > 0;
    }

    /** True when this order actually paid for delivery (Standard is free and stays hidden from the breakdown). */
    get hasShippingCost() {
        return !!this.order && this.order.shippingCost > 0;
    }

    get loyaltyDiscountDisplay() {
        // 1 point = ₹1 — same conversion LoyaltyService uses.
        return this.order && this.order.pointsRedeemed ? this.order.pointsRedeemed.toFixed(2) : '0.00';
    }

    get hasPointsEarned() {
        return !!this.order && this.order.pointsEarned > 0;
    }

    /** True for an intrastate shipment (CGST+SGST shown) — false shows IGST instead. See OrderPricingService.SELLER_STATE. */
    get isIntrastate() {
        return !!this.order && (this.order.igstAmount == null || this.order.igstAmount === 0);
    }

    get hasRecipient() {
        return !!this.order && !!this.order.recipientName;
    }

    /** CSS class for the icon badge at the top of the page — green check for Fully Paid or COD, amber clock only while a real payment is still pending admin review. */
    get confirmationIconClass() {
        return (this.isPaymentConfirmed || this.isCashOnDelivery) ? 'tb-check-mark' : 'tb-check-mark tb-check-mark-pending';
    }

    /** Icon character — checkmark for Fully Paid or COD, a clock only while a real payment is still pending admin review. */
    get confirmationIcon() {
        return (this.isPaymentConfirmed || this.isCashOnDelivery) ? '✔' : '⏳';
    }

    /** Navigates to the Product Catalog page. */
    handleContinueShopping() {
        this[NavigationMixin.Navigate](getShopRef());
    }

    /** Navigates to the Order History page to see all past orders. */
    handleViewOrder() {
        this[NavigationMixin.Navigate](getOrderHistoryRef());
    }

    /** Navigates to the Order Tracking page for this specific order. */
    handleTrackOrder() {
        this[NavigationMixin.Navigate](getOrderTrackingRef(this.orderId));
    }

    /**
     * Opens the real PDF invoice (OrderInvoice Visualforce page, rendered as
     * PDF) in a new tab — the browser handles viewing/downloading it from
     * there. Uses window.open() rather than an <a href> for the same reason
     * as the About Us LinkedIn buttons: reliable external/new-tab navigation
     * on this LWR site.
     *
     * The site's REAL registered name is "techbasketvforcesite" — "LaptopKart"
     * (visible in the browser's address bar / window.location.pathname) is
     * only a vanity URL the LWR page router understands. Classic /apex/...
     * Visualforce routing does not recognize that vanity path and 404s on
     * it; confirmed directly by fetching both paths unauthenticated — only
     * /techbasketvforcesite/apex/... resolves. Hardcoded rather than derived
     * from the current URL for that reason.
     */
    handleDownloadInvoice() {
        if (!this.orderId) {
            showToast('Order not loaded yet.', 'warning');
            return;
        }
        const url = `${window.location.origin}/techbasketvforcesite/apex/OrderInvoice?orderId=${this.orderId}`;
        window.open(url, '_blank', 'noopener,noreferrer');
    }
}
