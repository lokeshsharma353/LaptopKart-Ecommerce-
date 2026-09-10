import { LightningElement, api } from 'lwc';

// Reusable 0-5 star rating display with an optional review count.
export default class TechBasketRating extends LightningElement {
    @api rating = 0;
    @api reviewCount = 0;
    // Experience Builder property: hides the "(count)" text when true.
    @api hideCount = false;

    // Accessible text summary read by screen readers instead of the star glyphs.
    get ariaLabel() {
        return `Rated ${this.rating} out of 5 stars`;
    }

    // Shows the review count only when there is one and it isn't hidden.
    get showCount() {
        return !this.hideCount && this.reviewCount > 0;
    }

    // Builds 5 star entries, marking each filled/half/empty based on the rating value.
    get stars() {
        const result = [];
        for (let i = 1; i <= 5; i++) {
            let type = 'empty';
            if (this.rating >= i) {
                type = 'filled';
            } else if (this.rating >= i - 0.5) {
                type = 'half';
            }
            result.push({ id: `star-${i}`, className: `tb-star tb-star-${type}` });
        }
        return result;
    }
}
