import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getLoginRef } from 'c/navigationService';
import signUp from '@salesforce/apex/LoginCredentialsController.signUp';
import {
    EMAIL_PATTERN, PHONE_PATTERN, NAME_PATTERN,
    EMAIL_ERROR, PHONE_ERROR, NAME_ERROR, sanitizePhoneInput
} from 'c/formValidators';

/**
 * TechBasketSignUp — the new account registration page.
 * Creates a LaptopKart customer account via LoginCredentialsController.signUp,
 * saving credentials to Account.Password_Text__c so login via My Account works.
 */
export default class TechBasketSignUp extends NavigationMixin(LightningElement) {
    /** Form field values for the registration form. */
    @track formData = { firstName: '', lastName: '', email: '', phone: '', password: '', confirmPassword: '' };
    /** Validation error messages keyed by field name. */
    @track errors = {};
    /** True while the Apex registerUser call is in flight. */
    @track isSubmitting = false;
    /** Error message shown below the submit button on Apex failure. */
    @track submitError = '';
    /** True after a successful registration — shows the success state. */
    @track submitted = false;

    /** Submit button label — changes to "Creating Account..." while submitting. */
    get submitLabel() {
        return this.isSubmitting ? 'Creating Account...' : 'Sign Up';
    }

    /**
     * Updates a form field and clears its error on every keystroke.
     * @param {Event} event - target.dataset.field identifies which field changed
     */
    handleInput(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'phone') {
            value = sanitizePhoneInput(value);
            event.target.value = value;
        }
        this.formData = { ...this.formData, [field]: value };
        this.errors = { ...this.errors, [field]: '' };
    }

    /**
     * Validates all required fields, name/phone/email formats, and password rules.
     * Stores error messages in this.errors and returns true only when all pass.
     * @returns {boolean} true when the form is valid
     */
    validate() {
        const errors = {};
        if (!this.formData.firstName.trim()) {
            errors.firstName = 'First name is required.';
        } else if (!NAME_PATTERN.test(this.formData.firstName.trim())) {
            errors.firstName = NAME_ERROR;
        }
        if (!this.formData.lastName.trim()) {
            errors.lastName = 'Last name is required.';
        } else if (!NAME_PATTERN.test(this.formData.lastName.trim())) {
            errors.lastName = NAME_ERROR;
        }
        if (!EMAIL_PATTERN.test(this.formData.email.trim())) {
            errors.email = EMAIL_ERROR;
        }
        if (!this.formData.phone.trim()) {
            errors.phone = 'Phone number is required.';
        } else if (!PHONE_PATTERN.test(this.formData.phone.trim())) {
            errors.phone = PHONE_ERROR;
        }
        if (this.formData.password.length < 8) {
            errors.password = 'Password must be at least 8 characters.';
        }
        if (this.formData.confirmPassword !== this.formData.password) {
            errors.confirmPassword = 'Passwords do not match.';
        }
        this.errors = errors;
        return Object.keys(errors).length === 0;
    }

    /**
     * Validates the form and calls LoginCredentialsController.signUp on success.
     * Shows inline errors on validation failure or an Apex error message on server failure.
     */
    handleSubmit() {
        this.submitError = '';
        if (!this.validate()) { return; }
        this.isSubmitting = true;
        const fullName = (this.formData.firstName.trim() + ' ' + this.formData.lastName.trim()).trim();
        signUp({
            name: fullName,
            email: this.formData.email,
            phone: this.formData.phone,
            password: this.formData.password
        })
            .then(() => { this.isSubmitting = false; this.submitted = true; })
            .catch((error) => {
                this.isSubmitting = false;
                this.submitError = (error.body && error.body.message) || 'Unable to create your account. Please try again.';
            });
    }

    /** Navigates to the Salesforce login page. */
    handleGoToLogin() {
        this[NavigationMixin.Navigate](getLoginRef());
    }
}
