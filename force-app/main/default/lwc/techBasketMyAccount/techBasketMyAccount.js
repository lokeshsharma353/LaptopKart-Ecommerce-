import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import signUp from '@salesforce/apex/LoginCredentialsController.signUp';
import logIn from '@salesforce/apex/LoginCredentialsController.logIn';
import requestPasswordReset from '@salesforce/apex/LoginCredentialsController.requestPasswordReset';
import getOrdersByEmail from '@salesforce/apex/CheckoutController.getOrdersByEmail';
import requestReturn from '@salesforce/apex/CheckoutController.requestReturn';
import getLoyaltyWallet from '@salesforce/apex/LoginCredentialsController.getLoyaltyWallet';
import updateProfilePhoto from '@salesforce/apex/LoginCredentialsController.updateProfilePhoto';
import updateProfileInfo from '@salesforce/apex/LoginCredentialsController.updateProfileInfo';
import getMyAddresses from '@salesforce/apex/LoginCredentialsController.getMyAddresses';
import saveMyAddress from '@salesforce/apex/LoginCredentialsController.saveMyAddress';
import deleteMyAddress from '@salesforce/apex/LoginCredentialsController.deleteMyAddress';

/** Mirrors CheckoutController.RETURN_WINDOW_DAYS — client-side only for showing/hiding the button; Apex re-validates the real window on submit. */
const RETURN_WINDOW_DAYS = 7;
import { getSession, setSession, clearSession, subscribe } from 'c/authService';
import { rememberEmail } from 'c/orderService';
import { getOrderConfirmationRef, getOrderTrackingRef, getProductRef } from 'c/navigationService';
import { showToast } from 'c/toastService';
import { getWishlist, toggleWishlist } from 'c/wishlistService';
import { loadProducts, findById } from 'c/productDataService';
import { getSettings, saveSettings } from 'c/accountSettingsService';
import { addItem } from 'c/cartService';
import { getProductImages } from 'c/brandService';
import {
    EMAIL_PATTERN, PHONE_PATTERN, NAME_PATTERN,
    EMAIL_ERROR, PHONE_ERROR, NAME_ERROR, sanitizePhoneInput
} from 'c/formValidators';
import LOGIN_LOGO from '@salesforce/resourceUrl/LapkartLogoWhite';

/** Longest side (px) of the profile photo saved to Account.Profile_Photo__c — see resizeImageToDataUri. */
const PHOTO_TARGET_SIZE = 200;
/** Reject an original file above this size outright — the resize step below handles everything smaller without needing a hard cap much lower than this. */
const MAX_PHOTO_FILE_BYTES = 15 * 1024 * 1024;

/**
 * Center-crops the selected image to a square and scales it down to
 * PHOTO_TARGET_SIZE x PHOTO_TARGET_SIZE, returning a JPEG data URI — this
 * keeps the upload well under Profile_Photo__c's size limit no matter how
 * large the original photo was (a raw phone camera shot can be several MB;
 * the resized JPEG is typically a few tens of KB), and means the resize
 * happens entirely in the browser — nothing but the final small data URI is
 * ever sent to Apex.
 * @param {File} file - the selected image file
 * @returns {Promise<string>} resolves with a "data:image/jpeg;base64,..." data URI
 */
function resizeImageToDataUri(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = () => reject(new Error('Could not read the selected file.'));
        reader.onload = () => {
            const img = new Image();
            img.onerror = () => reject(new Error('That file doesn\'t look like a valid image.'));
            img.onload = () => {
                const side = Math.min(img.width, img.height);
                const sx = (img.width - side) / 2;
                const sy = (img.height - side) / 2;
                const canvas = document.createElement('canvas');
                canvas.width = PHOTO_TARGET_SIZE;
                canvas.height = PHOTO_TARGET_SIZE;
                canvas.getContext('2d').drawImage(img, sx, sy, side, side, 0, 0, PHOTO_TARGET_SIZE, PHOTO_TARGET_SIZE);
                resolve(canvas.toDataURL('image/jpeg', 0.85));
            };
            img.src = reader.result;
        };
        reader.readAsDataURL(file);
    });
}

