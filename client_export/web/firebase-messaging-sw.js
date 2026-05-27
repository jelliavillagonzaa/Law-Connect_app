/* Firebase Cloud Messaging — service worker for Flutter Web (must be real JS, not SPA fallback). */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCPcq-fpSxaLnnq4T5s_19vem0fIVuI11Q',
  authDomain: 'jurislink-app.firebaseapp.com',
  projectId: 'jurislink-app',
  storageBucket: 'jurislink-app.firebasestorage.app',
  messagingSenderId: '969711743833',
  appId: '1:969711743833:web:35a746c1c4c68c9e1e1248',
  measurementId: 'G-S7G14B5T35',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background message', payload);
});
