import { LightningElement, track } from 'lwc';
import { showToast } from 'c/toastService';
import submitMessage from '@salesforce/apex/ContactController.submitMessage';
import {
    EMAIL_PATTERN, NAME_PATTERN, PHONE_PATTERN,
    EMAIL_ERROR, NAME_ERROR, PHONE_ERROR, sanitizePhoneInput
} from 'c/formValidators';

/** Static FAQ data — real FAQs would come from Salesforce Knowledge articles. */
const FAQS = [
    { id: 'f1', question: 'How long does delivery take?', answer: 'Standard delivery is 5-7 business days.' },
    { id: 'f2', question: 'What is your return policy?', answer: 'Items can be returned within 14 days of delivery.' },
    { id: 'f3', question: 'Do you ship internationally?', answer: 'Currently we ship within the country only.' }
];

/**
 * TechBasketContactUs — the Contact Us page.
 * Contains a message submission form, support contact details, FAQs,
 * and a live chat entry point (backend integration required for actual chat).
 */
export default class TechBasketContactUs extends LightningElement {
    /** Form field values for the contact message form. */
    @track formData = { name: '', email: '', phone: '', subject: '', message: '' };
    /** Validation error messages keyed by field name. */
    @track errors = {};
    /** True after a successful form submission — shows the success message. */
    @track submitted = false;
    /** True while the Apex call is in flight — disables the Submit button. */
    @track isSubmitting = false;

    faqs = FAQS;

    /**
     * Updates a form field value as the user types.
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
    }

    /**
     * Validates all form fields, then sends the message to the admin's
     * email via ContactController.submitMessage. Phone is optional, so it's
     * only checked for a valid 10-digit shape when the shopper actually
     * typed something into it.
     */
    handleSubmit() {
        const errors = {};
        const phone = this.formData.phone.trim();
        if (!NAME_PATTERN.test(this.formData.name.trim())) { errors.name = NAME_ERROR; }
        if (!EMAIL_PATTERN.test(this.formData.email.trim())) { errors.email = EMAIL_ERROR; }
        if (phone && !PHONE_PATTERN.test(phone)) { errors.phone = PHONE_ERROR; }
        if (!this.formData.subject.trim()) { errors.subject = 'Subject is required.'; }
        if (!this.formData.message.trim()) { errors.message = 'Message is required.'; }
        this.errors = errors;
        if (Object.keys(errors).length > 0) {
            return;
        }

        this.isSubmitting = true;
        submitMessage({
            name: this.formData.name,
            email: this.formData.email,
            phone: this.formData.phone,
            subject: this.formData.subject,
            message: this.formData.message
        })
            .then(() => {
                this.isSubmitting = false;
                this.submitted = true;
            })
            .catch((error) => {
                this.isSubmitting = false;
                showToast((error.body && error.body.message) || 'Could not send your message. Please try again.', 'error');
            });
    }

    /**
     * Placeholder for live chat — real implementation requires a third-party chat integration.
     */
    handleLiveChat() {
        showToast('Live chat requires backend integration.', 'warning');
    }
}
