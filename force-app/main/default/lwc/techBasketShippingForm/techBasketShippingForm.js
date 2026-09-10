import { LightningElement, api, track } from 'lwc';
import { getAddresses } from 'c/addressService';
import {
    EMAIL_PATTERN, PHONE_PATTERN, NAME_PATTERN, POSTAL_PATTERN,
    PHONE_ERROR, EMAIL_ERROR, NAME_ERROR, POSTAL_ERROR,
    sanitizePhoneInput, sanitizePostalInput
} from 'c/formValidators';

const REQUIRED_FIELDS = ['fullName', 'email', 'phone', 'address1', 'city', 'state', 'postalCode', 'country'];
/** Fields checked against NAME_PATTERN (letters only) in addition to being required. */
const NAME_FIELDS = ['fullName', 'city', 'state'];

// Shipping address form. Validates required fields live and blocks Next until valid.
export default class TechBasketShippingForm extends LightningElement {
    @track formData = {
        fullName: '', email: '', phone: '', address1: '', address2: '',
        city: '', state: '', postalCode: '', country: '',
        useSameForBilling: true, saveAddress: false
    };
    @track errors = {};
    /** Addresses saved via addressService (My Account, or a previous checkout's "Save this address"). */
    @track savedAddresses = [];

    /** Loads the saved address book so the shopper can pick one instead of retyping. */
    connectedCallback() {
        this.savedAddresses = getAddresses().map((a) => ({
            ...a,
            optionLabel: [a.line1, a.city].filter(Boolean).join(', ') || 'Saved address'
        }));
    }

    /** True when at least one saved address exists — shows the chooser dropdown. */
    get hasSavedAddresses() {
        return this.savedAddresses.length > 0;
    }

    /**
     * Fills the form from a chosen saved address, then re-validates every
     * required field so "Next" enables immediately without the shopper
     * having to click into each field first. Email isn't part of a saved
     * address (the address book only stores shipping details), so whatever
     * email the shopper already typed is left untouched.
     * @param {Event} event - target.value contains the selected address id
     */
    handleSelectSavedAddress(event) {
        const id = event.target.value;
        if (!id) {
            return;
        }
        const addr = this.savedAddresses.find((a) => a.id === id);
        if (!addr) {
            return;
        }
        this.formData = {
            ...this.formData,
            fullName: addr.fullName || this.formData.fullName,
            phone: sanitizePhoneInput(addr.phone || ''),
            address1: addr.line1 || '',
            address2: addr.address2 || '',
            city: addr.city || '',
            state: addr.state || '',
            postalCode: sanitizePostalInput(addr.postalCode || ''),
            country: addr.country || ''
        };
        REQUIRED_FIELDS.forEach((field) => this.validateField(field));
    }

    // Updates the field being edited and re-validates it immediately.
    // Phone/postalCode are sanitized as the shopper types so non-digits and
    // extra length are simply not accepted, not just flagged after the fact.
    handleInput(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'phone') {
            value = sanitizePhoneInput(value);
            event.target.value = value;
        } else if (field === 'postalCode') {
            value = sanitizePostalInput(value);
            event.target.value = value;
        }
        this.formData = { ...this.formData, [field]: value };
        this.validateField(field);
    }

    handleSameBillingChange(event) {
        this.formData = { ...this.formData, useSameForBilling: event.target.checked };
    }

    handleSaveAddressChange(event) {
        this.formData = { ...this.formData, saveAddress: event.target.checked };
    }

    // Per-field validation, called on every keystroke so errors clear as soon as they're fixed.
    validateField(field) {
        const value = this.formData[field].trim();
        let message = '';

        if (REQUIRED_FIELDS.includes(field) && !value) {
            message = 'This field is required.';
        } else if (field === 'email' && !EMAIL_PATTERN.test(value)) {
            message = EMAIL_ERROR;
        } else if (field === 'phone' && !PHONE_PATTERN.test(value)) {
            message = PHONE_ERROR;
        } else if (field === 'postalCode' && !POSTAL_PATTERN.test(value)) {
            message = POSTAL_ERROR;
        } else if (NAME_FIELDS.includes(field) && !NAME_PATTERN.test(value)) {
            message = NAME_ERROR;
        }

        this.errors = { ...this.errors, [field]: message };
    }

    // True while any required field is empty or invalid; drives the Next button's disabled state.
    get isInvalid() {
        return REQUIRED_FIELDS.some((field) => {
            const value = this.formData[field].trim();
            if (!value) {
                return true;
            }
            if (field === 'email') {
                return !EMAIL_PATTERN.test(value);
            }
            if (field === 'phone') {
                return !PHONE_PATTERN.test(value);
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

    // Validates everything, then hands the completed address to the parent checkout flow.
    handleNext() {
        REQUIRED_FIELDS.forEach((field) => this.validateField(field));
        if (!this.isInvalid) {
            this.dispatchEvent(new CustomEvent('next', { detail: { ...this.formData } }));
        }
    }
}
