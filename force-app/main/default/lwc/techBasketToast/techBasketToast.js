import { LightningElement, track } from 'lwc';
import { subscribe } from 'c/toastService';

/** Auto-dismiss delay in milliseconds. */
const AUTO_DISMISS_MS = 3500;
/** Icon character for each toast variant. */
const ICONS = { success: '✓', error: '✕', warning: '⚠', info: 'ℹ' };

/**
 * TechBasketToast — global toast notification renderer.
 * Mounted once at the app level; subscribes to toastService and renders
 * each toast as a slide-in card with an icon, progress bar, and close button.
 * Toasts auto-dismiss after AUTO_DISMISS_MS milliseconds.
 */
export default class TechBasketToast extends LightningElement {
    /** Array of active toast objects currently displayed on screen. */
    @track toasts = [];
    /** Unsubscribe function returned by toastService.subscribe — called on disconnect. */
    unsubscribe;

    /**
     * Lifecycle: subscribes to toastService so any component can trigger a toast
     * by calling showToast() without needing a direct reference to this component.
     * Each incoming toast is enriched with an icon and CSS class, then auto-dismissed.
     */
    connectedCallback() {
        this.unsubscribe = subscribe((toast) => {
            const t = {
                ...toast,
                icon: ICONS[toast.variant] || ICONS.info,
                className: `tb-toast tb-toast-${toast.variant}`
            };
            this.toasts = [...this.toasts, t];
            // Schedule auto-dismiss after the display duration.
            setTimeout(() => this.dismiss(toast.id), AUTO_DISMISS_MS);
        });
    }

    /**
     * Lifecycle: cleans up the toastService subscription to prevent memory leaks.
     */
    disconnectedCallback() {
        if (this.unsubscribe) this.unsubscribe();
    }

    /**
     * Handles the close button click — dismisses the toast immediately.
     * @param {Event} event - currentTarget.dataset.id contains the toast id
     */
    handleClose(event) {
        this.dismiss(Number(event.currentTarget.dataset.id));
    }

    /**
     * Removes a toast from the active list by its id.
     * Called both by the close button and the auto-dismiss timer.
     * @param {number} id - unique toast id assigned by toastService
     */
    dismiss(id) {
        this.toasts = this.toasts.filter((t) => t.id !== id);
    }
}