/**
 * TechBasketMyAccount — the Account page.
 * This storefront has no real per-shopper Salesforce login (every visitor is
 * the Site Guest User) — login/sign-up is a lightweight custom system backed
 * by the standard Account object, Customer Account Detail record type (see
 * LoginCredentialsController), and a
 * client-side session (see authService). Logged out: a Log In / Sign Up
 * card. Logged in: a sidebar-driven dashboard — a Dashboard summary shown by
 * default, then My Profile, My Orders, Saved Addresses, Wishlist, Payment
 * Methods, Account Settings. Every section shows real data from an actual
 * backing service (Orders via CheckoutController, Addresses/Wishlist/
 * Settings via their own localStorage-backed services). Payment Methods
 * shows the two real checkout methods (Online/COD) as informational cards —
 * LaptopKart never stores payment details, so there's nothing to "manage".
 * Reviews & Ratings was removed from this nav entirely (products don't have
 * a reviews system in this project — see Product Detail's mocked reviews).
 */
export default class TechBasketMyAccount extends NavigationMixin(LightningElement) {
    /** The white LaptopKart brand logo, shown on the logged-out login/sign-up auth card. */
    logoUrl = LOGIN_LOGO;

    /** Current session ({ id, name, email, phone }), or null when logged out. */
    @track session = null;
    /** Which form is shown when logged out: 'login', 'signUp', or 'forgotPassword'. */
    @track mode = 'login';
    /** True while a signUp/logIn/requestPasswordReset Apex call is in flight — disables the submit button. */
    @track isSubmitting = false;
    /** Error message shown above the active form, if any. */
    @track errorMessage = '';
    /** True once the Forgot Password form has been submitted successfully — shows a confirmation instead of the form. */
    @track forgotPasswordSubmitted = false;

    /** Which dashboard section is shown when logged in — starts on the Dashboard summary. */
    @track activeSection = 'dashboard';

    /** This shopper's own past orders, scoped to their logged-in email. */
    @track orders = [];
    /** True while the getOrdersByEmail Apex call is in flight. */
    @track isLoadingOrders = false;

    /** Saved addresses — each toggleable into an inline edit mode. */
    @track addresses = [];

    /** Full product catalog — needed to resolve wishlisted product ids to real product details. */
    @track allProducts = [];
    /** Bumped on every wishlist change to force the wishlistProducts getter to recompute (it reads localStorage directly, which LWC can't observe on its own). */
    @track wishlistVersion = 0;

    /** Notification preferences, persisted via accountSettingsService. */
    @track settings = { emailNotifications: true };

    /** Rewards Wallet — loyalty point balance and ledger history (LoginCredentialsController.getLoyaltyWallet). See Feature Expansion Plan §2.7. */
    @track loyaltyWallet = { balance: 0, pointsValueRupees: 0, transactions: [] };
    /** True while the loyalty wallet Apex call is in flight. */
    @track isLoadingRewards = false;

    /** Unsubscribe function from authService — called on disconnect. */
    _unsubscribe;

    connectedCallback() {
        this.session = getSession();
        if (this.session) {
            this.initDashboard();
        }
        this._unsubscribe = subscribe((session) => {
            this.session = session;
            if (session) {
                this.initDashboard();
            } else {
                this.orders = [];
                this.activeSection = 'dashboard';
            }
        });
    }

    disconnectedCallback() {
        if (this._unsubscribe) this._unsubscribe();
    }

    /** Loads everything the dashboard's sections need, once a session exists. */
    initDashboard() {
        this.loadOrders();
        this.loadAddresses();
        this.settings = getSettings();
        loadProducts().then((products) => { this.allProducts = products; });
        this.loadRewards();
    }

    /** Loads this shopper's saved addresses from their own Account (Saved_Address__c). */
    loadAddresses() {
        getMyAddresses({ accountId: this.session.id })
            .then((results) => {
                this.addresses = results.map((a) => ({ ...a, editing: false }));
            })
            .catch(() => { this.addresses = []; });
    }

    /** Loads this shopper's loyalty balance and ledger history. */
    loadRewards() {
        this.isLoadingRewards = true;
        getLoyaltyWallet({ accountId: this.session.id })
            .then((wallet) => {
                this.loyaltyWallet = {
                    ...wallet,
                    transactions: (wallet.transactions || []).map((t) => ({
                        ...t,
                        pointsClass: t.points > 0 ? 'tb-rewards-row-points tb-rewards-row-points-positive' : 'tb-rewards-row-points tb-rewards-row-points-negative',
                        pointsDisplay: t.points > 0 ? `+${t.points}` : `${t.points}`
                    }))
                };
            })
            .catch(() => { this.loyaltyWallet = { balance: 0, pointsValueRupees: 0, transactions: [] }; })
            .finally(() => { this.isLoadingRewards = false; });
    }

