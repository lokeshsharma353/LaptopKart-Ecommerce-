/**
 * formValidators — shared field-format rules used by every form on the
 * storefront (Shipping, Billing, Contact Us, Sign Up, My Account), so a
 * phone number, PIN code, etc. is checked the same way everywhere instead
 * of each component inventing its own regex.
 */

/** Exactly 10 digits, no spaces/symbols — matches an Indian mobile number. */
export const PHONE_PATTERN = /^[0-9]{10}$/;
/** Standard email shape: something@something.something, no spaces. */
export const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
/** Letters, spaces, apostrophes and hyphens only, 2-50 characters — for names, cities, states. */
export const NAME_PATTERN = /^[A-Za-z][A-Za-z\s'-]{1,49}$/;
/** 6-digit Indian PIN code, first digit 1-9. */
export const POSTAL_PATTERN = /^[1-9][0-9]{5}$/;

/** True when value is exactly 10 digits. */
export function isValidPhone(value) {
    return PHONE_PATTERN.test((value || '').trim());
}

/** True when value looks like a real email address. */
export function isValidEmail(value) {
    return EMAIL_PATTERN.test((value || '').trim());
}

/** True when value is a plausible person/place name. */
export function isValidName(value) {
    return NAME_PATTERN.test((value || '').trim());
}

/** True when value is a 6-digit Indian PIN code. */
export function isValidPostalCode(value) {
    return POSTAL_PATTERN.test((value || '').trim());
}

/** Strips everything but digits and caps at 10 — used on phone fields' oninput so you physically cannot type an 11th digit or a letter. */
export function sanitizePhoneInput(value) {
    return (value || '').replace(/\D/g, '').slice(0, 10);
}

/** Strips everything but digits and caps at 6 — used on PIN code fields' oninput. */
export function sanitizePostalInput(value) {
    return (value || '').replace(/\D/g, '').slice(0, 6);
}

/** Standard error message shown under an invalid phone field. */
export const PHONE_ERROR = 'Enter a valid 10-digit mobile number.';
/** Standard error message shown under an invalid email field. */
export const EMAIL_ERROR = 'Enter a valid email address.';
/** Standard error message shown under an invalid name field. */
export const NAME_ERROR = 'Enter a valid name (letters only).';
/** Standard error message shown under an invalid postal code field. */
export const POSTAL_ERROR = 'Enter a valid 6-digit PIN code.';
