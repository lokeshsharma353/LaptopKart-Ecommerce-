import { LightningElement, track } from 'lwc';
import submitWelcomeLead from '@salesforce/apex/WelcomeLeadController.submitWelcomeLead';
import { getCategories } from 'c/categoryService';
import { showToast } from 'c/toastService';
import { EMAIL_PATTERN, NAME_PATTERN, EMAIL_ERROR, NAME_ERROR } from 'c/formValidators';

/** localStorage key — once dismissed or submitted, don't show again in this browser. */
const STORAGE_KEY = 'techbasket_welcome_seen';
/** Delay before the popup appears, so it doesn't jar the very first paint. */
const SHOW_DELAY_MS = 1500;

/**
 * TechBasketWelcomePopup — a one-time "welcome" lead-capture modal shown
 * shortly after the Home page loads. Collects name/email/laptop-type
 * (the only fields that matter), creates a marketing Lead via
 * WelcomeLeadController, and notifies the admin by email. Shown once per
 * browser (localStorage-gated), not once per page view.
 */
export default class TechBasketWelcomePopup extends LightningElement {
    @track isOpen = false;
    @track formData = { name: '', email: '', laptopType: '' };
    @track errors = {};
    @track isSubmitting = false;

    /** "Which type of laptop" dropdown options — reuses the real category list. */
    laptopTypeOptions = [
        { value: '', label: 'Not sure yet' },
        ...getCategories().map((c) => ({ value: c.name, label: c.name }))
    ];

    _timer;

    /**
     * Lifecycle: shows the popup after SHOW_DELAY_MS, unless this browser
     * has already seen (dismissed or submitted) it before.
     */
    connectedCallback() {
        let alreadySeen = false;
        try {
            alreadySeen = window.localStorage.getItem(STORAGE_KEY) === 'true';
        } catch (e) {
            // storage unavailable — show it anyway, just can't remember dismissal
        }
        if (!alreadySeen) {
            this._timer = setTimeout(() => {
                this.isOpen = true;
            }, SHOW_DELAY_MS);
        }
    }

    disconnectedCallback() {
        if (this._timer) {
            clearTimeout(this._timer);
        }
    }

    /** Updates a form field as the user types. */
    handleInput(event) {
        const field = event.target.dataset.field;
        this.formData = { ...this.formData, [field]: event.target.value };
    }

    /** Updates the laptop-type dropdown selection. */
    handleLaptopTypeChange(event) {
        this.formData = { ...this.formData, laptopType: event.target.value };
    }

    /** Closes the popup without submitting and remembers not to show it again. */
    handleClose() {
        this.dismiss();
    }

    dismiss() {
        this.isOpen = false;
        try {
            window.localStorage.setItem(STORAGE_KEY, 'true');
        } catch (e) {
            // storage unavailable — it'll just show again next visit
        }
    }

    /** Validates the two required fields, then submits the lead via Apex. */
    handleSubmit() {
        const errors = {};
        if (!NAME_PATTERN.test(this.formData.name.trim())) {
            errors.name = NAME_ERROR;
        }
        if (!EMAIL_PATTERN.test(this.formData.email.trim())) {
            errors.email = EMAIL_ERROR;
        }
        this.errors = errors;
        if (Object.keys(errors).length > 0) {
            return;
        }

        this.isSubmitting = true;
        submitWelcomeLead({
            name: this.formData.name,
            email: this.formData.email,
            laptopType: this.formData.laptopType
        })
            .then(() => {
                this.isSubmitting = false;
                showToast("Thanks! We'll point you to the best picks for you.", 'success');
                this.dismiss();
            })
            .catch((error) => {
                this.isSubmitting = false;
                showToast((error.body && error.body.message) || 'Something went wrong. Please try again.', 'error');
            });
    }
}