    /** True once a session exists — drives the dashboard vs. login/sign-up forms. */
    get isLoggedIn() { return !!this.session; }

    /**
     * Up to 2 uppercase initials from the shopper's name (e.g. "Priya Shah"
     * -> "PS"), shown on a generated avatar in place of an uploaded photo —
     * this login system has no photo-storage field, so a real initials
     * avatar (the same pattern Gmail/Slack use) is the honest, real option
     * rather than a fake stock photo.
     */
    get avatarInitials() {
        const name = (this.session && this.session.name) || '';
        const parts = name.trim().split(/\s+/).filter(Boolean);
        if (parts.length === 0) return '?';
        if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
        return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }

    /**
     * Deterministic background color for the avatar, derived from the
     * shopper's name (same name always gets the same color, different
     * shoppers usually get visually distinct ones) — a small fixed palette
     * of navy/slate shades kept consistent with the site's blue-forward theme,
     * rather than an unrelated rainbow of hues.
     */
    get avatarStyle() {
        const palette = ['#2563EB', '#1D4ED8', '#1E3A8A', '#334155', '#0F172A', '#3B82F6', '#475569'];
        const name = (this.session && this.session.name) || '';
        let hash = 0;
        for (let i = 0; i < name.length; i++) {
            hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
        }
        const color = palette[hash % palette.length];
        return `background: ${color};`;
    }

    /** True once the shopper has uploaded a profile photo — switches every avatar on the page from the generated initials to the real image. */
    get hasProfilePhoto() { return !!(this.session && this.session.profilePhoto); }

    /** True while a selected photo is being resized/uploaded — disables the change-photo control so a shopper can't fire off a second upload mid-flight. */
    @track isUploadingPhoto = false;

    /** Text link label under the profile avatar — changes while an upload is in flight. */
    get changePhotoLabel() {
        if (this.isUploadingPhoto) return 'Uploading…';
        return this.hasProfilePhoto ? 'Change Photo' : 'Add Photo';
    }

    /**
     * Opens the native file picker — triggered by the visible "Change
     * Photo" button, which is separate from the actual (hidden) file input
     * so it can be styled consistently with the rest of the UI.
     */
    handleChoosePhoto() {
        const input = this.template.querySelector('input[data-id="profilePhotoInput"]');
        if (input) input.click();
    }

    /**
     * Handles a profile-photo file selection: validates it's a real image
     * under a sane raw size, resizes it client-side (see
     * resizeImageToDataUri), saves it via Apex, and updates the shared
     * session — every avatar on the page (sidebar, dashboard banner,
     * profile card) reflects the new photo immediately since they all read
     * from the same session object, no reload needed.
     * @param {Event} event - the file input's change event
     */
    handlePhotoSelect(event) {
        const file = event.target.files && event.target.files[0];
        event.target.value = ''; // allow re-selecting the same file again later
        if (!file) return;

        if (!file.type || !file.type.startsWith('image/')) {
            showToast('Please choose an image file.', 'error');
            return;
        }
        if (file.size > MAX_PHOTO_FILE_BYTES) {
            showToast('That image is too large. Please choose one under 15 MB.', 'error');
            return;
        }

        this.isUploadingPhoto = true;
        resizeImageToDataUri(file)
            .then((dataUri) => updateProfilePhoto({ accountId: this.session.id, photoDataUri: dataUri }).then(() => dataUri))
            .then((dataUri) => {
                setSession({ ...this.session, profilePhoto: dataUri });
                showToast('Profile photo updated.', 'success');
            })
            .catch((error) => {
                showToast(this._extractError(error) || 'Could not update your photo. Please try again.', 'error');
            })
            .finally(() => { this.isUploadingPhoto = false; });
    }

    /** True while the Account Information card on My Profile is in edit mode. */
    @track isEditingProfile = false;
    /** True while the updateProfileInfo Apex call is in flight — disables the Save button. */
    @track isSavingProfile = false;

    /** Switches the Account Information card into edit mode. */
    handleEditProfile() { this.isEditingProfile = true; }

