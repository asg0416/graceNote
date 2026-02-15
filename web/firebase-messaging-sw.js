// Firebase Messaging Service Worker
// 백그라운드 푸시 알림 수신용 (data-only + notification 하위 호환)

importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: "AIzaSyAaMrzkmU6PLr0xBRRt_fgQT_ZniKOQ8Yc",
    authDomain: "gracenote-5992e.firebaseapp.com",
    projectId: "gracenote-5992e",
    storageBucket: "gracenote-5992e.firebasestorage.app",
    messagingSenderId: "934640733901",
    appId: "1:934640733901:web:eff49dfeae3dea84cbe384"
});

const messaging = firebase.messaging();

// 백그라운드 메시지 핸들러
// data-only 메시지 우선, notification fallback 지원
messaging.onBackgroundMessage((payload) => {
    console.log('[SW] Background message:', payload);

    const data = payload.data || {};
    const notif = payload.notification || {};

    // data 필드 우선, notification fallback
    const title = data.title || notif.title || 'Grace Note';
    const body = data.body || notif.body || '';
    const tag = data.tag || 'grace-note-default';
    const link = data.link || '/';

    return self.registration.showNotification(title, {
        body,
        icon: '/icons/Icon-192.png',
        badge: '/icons/notification-logo-icon.png',
        tag,
        renotify: true,
        data: { link },
    });
});

// 알림 클릭 핸들러
self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    const link = event.notification.data?.link || '/';

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
            for (const client of windowClients) {
                if (client.url.includes(self.location.origin) && 'focus' in client) {
                    return client.focus();
                }
            }
            return clients.openWindow(link);
        })
    );
});
