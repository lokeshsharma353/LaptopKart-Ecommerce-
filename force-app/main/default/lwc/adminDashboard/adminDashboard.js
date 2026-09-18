import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getDashboardStats from '@salesforce/apex/AdminDashboardController.getDashboardStats';
import getCoupons from '@salesforce/apex/AdminDashboardController.getCoupons';
import createCampaignCoupon from '@salesforce/apex/AdminDashboardController.createCampaignCoupon';
import setCouponActive from '@salesforce/apex/AdminDashboardController.setCouponActive';
import sendOfferEmail from '@salesforce/apex/AdminDashboardController.sendOfferEmail';
import getRecentOrders from '@salesforce/apex/AdminDashboardController.getRecentOrders';
import getLowStockProducts from '@salesforce/apex/AdminDashboardController.getLowStockProducts';

/** Blank shape for the "New Coupon Campaign" form — also what the form resets to after a successful create. */
function blankCouponForm() {
    return {
        campaignName: '',
        discountType: 'Percentage',
        discountValue: '',
        minimumOrderValue: '',
        maximumDiscountAmount: '',
        eligibleCategory: '',
        startDate: '',
        endDate: '',
        couponCode: '',
        maxUsesPerCustomer: '1',
        maxTotalUses: ''
    };
}

/**
 * AdminDashboard — a single internal screen (Enterprise Order Management app)
 * where the admin can see store-wide KPIs, create/toggle discount campaigns
 * and coupon codes, and send a one-off offer email to every customer,
 * instead of working across several separate tabs and raw records to do the
 * same things. Every action here goes through AdminDashboardController,
 * which is the same Campaign/Coupon_Code__c data model the storefront's
 * DiscountService already reads from — nothing here is a separate, parallel
 * system.
 */
export default class AdminDashboard extends NavigationMixin(LightningElement) {
    /** Store-wide KPI tiles. */
    @track stats = {
        totalOrders: 0, totalRevenue: 0, totalCustomers: 0,
        activeCoupons: 0, pendingReturns: 0, lowStockProducts: 0
    };
    @track isLoadingStats = true;

    /** Existing coupons/campaigns list. */
    @track coupons = [];
    @track isLoadingCoupons = true;
    _couponsWireResult;

    /** New Coupon Campaign form. */
    @track showNewCouponForm = false;
    @track couponForm = blankCouponForm();
    @track isCreatingCoupon = false;

    /** Offer email form. */
    @track offerSubject = '';
    @track offerBody = '';
    @track isSendingOffer = false;
    /** Shown directly on the card (not just as a toast, which is easy to miss) after a send attempt — { message, isError }. */
    @track offerResult = null;

    /** Recent orders table. */
    @track recentOrders = [];
    @track isLoadingRecentOrders = true;

    /** Low stock products table. */
    @track lowStockList = [];
    @track isLoadingLowStock = true;

    @wire(getDashboardStats)
    wiredStats({ data, error }) {
        this.isLoadingStats = false;
        if (data) {
            this.stats = data;
        } else if (error) {
            this._toast('Error', this._extractError(error), 'error');
        }
    }

    @wire(getCoupons)
    wiredCoupons(result) {
        this._couponsWireResult = result;
        this.isLoadingCoupons = false;
        if (result.data) {
            this.coupons = result.data.map((c) => ({
                ...c,
                statusLabel: c.isActive && c.campaignActive ? 'Active' : 'Inactive',
                statusClass: c.isActive && c.campaignActive ? 'admin-badge admin-badge-active' : 'admin-badge admin-badge-inactive',
                toggleLabel: c.isActive ? 'Deactivate' : 'Activate',
                discountDisplay: c.discountType === 'Flat Amount'
                    ? `Rs. ${c.discountValue} off`
                    : `${c.discountValue}% off`
            }));
        } else if (result.error) {
            this._toast('Error', this._extractError(result.error), 'error');
        }
    }