    /** Exits edit mode without saving any changes. */
    handleCancelEditProfile() { this.isEditingProfile = false; }

    /**
     * Submits the Account Information edit form: validates name/email/phone
     * the same way Sign Up does, calls LoginCredentialsController.updateProfileInfo
     * (which also blocks a duplicate email server-side), and refreshes the
     * shared session so every part of the page (sidebar, welcome banner,
     * profile card) reflects the new details immediately.
     */
    handleSaveProfile() {
        const name = this._readField('profileName').trim();
        const email = this._readField('profileEmail').trim();
        const phone = this._readField('profilePhone').trim();

        if (!name || !email || !phone) {
            showToast('Please fill in all fields.', 'error');
            return;
        }
        if (!NAME_PATTERN.test(name)) {
            showToast(NAME_ERROR, 'error');
            return;
        }
        if (!EMAIL_PATTERN.test(email)) {
            showToast(EMAIL_ERROR, 'error');
            return;
        }
        if (!PHONE_PATTERN.test(phone)) {
            showToast(PHONE_ERROR, 'error');
            return;
        }

        this.isSavingProfile = true;
        updateProfileInfo({ accountId: this.session.id, name, email, phone })
            .then((session) => {
                setSession(session);
                // See handleLogin — keeps the two Order History surfaces in sync
                // even after an email change.
                rememberEmail(session.email);
                this.isEditingProfile = false;
                showToast('Profile updated.', 'success');
            })
            .catch((error) => {
                showToast(this._extractError(error) || 'Could not update your profile. Please try again.', 'error');
            })
            .finally(() => { this.isSavingProfile = false; });
    }

    /** Save button label on the Account Information edit form. */
    get saveProfileLabel() { return this.isSavingProfile ? 'Saving…' : 'Save Changes'; }

    get isLoginMode() { return !this.isLoggedIn && this.mode === 'login'; }
    get isSignUpMode() { return !this.isLoggedIn && this.mode === 'signUp'; }
    get isForgotPasswordMode() { return !this.isLoggedIn && this.mode === 'forgotPassword'; }
    get hasError() { return !!this.errorMessage; }

    get loginTabClass() { return this.mode === 'login' ? 'tb-tab tb-tab-active' : 'tb-tab'; }
    get signUpTabClass() { return this.mode === 'signUp' ? 'tb-tab tb-tab-active' : 'tb-tab'; }

    get loginButtonLabel() { return this.isSubmitting ? 'Logging in…' : 'Log In'; }
    get signUpButtonLabel() { return this.isSubmitting ? 'Creating account…' : 'Create Account'; }
    get forgotPasswordButtonLabel() { return this.isSubmitting ? 'Submitting…' : 'Submit Request'; }

    /** Switches to the Sign Up tab and clears any error from the other form. */
    handleSwitchToSignUp() { this.mode = 'signUp'; this.errorMessage = ''; }
    /** Switches to the Log In tab and clears any error from the other form. */
    handleSwitchToLogin() { this.mode = 'login'; this.errorMessage = ''; this.forgotPasswordSubmitted = false; }
    /** Switches to the Forgot Password form and clears any error from the other form. */
    handleSwitchToForgotPassword() { this.mode = 'forgotPassword'; this.errorMessage = ''; this.forgotPasswordSubmitted = false; }

    /**
     * Reads a form field's *current* value straight from the DOM rather than
     * from tracked component state. Necessary because browser autofill (a
     * saved address/password) can visibly populate an input without firing
     * the standard `input` event — relying on an oninput-synced tracked
     * property would silently submit blank values in that case even though
     * the field looks filled on screen. (Fields don't need manual resetting
     * elsewhere — the if:true/if:false template blocks around each form
     * unmount and remount their inputs fresh whenever the mode or logged-in
     * state changes, which already clears any uncontrolled value.)
     * @param {string} field - the input's data-field attribute value
     * @returns {string} the input's current value (empty string if not found)
     */
    _readField(field) {
        const el = this.template.querySelector(`[data-field="${field}"]`);
        return el ? el.value : '';
    }

    /**
     * Live-sanitizes a phone input as the shopper types: strips anything
     * that isn't a digit and caps it at 10 characters, so it's physically
     * impossible to type an 11th digit or a letter into these fields.
     * @param {Event} event - the phone input's own input event
     */
    handlePhoneInput(event) {
        event.target.value = sanitizePhoneInput(event.target.value);
    }

