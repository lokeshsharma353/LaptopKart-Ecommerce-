import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getMyOrders, cancelOrder } from 'c/orderService';
import { getOrderConfirmationRef, getShopRef } from 'c/navigationService';
import { showToast } from 'c/toastService';

/**
 * TechBasketOrderHistory — lists every website order placed by this shopper
 * (matched by the email remembered from checkout — see orderService.getMyOrders
 * — with a fallback to this browser's locally remembered order ids), fetched
 * from Salesforce via CheckoutController. Two actions per order: View Order
 * (order confirmation/detail, including tracking) and Cancel Order.
 */
export default class TechBasketOrderHistory extends NavigationMixin(LightningElement) {
    /** Array of order summary objects loaded from Salesforce. */
    @track orders = [];
    /** True while the Apex getOrders call is in flight. */
    @track isLoading = true;

    /**
     * Lifecycle: loads every order this shopper has placed.
     * Each order is enriched with a statusClass for pill badge styling and
     * a canCancel flag (true unless the order is already Cancelled).
     */
    connectedCallback() {
        this.loadOrders();
    }

    /** (Re)loads orders from Salesforce and rebuilds the display list. */
    loadOrders() {
        this.isLoading = true;
        getMyOrders()
            .then((results) => {
                this.orders = results.map((order) => this.decorate(order));
                this.isLoading = false;
            })
            .catch(() => { this.isLoading = false; });
    }

    /**
     * Adds display-only fields to a raw OrderSummary from Apex.
     * @param {Object} order - OrderSummary returned by CheckoutController
     * @returns {Object} order enriched with statusClass/canCancel/isCancelling
     */
    decorate(order) {
        return {
            ...order,
            statusClass: order.status === 'Cancelled'
                ? 'tb-status tb-status-cancelled'
                : order.status === 'Activated'
                    ? 'tb-status tb-status-done'
                    : 'tb-status tb-status-processing',
            canCancel: order.status !== 'Cancelled',
            isCancelling: false,
            // The real, final charged amount (GST-inclusive, net of any
            // discount/loyalty redemption) — never the raw pre-tax
            // totalAmount, which would show a lower figure than what the
            // customer actually paid. Falls back to totalAmount only for an
            // order that predates the pricing engine (amountPayable blank).
            displayAmount: order.amountPayable != null ? order.amountPayable : order.totalAmount
        };
    }

    /** True when at least one order has been loaded. */
    get hasOrders() {
        return this.orders.length > 0;
    }

    /**
     * Navigates to the Order Confirmation page for the clicked order — it
     * already shows full order detail including tracking, so one "View
     * Order" action covers both order detail and tracking.
     * @param {Event} event - currentTarget.dataset.id contains the Order Salesforce Id
     */
    handleViewDetails(event) {
        this[NavigationMixin.Navigate](getOrderConfirmationRef(event.currentTarget.dataset.id));
    }

    /**
     * Cancels an order via CheckoutController.cancelOrder, then updates it
     * in place (no full reload needed) on success.
     * @param {Event} event - currentTarget.dataset.id contains the Order Salesforce Id
     */
    handleCancelOrder(event) {
        const orderId = event.currentTarget.dataset.id;
        const order = this.orders.find((o) => o.orderId === orderId);
        const label = order ? `Order #${order.orderNumber}` : 'This order';

        this.orders = this.orders.map((o) => (o.orderId === orderId ? { ...o, isCancelling: true } : o));

        cancelOrder(orderId)
            .then(() => {
                this.orders = this.orders.map((o) =>
                    o.orderId === orderId ? this.decorate({ ...o, status: 'Cancelled' }) : o
                );
                showToast(`${label} has been cancelled.`, 'success');
            })
            .catch((error) => {
                this.orders = this.orders.map((o) => (o.orderId === orderId ? { ...o, isCancelling: false } : o));
                showToast((error.body && error.body.message) || `Could not cancel ${label}.`, 'error');
            });
    }

    /** Navigates to the Product Catalog page. */
    handleShopNow() {
        this[NavigationMixin.Navigate](getShopRef());
    }
}
