import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";
import { getAuth } from "firebase/auth";

const env = import.meta.env;
export const hasFirebaseConfig = Boolean(
  env.VITE_FIREBASE_API_KEY && env.VITE_FIREBASE_AUTH_DOMAIN &&
  env.VITE_FIREBASE_PROJECT_ID && env.VITE_FIREBASE_APP_ID,
);

const app = initializeApp(hasFirebaseConfig ? {
  apiKey: env.VITE_FIREBASE_API_KEY,
  authDomain: env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: env.VITE_FIREBASE_APP_ID,
} : {
  // The synthetic preview never signs in or reads from Firestore.
  apiKey: "demo-api-key",
  projectId: "demo-physiopano",
});

export const db = getFirestore(app);
export const auth = getAuth(app);