    /**
     * Submits the Log In form: calls LoginCredentialsController.logIn, and on
     * success starts a session via authService (which re-renders this
     * component into the logged-in dashboard).
     */
    handleLogin() {
        this.errorMessage = '';
        const email = this._readField('loginEmail').trim();
        const password = this._readField('loginPassword');

        if (!email || !password) {
            this.errorMessage = 'Please enter your email and password.';
            return;
        }
        if (!EMAIL_PATTERN.test(email)) {
            this.errorMessage = EMAIL_ERROR;
            return;
        }
        this.isSubmitting = true;
        logIn({ email, password })
            .then((session) => {
                setSession(session);
                // Keeps orderService's remembered checkout email in sync with
                // whoever is actually logged in, so the standalone Order
                // History page (which looks orders up by that remembered
                // email) always agrees with My Account's own Order History
                // tab (which looks orders up by this session's email) —
                // without this they can silently diverge whenever someone
                // logs into an account whose email differs from the email
                // last used at checkout on this browser.
                rememberEmail(session.email);
                showToast(`Welcome back, ${session.name}!`, 'success');
            })
            .catch((error) => { this.errorMessage = this._extractError(error); })
            .finally(() => { this.isSubmitting = false; });
    }

    /**
     * Submits the Sign Up form: calls LoginCredentialsController.signUp
     * (which blocks duplicate emails server-side), and on success starts a
     * session immediately — no separate log-in step needed after signing up.
     */
    handleSignUp() {
        this.errorMessage = '';
        const name = this._readField('signUpName').trim();
        const email = this._readField('signUpEmail').trim();
        const phone = this._readField('signUpPhone').trim();
        const password = this._readField('signUpPassword');

        if (!name || !email || !phone || !password) {
            this.errorMessage = 'Please fill in all fields.';
            return;
        }
        if (!NAME_PATTERN.test(name)) {
            this.errorMessage = NAME_ERROR;
            return;
        }
        if (!EMAIL_PATTERN.test(email)) {
            this.errorMessage = EMAIL_ERROR;
            return;
        }
        if (!PHONE_PATTERN.test(phone)) {
            this.errorMessage = PHONE_ERROR;
            return;
        }
        if (password.length < 8) {
            this.errorMessage = 'Password must be at least 8 characters.';
            return;
        }
        this.isSubmitting = true;
        signUp({ name, email, phone, password })
            .then((session) => {
                setSession(session);
                // See handleLogin — keeps the two Order History surfaces in sync.
                rememberEmail(session.email);
                showToast(`Welcome, ${session.name}!`, 'success');
            })
            .catch((error) => { this.errorMessage = this._extractError(error); })
            .finally(() => { this.isSubmitting = false; });
    }

    /**
     * Submits the Forgot Password form: calls
     * LoginCredentialsController.requestPasswordReset, which creates a Task
     * for an admin to follow up directly — there's no automated reset link
     * in this custom login system. On success, shows a confirmation instead
     * of the form.
     */
    handleForgotPasswordSubmit() {
        this.errorMessage = '';
        const email = this._readField('forgotPasswordEmail').trim();
        const phone = this._readField('forgotPasswordPhone').trim();
        const message = this._readField('forgotPasswordMessage').trim();

        if (!email) {
            this.errorMessage = 'Please enter the email on your account.';
            return;
        }
        if (!EMAIL_PATTERN.test(email)) {
            this.errorMessage = EMAIL_ERROR;
            return;
        }
        if (phone && !PHONE_PATTERN.test(phone)) {
            this.errorMessage = PHONE_ERROR;
            return;
        }
        this.isSubmitting = true;
        requestPasswordReset({ email, phone, message })
            .then(() => {
                this.forgotPasswordSubmitted = true;
            })
            .catch((error) => { this.errorMessage = this._extractError(error); })
            .finally(() => { this.isSubmitting = false; });
    }

    /** Clears the session and returns to a blank Log In form. */
    handleLogout() {
        clearSession();
        this.mode = 'login';
        this.activeSection = 'dashboard';
        this.forgotPasswordSubmitted = false;
        showToast('You have been logged out.', 'info');
    }

