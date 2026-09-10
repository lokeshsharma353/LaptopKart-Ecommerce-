import { LightningElement, api, wire } from 'lwc';

import getOrderDetails from '@salesforce/apex/OrderPaymentController.getOrderDetails';
import getPayments from '@salesforce/apex/OrderPaymentController.getPayments';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Order Payment Dashboard — shown on the Order record page in the internal
// Enterprise app. Read-only summary + payment history: there is no "Make
// Payment" button here anymore — every Payment__c record is created only
// by the real website checkout (as 'Pending'), and an admin confirms one by
// editing its Payment_Status__c field directly on the record, not by
// creating a new one from this dashboard.
export default class OrderPaymentDashboard extends LightningElement {

    @api recordId;

    order;
    payments = [];

    wiredOrderResult;
    wiredPaymentsResult;

    columns = [
        {
            label: 'Payment Number',
            fieldName: 'paymentNumber'
        },
        {
            label: 'Amount',
            fieldName: 'amount',
            type: 'currency',
            typeAttributes: {
                currencyCode: 'INR'
            }
        },
        {
            label: 'Date',
            fieldName: 'paymentDate',
            type: 'date'
        },
        {
            label: 'Method',
            fieldName: 'method'
        },
        {
            label: 'Status',
            fieldName: 'status'
        },
        {
            label: 'Transaction ID',
            fieldName: 'transactionId'
        }
    ];


    // Load the current Order details.
    // recordId comes from the Order record page.
    @wire(getOrderDetails, { orderId: '$recordId' })
    wiredOrder(result) {

        this.wiredOrderResult = result;

        if (result.data) {
            this.order = result.data;
        } else if (result.error) {
            this.showError(result.error);
        }
    }


    // Load Payments related to the current Order.
    // Payment records are displayed in the table.
    @wire(getPayments, { orderId: '$recordId' })
    wiredPaymentRecords(result) {

        this.wiredPaymentsResult = result;

        if (result.data) {
            this.payments = result.data;
        } else if (result.error) {
            this.showError(result.error);
        }
    }


    get outstandingAmount() {

        if (!this.order) {
            return 0;
        }

        return Math.max(
            0,
            this.order.orderAmount - this.order.totalPaid
        );
    }


    get outstandingAmountClass() {

        return this.outstandingAmount > 0
            ? 'detail-value outstanding-value is-due'
            : 'detail-value outstanding-value is-paid';
    }

    // Payment Status badge color — reuses the same success/warning/danger
    // tokens as outstandingAmountClass, just keyed off the payment
    // confirmation state instead.
    get paymentStatusClass() {
        if (!this.order || !this.order.paymentStatus) {
            return 'status-badge';
        }
        if (this.order.paymentStatus === 'Fully Paid') {
            return 'status-badge is-paid';
        }
        if (this.order.paymentStatus === 'Unpaid') {
            return 'status-badge is-pending';
        }
        return 'status-badge is-partial';
    }

    /** True once this Order has at least one Payment__c record — the payments table is hidden entirely otherwise. */
    get hasPayments() {
        return this.payments && this.payments.length > 0;
    }

    get hasTracking() {
        return !!(this.order && this.order.trackingNumber);
    }

    /**
     * Opens the real PDF invoice (OrderInvoice Visualforce page) in a new
     * tab. Unlike the storefront's equivalent button, this runs on the
     * org's normal internal domain (this component only ever loads on the
     * Order record page inside Lightning Experience, not the public
     * Experience Cloud site), so a plain relative /apex/... path resolves
     * correctly with no vanity-URL complication.
     */
    handleViewInvoice() {
        window.open(`/apex/OrderInvoice?orderId=${this.recordId}`, '_blank', 'noopener,noreferrer');
    }


    showToast(title, message, variant) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }


    showError(error) {

        let message = 'An error occurred.';

        if (
            error &&
            error.body &&
            error.body.message
        ) {
            message = error.body.message;
        }

        this.showToast(
            'Error',
            message,
            'error'
        );
    }
}
