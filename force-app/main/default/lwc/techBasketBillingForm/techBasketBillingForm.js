import { LightningElement, track } from 'lwc';
import { NAME_PATTERN, POSTAL_PATTERN, NAME_ERROR, POSTAL_ERROR, sanitizePostalInput } from 'c/formValidators';

const REQUIRED_FIELDS = ['address1', 'city', 'state', 'postalCode', 'country'];
/** Fields checked against NAME_PATTERN (letters only) in addition to being required. */
const NAME_FIELDS = ['city', 'state'];

// Billing address form, shown only when "use same address for billing" is unchecked.
export default class TechBasketBillingForm extends LightningElement {
    @track formData = { address1: '', address2: '', city: '', state: '', postalCode: '', country: '' };
    @track errors = {};

    handleInput(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'postalCode') {
            value = sanitizePostalInput(value);
            event.target.value = value;
        }
        this.formData = { ...this.formData, [field]: value };
        this.validateField(field);
    }

    // Per-field validation, mirrors the Shipping form's approach.
    validateField(field) {
        const value = this.formData[field].trim();
        let message = '';
        if (REQUIRED_FIELDS.includes(field) && !value) {
            message = 'This field is required.';
        } else if (field === 'postalCode' && !POSTAL_PATTERN.test(value)) {
            message = POSTAL_ERROR;
        } else if (NAME_FIELDS.includes(field) && !NAME_PATTERN.test(value)) {
            message = NAME_ERROR;
        }
        this.errors = { ...this.errors, [field]: message };
    }

    get isInvalid() {
        return REQUIRED_FIELDS.some((field) => {
            const value = this.formData[field].trim();
            if (!value) {
                return true;
            }
            if (field === 'postalCode') {
                return !POSTAL_PATTERN.test(value);
            }
            if (NAME_FIELDS.includes(field)) {
                return !NAME_PATTERN.test(value);
            }
            return false;
        });
    }

    // Returns to the Shipping step.
    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    // Validates everything, then hands the completed billing address to the checkout flow.
    handleNext() {
        REQUIRED_FIELDS.forEach((field) => this.validateField(field));
        if (!this.isInvalid) {
            this.dispatchEvent(new CustomEvent('next', { detail: { ...this.formData } }));
        }
    }
}