    /**
     * Extracts a readable message from an AuraHandledException thrown by Apex.
     * @param {Object} error - the LWC imperative Apex error object
     * @returns {string} a user-facing error message
     */
    _extractError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Something went wrong. Please try again.';
    }

    // ───────────────────────── Dashboard sidebar ─────────────────────────

    /** Builds the sidebar navigation item array, marking the active one. */
    get navItems() {
        const items = [
            { key: 'dashboard', label: 'Overview', icon: 'grid' },
            { key: 'profile', label: 'My Profile', icon: 'user' },
            { key: 'orders', label: 'My Orders', icon: 'package' },
            { key: 'rewards', label: 'Rewards Wallet', icon: 'gift' },
            { key: 'addresses', label: 'Saved Addresses', icon: 'pin' },
            { key: 'wishlist', label: 'Wishlist', icon: 'heart' },
            { key: 'payments', label: 'Payment Methods', icon: 'card' },
            { key: 'settings', label: 'Account Settings', icon: 'settings' }
        ];
        return items.map((i) => ({
            ...i,
            className: i.key === this.activeSection ? 'tb-nav-btn tb-nav-btn-active' : 'tb-nav-btn'
        }));
    }

    /** Switches the active dashboard section — also used by the Dashboard's own summary tiles. */
    handleNavClick(event) { this.activeSection = event.currentTarget.dataset.key; }

    get isDashboardSection() { return this.activeSection === 'dashboard'; }
    get isProfileSection() { return this.activeSection === 'profile'; }
    get isOrdersSection() { return this.activeSection === 'orders'; }
    get isRewardsSection() { return this.activeSection === 'rewards'; }
    get isAddressesSection() { return this.activeSection === 'addresses'; }
    get isWishlistSection() { return this.activeSection === 'wishlist'; }
    get isPaymentsSection() { return this.activeSection === 'payments'; }
    get isSettingsSection() { return this.activeSection === 'settings'; }

    // ───────────────────────── Dashboard summary ─────────────────────────

    /** Total number of this shopper's orders, shown on the Dashboard's Orders tile. */
    get ordersCount() { return this.orders.length; }
    /** Total number of wishlisted products, shown on the Dashboard's Wishlist tile. */
    get wishlistCount() { return this.wishlistProducts.length; }
    /** Total number of saved addresses, shown on the Dashboard's Addresses tile. */
    get addressesCount() { return this.addresses.length; }

    /** The most recently placed order (orders are already newest-first from Apex), or null if none. */
    get recentOrder() { return this.orders.length > 0 ? this.orders[0] : null; }
    get hasRecentOrder() { return this.recentOrder !== null; }

    // ───────────────────────── Order History ─────────────────────────

    /** Loads this shopper's own orders, scoped to their logged-in email. */
    loadOrders() {
        this.isLoadingOrders = true;
        getOrdersByEmail({ email: this.session.email })
            .then((results) => {
                this.orders = results.map((order) => ({
                    ...order,
                    statusClass: order.status === 'Cancelled'
                        ? 'tb-order-status tb-order-status-cancelled'
                        : order.status === 'Activated'
                            ? 'tb-order-status tb-order-status-done'
                            : 'tb-order-status tb-order-status-processing',
                    // One-line summary of what's in the order for the card view —
                    // the first item's name, plus a "+N more" if there's more
                    // than one, rather than listing every line item on the card.
                    itemsSummary: this.buildItemsSummary(order.items),
                    canReturn: this.isWithinReturnWindow(order),
                    isRequestingReturn: false,
                    // The real, final charged amount (GST-inclusive, net of
                    // discount/loyalty) — never the raw pre-tax totalAmount,
                    // which would show a lower figure than what was actually
                    // paid. Falls back to totalAmount only for an order that
                    // predates the pricing engine.
                    displayAmount: order.amountPayable != null ? order.amountPayable : order.totalAmount
                }));
            })
            .catch(() => { this.orders = []; })
            .finally(() => { this.isLoadingOrders = false; });
    }

    /** True only for a Delivered order still inside the return window — the Apex side (requestReturn) re-checks this for real; this is just for showing/hiding the button. */
    isWithinReturnWindow(order) {
        if (order.deliveryStatus !== 'Delivered' || !order.deliveryDate) {
            return false;
        }
        const deliveredOn = new Date(order.deliveryDate);
        const windowEnd = new Date(deliveredOn.getTime() + RETURN_WINDOW_DAYS * 24 * 60 * 60 * 1000);
        return new Date() <= windowEnd;
    }

    /** Opens the inline return-reason form on an order card. */
    handleShowReturnForm(event) {
        const id = event.currentTarget.dataset.id;
        this.orders = this.orders.map((o) => (o.orderId === id ? { ...o, isRequestingReturn: true } : o));
    }

    /** Cancels the inline return-reason form without submitting. */
    handleCancelReturnForm(event) {
        const id = event.currentTarget.dataset.id;
        this.orders = this.orders.map((o) => (o.orderId === id ? { ...o, isRequestingReturn: false } : o));
    }

    /**
     * Submits the return request via CheckoutController.requestReturn.
     * Reads the reason straight from the textarea (same _readField
     * reasoning as the login/sign-up forms above) rather than a
     * tracked-and-rerendered value, since this order card re-renders on
     * every unrelated order-list change.
     */
    handleSubmitReturn(event) {
        const id = event.currentTarget.dataset.id;
        const textarea = this.template.querySelector(`textarea[data-id="${id}"][data-field="returnReason"]`);
        const reason = textarea ? textarea.value.trim() : '';
        if (!reason) {
            showToast('Please tell us why you\'d like to return this order.', 'error');
            return;
        }
        requestReturn({ orderId: id, reason })
            .then(() => {
                showToast('Return request submitted. We\'ll email you once it\'s processed.', 'success');
                this.loadOrders();
            })
            .catch((error) => { showToast(this._extractError(error), 'error'); });
    }

    /**
     * Builds the "+N more" one-line item summary shown on an order card.
     * @param {Array} items - OrderLineSummary array from Apex
     * @returns {string}
     */
    buildItemsSummary(items) {
        if (!items || items.length === 0) { return ''; }
        const first = items[0].productName;
        return items.length > 1 ? `${first} +${items.length - 1} more` : first;
    }

    /** True once at least one order has loaded for this shopper. */
    get hasOrders() { return this.orders.length > 0; }

    /** True once at least one loyalty transaction has loaded for this shopper. */
    get hasLoyaltyTransactions() { return this.loyaltyWallet.transactions && this.loyaltyWallet.transactions.length > 0; }

    /**
     * Navigates to the Order Confirmation page for the clicked order.
     * @param {Event} event - currentTarget.dataset.id contains the Order Salesforce Id
     */
    handleViewOrder(event) {
        this[NavigationMixin.Navigate](getOrderConfirmationRef(event.currentTarget.dataset.id));
    }

    /**
     * Navigates to the Order Tracking page for the clicked order.
     * @param {Event} event - currentTarget.dataset.id contains the Order Salesforce Id
     */
    handleTrackOrder(event) {
        this[NavigationMixin.Navigate](getOrderTrackingRef(event.currentTarget.dataset.id));
    }

    // ───────────────────────── Saved Addresses ─────────────────────────

    /** True once at least one address has been saved. */
    get hasAddresses() { return this.addresses.length > 0; }

    /**
     * Addresses with a "default" flag added for display — the first saved
     * address is treated as the default one (a simple, non-persisted
     * convention; there's no real settable default yet). Computed fresh
     * every time rather than stored, so it stays correct after add/delete.
     */
    get addressesDisplay() {
        return this.addresses.map((a, i) => ({ ...a, isDefault: i === 0 }));
    }

    /**
     * Puts an address card into edit mode.
     * @param {Event} event - currentTarget.dataset.id contains the address id
     */
    handleEditAddress(event) {
        const id = event.currentTarget.dataset.id;
        this.addresses = this.addresses.map((a) => (a.id === id ? { ...a, editing: true } : a));
    }

    /**
     * Persists the address edit onto the shopper's own Account
     * (Saved_Address__c) and exits edit mode. A locally-generated id (from
     * handleAddAddress, e.g. "addr_1234") is not a real Salesforce record
     * yet, so it's sent as a null addressId — the server creates a new
     * record and the real id it returns replaces the temporary one.
     * @param {Event} event - currentTarget.dataset.id contains the address id
     */
    handleDoneEditAddress(event) {
        const id = event.currentTarget.dataset.id;
        const addr = this.addresses.find((a) => a.id === id);
        if (!addr) return;
        if (!addr.line1 || !addr.city) {
            showToast('Please fill in the address and city.', 'error');
            return;
        }
        if (addr.phone && !PHONE_PATTERN.test(addr.phone.trim())) {
            showToast(PHONE_ERROR, 'error');
            return;
        }

        const isNew = id.startsWith('addr_');
        saveMyAddress({
            accountId: this.session.id,
            addressId: isNew ? null : id,
            line1: addr.line1,
            city: addr.city,
            phone: addr.phone
        })
            .then((savedId) => {
                this.addresses = this.addresses.map((a) => (a.id === id ? { ...a, id: savedId, editing: false } : a));
                showToast('Address saved.', 'success');
            })
            .catch((error) => {
                showToast(this._extractError(error) || 'Could not save that address.', 'error');
            });
    }

    /**
     * Updates a single field within an address while it is being edited.
     * Phone is sanitized live (digits only, capped at 10) the same way every
     * other phone field on the site is.
     * @param {Event} event - currentTarget.dataset.id and dataset.field identify the target
     */
    handleAddressInput(event) {
        const { id, field } = event.currentTarget.dataset;
        let value = event.target.value;
        if (field === 'phone') {
            value = sanitizePhoneInput(value);
            event.target.value = value;
        }
        this.addresses = this.addresses.map((a) => (a.id === id ? { ...a, [field]: value } : a));
    }

    /**
     * Removes a saved address from the shopper's own Account and the
     * displayed list. A still-unsaved local row (temporary "addr_" id) has
     * nothing on the server yet, so it's just dropped from the list.
     * @param {Event} event - currentTarget.dataset.id contains the address id
     */
    handleDeleteAddress(event) {
        const id = event.currentTarget.dataset.id;
        this.addresses = this.addresses.filter((a) => a.id !== id);
        if (id.startsWith('addr_')) return;
        deleteMyAddress({ accountId: this.session.id, addressId: id })
            .then(() => showToast('Address removed.', 'info'))
            .catch((error) => showToast(this._extractError(error) || 'Could not remove that address.', 'error'));
    }

    /** Adds a new blank address card in edit mode — persisted once "Done" is clicked. */
    handleAddAddress() {
        const id = `addr_${Date.now()}`;
        this.addresses = [...this.addresses, { id, line1: '', city: '', phone: '', editing: true }];
    }

    // ───────────────────────── Wishlist ─────────────────────────

    /** Returns full product objects (with a resolved image) for every wishlisted product id. */
    get wishlistProducts() {
        // eslint-disable-next-line no-unused-expressions
        this.wishlistVersion; // declares reactivity on this tracked counter
        return getWishlist()
            .map((id) => findById(this.allProducts, id))
            .filter((p) => p !== null)
            .map((p) => ({ ...p, imageUrl: getProductImages(p.productName)[0] }));
    }

    /** True when the wishlist has at least one product. */
    get hasWishlistItems() { return this.wishlistProducts.length > 0; }

    /**
     * Removes a product from the wishlist.
     * @param {Event} event - currentTarget.dataset.id contains the product id
     */
    handleRemoveWishlistItem(event) {
        toggleWishlist(event.currentTarget.dataset.id);
        this.wishlistVersion += 1;
        showToast('Removed from wishlist.', 'info');
    }

    /**
     * Navigates to the Product Detail page for a wishlisted product.
     * @param {Event} event - currentTarget.dataset.id contains the product id
     */
    handleViewWishlistProduct(event) {
        this[NavigationMixin.Navigate](getProductRef(event.currentTarget.dataset.id));
    }

    /**
     * Adds a wishlisted product to the cart directly from its card.
     * @param {Event} event - currentTarget.dataset.id contains the product id
     */
    handleAddWishlistToCart(event) {
        const id = event.currentTarget.dataset.id;
        const product = findById(this.allProducts, id);
        if (!product) { return; }
        addItem(product, 1);
        showToast(`${product.productName} added to cart!`, 'success');
    }

    // ───────────────────────── Account Settings ─────────────────────────

    /**
     * Updates a notification setting when its checkbox changes.
     * @param {Event} event - target.dataset.field and target.checked
     */
    handleSettingChange(event) {
        const field = event.target.dataset.field;
        this.settings = { ...this.settings, [field]: event.target.checked };
    }

    /** Persists notification settings via accountSettingsService. */
    handleSaveSettings() {
        saveSettings(this.settings);
        showToast('Settings saved.', 'success');
    }
}
