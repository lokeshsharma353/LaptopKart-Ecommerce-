import { LightningElement, api } from 'lwc';

// Clickable category tile used on the homepage; notifies the parent which category was picked.
export default class TechBasketCategoryCard extends LightningElement {
    @api categoryName = '';
    @api itemCount = 0;

    // Single-letter placeholder shown in place of a real category image.
    get categoryInitial() {
        return this.categoryName ? this.categoryName.charAt(0).toUpperCase() : '?';
    }

    // Notifies the parent (usually Home) of the chosen category name.
    handleClick() {
        this.dispatchEvent(new CustomEvent('categoryselect', { detail: { category: this.categoryName } }));
    }
}