    @wire(getRecentOrders)
    wiredRecentOrders({ data, error }) {
        this.isLoadingRecentOrders = false;
        if (data) {
            this.recentOrders = data.map((o) => ({
                ...o,
                statusClass: o.status === 'Cancelled' ? 'admin-badge admin-badge-inactive' : 'admin-badge admin-badge-active',
                amountDisplay: (o.amount || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })
            }));
        } else if (error) {
            this._toast('Error', this._extractError(error), 'error');
        }
    }

    @wire(getLowStockProducts)
    wiredLowStock({ data, error }) {
        this.isLoadingLowStock = false;
        if (data) {
            this.lowStockList = data;
        } else if (error) {
            this._toast('Error', this._extractError(error), 'error');
        }
    }

    /** Refreshes both KPIs and the coupon list after any create/toggle action. */
    _refreshAll() {
        return Promise.all([
            refreshApex(this._couponsWireResult),
            getDashboardStats().then((data) => { this.stats = data; })
        ]);
    }

    // ───────────────────────── Quick navigation ─────────────────────────

    _navigateToTab(tabName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: tabName }
        });
    }

    handleGoToOrders() { this._navigateToTab('standard-Order'); }
    handleGoToProducts() { this._navigateToTab('standard-Product2'); }
    handleGoToAccounts() { this._navigateToTab('standard-Account'); }
    handleGoToCampaigns() { this._navigateToTab('standard-Campaign'); }
    handleGoToCoupons() { this._navigateToTab('Coupon_Code__c'); }
    handleGoToOrderTrackings() { this._navigateToTab('Order_Tracking__c'); }

    handleViewOrder(event) {
        const orderId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: orderId, objectApiName: 'Order', actionName: 'view' }
        });
    }

    handleViewProduct(event) {
        const productId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: productId, objectApiName: 'Product2', actionName: 'view' }
        });
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _extractError(error) {
        return (error && error.body && error.body.message) || 'Something went wrong.';
    }

    // ───────────────────────── KPI formatting ─────────────────────────

    get revenueDisplay() {
        return (this.stats.totalRevenue || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }
    get hasLowStock() { return this.stats.lowStockProducts > 0; }
    get hasPendingReturns() { return this.stats.pendingReturns > 0; }
    get lowStockClass() { return this.hasLowStock ? 'admin-kpi-value admin-kpi-value-warning' : 'admin-kpi-value'; }
    get pendingReturnsClass() { return this.hasPendingReturns ? 'admin-kpi-value admin-kpi-value-warning' : 'admin-kpi-value'; }

    // ───────────────────────── New Coupon Campaign ─────────────────────────

    get hasCoupons() { return this.coupons.length > 0; }
    get hasRecentOrders() { return this.recentOrders.length > 0; }
    get hasLowStockList() { return this.lowStockList.length > 0; }

    get discountTypeOptions() {
        return [
            { label: 'Percentage', value: 'Percentage' },
            { label: 'Flat Amount', value: 'Flat Amount' }
        ];
    }

    get newCouponButtonLabel() {
        return this.showNewCouponForm ? 'Cancel' : '+ New Coupon Campaign';
    }

    handleToggleNewCouponForm() {
        this.showNewCouponForm = !this.showNewCouponForm;
        if (!this.showNewCouponForm) {
            this.couponForm = blankCouponForm();
        }
    }

    handleCouponFormChange(event) {
        const field = event.target.dataset.field;
        this.couponForm = { ...this.couponForm, [field]: event.target.value };
    }

    handleCreateCoupon() {
        const form = this.couponForm;
        if (!form.campaignName || !form.couponCode || !form.discountValue) {
            this._toast('Missing information', 'Please fill in the campaign name, coupon code, and discount value.', 'error');
            return;
        }

        this.isCreatingCoupon = true;
        createCampaignCoupon({
            input: {
                campaignName: form.campaignName,
                discountType: form.discountType,
                discountValue: Number(form.discountValue),
                minimumOrderValue: form.minimumOrderValue ? Number(form.minimumOrderValue) : null,
                maximumDiscountAmount: form.maximumDiscountAmount ? Number(form.maximumDiscountAmount) : null,
                eligibleCategory: form.eligibleCategory || null,
                startDate: form.startDate || null,
                endDate: form.endDate || null,
                couponCode: form.couponCode,
                maxUsesPerCustomer: form.maxUsesPerCustomer ? Number(form.maxUsesPerCustomer) : 1,
                maxTotalUses: form.maxTotalUses ? Number(form.maxTotalUses) : null
            }
        })
            .then(() => {
                this._toast('Coupon created', `${form.couponCode.toUpperCase()} is live and ready to use.`, 'success');
                this.couponForm = blankCouponForm();
                this.showNewCouponForm = false;
                return this._refreshAll();
            })
            .catch((error) => this._toast('Could not create coupon', this._extractError(error), 'error'))
            .finally(() => { this.isCreatingCoupon = false; });
    }

    handleToggleCouponActive(event) {
        const id = event.currentTarget.dataset.id;
        const nextActive = event.currentTarget.dataset.active !== 'true';
        setCouponActive({ couponCodeId: id, isActive: nextActive })
            .then(() => {
                this._toast('Updated', `Coupon ${nextActive ? 'activated' : 'deactivated'}.`, 'success');
                return this._refreshAll();
            })
            .catch((error) => this._toast('Could not update coupon', this._extractError(error), 'error'));
    }

    // ───────────────────────── Offer email ─────────────────────────

    get sendOfferButtonLabel() {
        return this.isSendingOffer ? 'Sending…' : 'Send to All Customers';
    }

    get offerResultClass() {
        return this.offerResult && this.offerResult.isError
            ? 'admin-inline-result admin-inline-result-error'
            : 'admin-inline-result admin-inline-result-success';
    }

    handleOfferSubjectChange(event) { this.offerSubject = event.target.value; }
    handleOfferBodyChange(event) { this.offerBody = event.target.value; }

    /**
     * Validates both fields through the lightning-input/-textarea's own
     * built-in validity UI (a red border + inline error message under the
     * field itself) rather than only a toast — a toast can slide in and out
     * fast enough to miss, and gives no lasting proof anything happened.
     * @returns {boolean} true when both fields are non-blank
     */
    _validateOfferForm() {
        const subjectInput = this.template.querySelector('[data-id="offerSubjectInput"]');
        const bodyInput = this.template.querySelector('[data-id="offerBodyInput"]');
        const subjectValid = subjectInput ? subjectInput.reportValidity() : true;
        const bodyValid = bodyInput ? bodyInput.reportValidity() : true;
        return subjectValid && bodyValid;
    }

    handleSendOffer() {
        this.offerResult = null;
        if (!this._validateOfferForm()) {
            return;
        }

        this.isSendingOffer = true;
        sendOfferEmail({ subject: this.offerSubject, body: this.offerBody })
            .then((result) => {
                let message;
                let isError = false;
                const skippedNote = result.skippedBouncedCount > 0
                    ? ` (${result.skippedBouncedCount} skipped — previously bounced/invalid address)`
                    : '';
                if (result.recipientCount === 0 && result.skippedBouncedCount === 0) {
                    message = 'No customer accounts with an email on file were found — nothing was sent.';
                    isError = true;
                } else if (result.recipientCount === 0) {
                    message = `Nothing sent — every customer email on file has previously bounced (${result.skippedBouncedCount} skipped).`;
                    isError = true;
                } else if (result.failureCount > 0) {
                    message = `Sent to ${result.successCount} of ${result.recipientCount}.${skippedNote} Failed: ${result.failureDetails.join('; ')}`;
                    isError = result.successCount === 0;
                } else {
                    message = `Sent to ${result.successCount} customer${result.successCount === 1 ? '' : 's'}.${skippedNote}`;
                }
                this.offerResult = { message, isError };
                this._toast('Offer email sent', message, isError ? 'error' : (result.failureCount > 0 ? 'warning' : 'success'));
                if (!isError) {
                    this.offerSubject = '';
                    this.offerBody = '';
                }
            })
            .catch((error) => {
                const message = this._extractError(error);
                this.offerResult = { message, isError: true };
                this._toast('Could not send offer email', message, 'error');
            })
            .finally(() => { this.isSendingOffer = false; });
    }
}
