import { LightningElement, track } from 'lwc';

const METHODS = [
    { id: 'standard', name: 'Standard Delivery', eta: '5-7 business days', price: 0 },
    { id: 'express', name: 'Express Delivery', eta: '2-3 business days', price: 500 },
    { id: 'overnight', name: 'Overnight Delivery', eta: 'Next day', price: 1500 }
];

// Shipping method selector: Standard / Express / Overnight, with live totals impact via "next".
export default class TechBasketShippingMethod extends LightningElement {
    @track selectedId = 'standard';

    // Tells the parent the default selection (Standard/free) the moment this
    // step renders, so the sidebar total is correct even before the shopper
    // clicks anything — not just after they actively pick a method.
    connectedCallback() {
        const method = METHODS.find((m) => m.id === this.selectedId);
        this.dispatchEvent(new CustomEvent('select', { detail: { ...method } }));
    }

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
        // Fires immediately on click (not just when "Next" is pressed) so
        // the checkout sidebar's total can update live as the shopper
        // compares delivery options, instead of only changing once they've
        // already committed to a choice and moved on.
        const method = METHODS.find((m) => m.id === this.selectedId);
        this.dispatchEvent(new CustomEvent('select', { detail: { ...method } }));
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
