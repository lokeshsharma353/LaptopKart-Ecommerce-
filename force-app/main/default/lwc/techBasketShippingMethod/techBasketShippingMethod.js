import { LightningElement, track } from 'lwc';

const METHODS = [
    { id: 'standard', name: 'Standard Delivery', eta: '5-7 business days', price: 0 },
    { id: 'express', name: 'Express Delivery', eta: '2-3 business days', price: 500 },
    { id: 'overnight', name: 'Overnight Delivery', eta: 'Next day', price: 1500 }
];

// Shipping method selector: Standard / Express / Overnight, with live totals impact via "next".
export default class TechBasketShippingMethod extends LightningElement {
    @track selectedId = 'standard';

    // Builds the option list, marking the selected one for highlight styling.
    get methods() {
        return METHODS.map((m) => ({
            ...m,
            priceLabel: m.price === 0 ? 'Free' : `₹${m.price}`,
            className: m.id === this.selectedId ? 'tb-method tb-method-selected' : 'tb-method'
        }));
    }

    handleSelect(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    // Hands the selected method (with its cost) to the checkout flow.
    handleNext() {
        const method = METHODS.find((m) => m.id === this.selectedId);
        this.dispatchEvent(new CustomEvent('next', { detail: { ...method } }));
    }
}
