import { LightningElement, api } from 'lwc';

/**
 * The fulfillment steps shown in a row, in order. "Order Placed" and
 * "Payment" are derived from standard/existing fields (Order.Status,
 * Order.Payment_Status__c — auto-recalculated whenever a Payment__c record
 * changes); "Shipped"/"Out for Delivery"/"Delivered" come from
 * Order_Tracking__c.Delivery_Status__c, which the admin updates by hand as
 * the physical shipment progresses — there's no courier integration here.
 */
const STEPS = [
    { key: 'placed', label: 'Order Placed' },
    { key: 'paid', label: 'Payment' },
    { key: 'shipped', label: 'Shipped' },
    { key: 'outForDelivery', label: 'Out for Delivery' },
    { key: 'delivered', label: 'Delivered' }
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

    /**
     * Index (0-4) of the furthest step reached so far, derived from the
     * real field values — never stored, always recomputed from the order.
     */
    get reachedIndex() {
        if (!this.order) {
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

    /** True when the payment step reflects an actual problem (admin marked a payment Failed/Refunded) rather than just "not reached yet". */
    get hasPaymentIssue() {
        return !!this.order && this.order.paymentStatus && this.order.paymentStatus !== 'Fully Paid';
    }

    /**
     * Builds the row of step objects with done/current/upcoming styling and
     * a sub-label under the Payment step showing its real status text.
     */
    get steps() {
        const reached = this.reachedIndex;
        return STEPS.map((step, index) => {
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
                isLast: index === STEPS.length - 1
            };
        });
    }
}
