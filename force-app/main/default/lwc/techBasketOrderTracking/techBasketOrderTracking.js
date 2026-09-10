import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getMyOrders, getOrder } from 'c/orderService';

/**
 * TechBasketOrderTracking — shows real-time tracking info for an order.
 * Can be reached two ways:
 * 1. Via navigation state (orderId passed from Order History's "Track" button).
 * 2. Via manual lookup by order number typed into the search field.
 */
export default class TechBasketOrderTracking extends LightningElement {
    /** The loaded order object, or null if not yet found. */
    @track order = null;
    /** Current value of the manual order number lookup input. */
    @track lookupValue = '';
    /** True when a manual lookup returned no matching order. */
    @track notFound = false;
    /** True while an Apex call is in flight. */
    @track isLoading = false;

    /**
     * Wire: reads the Order Id from navigation state (e.g. from Order History's "Track" button).
     * Loads the order details from Salesforce when an id is present.
     * @param {Object} pageRef - LWR page reference object
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const orderId = pageRef && pageRef.state && pageRef.state.orderId;
        if (orderId) {
            this.isLoading = true;
            getOrder(orderId).then((result) => {
                this.order = result;
                this.isLoading = false;
            });
        }
    }

    /**
     * Updates the lookup input value and clears the "not found" message on each keystroke.
     * @param {Event} event - input event from the order number field
     */
    handleLookupInput(event) {
        this.lookupValue = event.target.value;
        this.notFound = false;
    }

    /**
     * Searches this browser's order history for an order matching the typed order number.
     * Sets notFound to true if no match is found.
     */
    handleLookup() {
        const term = this.lookupValue.trim().toUpperCase();
        this.isLoading = true;
        getMyOrders().then((orders) => {
            const found = orders.find((o) => o.orderNumber.toUpperCase() === term);
            this.order = found || null;
            this.notFound = !found;
            this.isLoading = false;
        });
    }
}
