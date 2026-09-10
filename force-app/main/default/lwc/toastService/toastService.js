const listeners = new Set();

// Publishes a toast message; techBasketToast (mounted once, globally) renders it.
export function showToast(message, variant) {
    const toast = { id: Date.now() + Math.random(), message, variant: variant || 'success' };
    listeners.forEach((cb) => cb(toast));
}

// Lets techBasketToast subscribe to published messages. Returns an unsubscribe function.
export function subscribe(callback) {
    listeners.add(callback);
    return () => listeners.delete(callback);
}
