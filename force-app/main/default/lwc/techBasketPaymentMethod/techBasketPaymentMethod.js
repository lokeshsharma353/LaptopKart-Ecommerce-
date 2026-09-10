import { LightningElement, api } from 'lwc';

const METHODS = [
    { id: 'online', label: 'Online Payment' },
    { id: 'cod', label: 'Cash on Delivery' }
];

// Payment method picker: Online Payment or Cash on Delivery. Selection is
// passed up; a real online payment gateway integration is BACKEND CONNECTION
// REQUIRED — both methods currently place the order immediately.
export default class TechBasketPaymentMethod extends LightningElement {
    @api selectedId = 'online';

    get methods() {
        return METHODS.map((m) => ({
            ...m,
            className: m.id === this.selectedId ? 'tb-method-btn tb-method-btn-active' : 'tb-method-btn'
        }));
    }

    // Notifies the parent (techBasketPayment) which method is now selected.
    handleSelect(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('methodselect', { detail: { methodId: id } }));
    }
}
