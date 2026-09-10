import { LightningElement, api } from 'lwc';

// Reusable [-][qty][+] control. Clamps between 1 and maxQuantity (available stock).
export default class TechBasketQuantitySelector extends LightningElement {
    @api quantity = 1;
    @api maxQuantity = 99;

    // True once quantity is at the floor of 1.
    get atMin() {
        return this.quantity <= 1;
    }

    // True once quantity has reached the available stock.
    get atMax() {
        return this.quantity >= this.maxQuantity;
    }

    // Decrements (never below 1) and notifies the parent.
    handleDecrease() {
        if (!this.atMin) {
            this.quantity -= 1;
            this.notifyChange();
        }
    }

    // Increments (never above maxQuantity) and notifies the parent.
    handleIncrease() {
        if (!this.atMax) {
            this.quantity += 1;
            this.notifyChange();
        }
    }

    // Fires "change" with the new quantity for the parent to act on.
    notifyChange() {
        this.dispatchEvent(new CustomEvent('change', { detail: { quantity: this.quantity } }));
    }
}
