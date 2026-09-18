import { LightningElement, api } from 'lwc';

/**
 * The fulfillment steps shown in a row, in order. "Order Placed" and
 * "Payment" are derived from standard/existing fields (Order.Status,
 * Order.Payment_Status__c — auto-recalculated whenever a Payment__c record
 * changes); "Shipped"/"Out for Delivery"/"Delivered" come from
 * Order_Tracking__c.Delivery_Status__c, which the admin updates by hand as
 * the physical shipment progresses — there's no courier integration here.
 *
 * Two different step orders exist because payment happens at a different
 * point in the real-world flow depending on the method: an online payment
 * is collected up front, before the order even ships, so Payment sits
 * second. Cash on Delivery is collected by the courier at the doorstep —
 * after Delivered, not before Shipped — so for COD orders Payment Received
 * is the last step instead of the second one.
 */
const ONLINE_STEPS = [
    { key: 'placed', label: 'Order Placed' },
    { key: 'paid', label: 'Payment' },
    { key: 'shipped', label: 'Shipped' },
    { key: 'outForDelivery', label: 'Out for Delivery' },
    { key: 'delivered', label: 'Delivered' }
];
const COD_STEPS = [
    { key: 'placed', label: 'Order Placed' },
    { key: 'shipped', label: 'Shipped' },
    { key: 'outForDelivery', label: 'Out for Delivery' },
    { key: 'delivered', label: 'Delivered' },
    { key: 'paid', label: 'Payment Received' }
];

/**
 * TechBasketOrderProgress — a horizontal "your order, step by step" row
 * used on Order Confirmation and Order Tracking. Purely a display of
 * existing data (Order.Status, Order.Payment_Status__c,
 * Order_Tracking__c.Delivery_Status__c via the OrderSummary the parent
 * already loaded) — every step here reflects a field an admin sets by hand
 * in Salesforce (directly on the Order/Order_Tracking__c/Payment__c record,
 * or in the Enterprise Order Management app), not anything this component
 * writes back.
 */
export default class TechBasketOrderProgress extends LightningElement {
    /** OrderSummary-shaped object: {status, paymentStatus, deliveryStatus}. */
    @api order;

    /** True when the order (or its tracking) has been cancelled — shows a banner instead of the step row. */
    get isCancelled() {
        return !!this.order && (this.order.status === 'Cancelled' || this.order.deliveryStatus === 'Cancelled');
    }

    /** True for a Cash on Delivery order — Payment_Method__c is 'Cash'. Determines which step order applies (see COD_STEPS above). */
    get isCashOnDelivery() {
        return !!this.order && this.order.paymentMethod === 'Cash';
    }

    /** The step order to render — COD moves Payment to the end; online keeps it second. */
    get activeSteps() {
        return this.isCashOnDelivery ? COD_STEPS : ONLINE_STEPS;
    }

    /**
     * Index of the furthest step reached so far in whichever step order is
     * active, derived from the real field values — never stored, always
     * recomputed from the order. COD counts delivery progress first and
     * only reaches its final "Payment Received" step once an admin has
     * actually recorded the cash collection as a Successful Payment__c;
     * online counts a Fully Paid payment before any delivery progress can
     * be reached at all, matching that money is collected up front there.
     */
    get reachedIndex() {
        if (!this.order) {
            return 0;
        }
        if (this.isCashOnDelivery) {
            if (this.order.paymentStatus === 'Fully Paid') {
                return 4;
            }
            if (this.order.deliveryStatus === 'Delivered') {
                return 3;
            }
            if (this.order.deliveryStatus === 'Out for Delivery') {
                return 2;
            }
            if (this.order.deliveryStatus === 'Shipped') {
                return 1;
            }
            return 0;
        }
        if (this.order.deliveryStatus === 'Delivered') {
            return 4;
        }
        if (this.order.deliveryStatus === 'Out for Delivery') {
            return 3;
        }
        if (this.order.deliveryStatus === 'Shipped') {
            return 2;
        }
        if (this.order.paymentStatus === 'Fully Paid') {
            return 1;
        }
        return 0;
    }

    /** True when the payment step reflects an actual problem — an Online/Card/Net Banking payment still not Fully Paid. Cash on Delivery is excluded: Unpaid before the final step is expected there, not an issue. */
    get hasPaymentIssue() {
        return !!this.order && this.order.paymentStatus && this.order.paymentStatus !== 'Fully Paid' && !this.isCashOnDelivery;
    }

    /** True when the delivery estimate row should render — a real deliveryDate exists (Order_Tracking__c.Delivery_Date__c, set at checkout) and the order hasn't already been delivered or cancelled. */
    get showDeliveryEstimate() {
        return !!this.order && !!this.order.deliveryDate && this.order.deliveryStatus !== 'Delivered' && !this.isCancelled;
    }

    /** The estimated delivery date formatted for display, e.g. "24 Sep 2026". */
    get deliveryDateDisplay() {
        if (!this.order || !this.order.deliveryDate) {
            return '';
        }
        return new Date(this.order.deliveryDate).toLocaleDateString('en-IN', {
            day: 'numeric', month: 'short', year: 'numeric'
        });
    }

    /**
     * Builds the row of step objects with done/current/upcoming styling and
     * a sub-label under the Payment step showing its real status text.
     */
    get steps() {
        const reached = this.reachedIndex;
        const activeSteps = this.activeSteps;
        return activeSteps.map((step, index) => {
            let cls = 'tb-progress-step';
            if (index < reached) {
                cls += ' tb-progress-step-done';
            } else if (index === reached) {
                cls += this.hasPaymentIssue && step.key === 'paid' ? ' tb-progress-step-issue' : ' tb-progress-step-current';
            }
            return {
                key: step.key,
                label: step.label,
                cls,
                subLabel: step.key === 'paid' ? this.order.paymentStatus : '',
                isLast: index === activeSteps.length - 1
            };
        });
    }
}
