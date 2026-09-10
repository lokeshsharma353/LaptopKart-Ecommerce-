import { LightningElement, api } from 'lwc';

// Generic confirmation modal (e.g. Clear Cart). Visibility is fully controlled by the parent.
export default class TechBasketModal extends LightningElement {
    @api isOpen = false;
    @api title = 'Are you sure?';
    @api message = '';
    @api confirmLabel = 'Confirm';
    @api cancelLabel = 'Cancel';

    // Notifies the parent to close the modal without acting.
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    // Notifies the parent the destructive action was confirmed.
    handleConfirm() {
        this.dispatchEvent(new CustomEvent('confirm'));
    }
}
