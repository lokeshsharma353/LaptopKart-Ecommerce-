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
     * True once an admin has manually confirmed payment (Payment__c.Payment_Status__c
     * changed to 'Successful', which rolls Order.Payment_Status__c up to
     * 'Fully Paid' — see PaymentService). Every order starts unconfirmed:
     * an Online payment is a self-reported UTR with nothing to verify it
     * against, and Cash on Delivery hasn't actually been collected yet.
     */
    get isPaymentConfirmed() {
        return !!this.order && this.order.paymentStatus === 'Fully Paid';
    }

    /** Heading text — differs before vs. after admin payment confirmation. */
    get confirmationHeading() {
        return this.isPaymentConfirmed ? 'Thank You! Your Order is Confirmed' : "We've Received Your Order";
    }

    /** Subheading text — differs before vs. after admin payment confirmation. */
    get confirmationSubheading() {
        return this.isPaymentConfirmed
            ? 'A confirmation email has been sent to you.'
            : "We're confirming your payment — you'll get an email the moment it's approved.";
    }

    /** CSS class for the icon badge at the top of the page — green check once confirmed, amber clock while pending. */
    get confirmationIconClass() {
        return this.isPaymentConfirmed ? 'tb-check-mark' : 'tb-check-mark tb-check-mark-pending';
    }

    /** Icon character — checkmark once confirmed, a clock while payment is still pending admin review. */
    get confirmationIcon() {
        return this.isPaymentConfirmed ? '✔' : '⏳';
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
