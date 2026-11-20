import { lazy, Suspense, useEffect, useState } from 'react'
import {
  onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword,
  sendPasswordResetEmail, updateProfile, signOut, User,
} from 'firebase/auth'
import { auth, hasFirebaseConfig } from './firebase'
import { Landing } from './components/Landing'
import { AuthScreen } from './components/AuthScreen'

const Dashboard = lazy(() => import('./components/Dashboard').then(module => ({ default: module.Dashboard })))

async function hasConsoleAccess(user: User) {
  const token = await user.getIdTokenResult()
  return token.claims.navigator === true
}

export default function App() {
  const [user, setUser] = useState<User | null>(null)
  const [route, setRoute] = useState(() => window.location.hash)

  useEffect(() => {
    if (!hasFirebaseConfig) return
    let active = true
    const unsub = onAuthStateChanged(auth, async u => {
      if (!u) { if (active) setUser(null); return }
      const allowed = await hasConsoleAccess(u).catch(() => false)
      if (active && auth.currentUser === u) setUser(allowed ? u : null)
    })
    return () => { active = false; unsub() }
  }, [])

  // Keep the URL hash in sync so /#/login is shareable.
  useEffect(() => {
    const onHash = () => setRoute(window.location.hash)
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  function openAuth() {
    window.location.hash = '#/login'
  }

  function closeAuth() {
    window.location.hash = ''
  }

  async function handleSignIn(email: string, password: string) {
    const { user: signedInUser } = await signInWithEmailAndPassword(auth, email, password)
    if (await hasConsoleAccess(signedInUser).catch(() => false)) return
    await signOut(auth)
    throw new Error('Use a navigator account to sign in to the console.')
  }

  async function handleSignUp(name: string, email: string, password: string) {
    const cred = await createUserWithEmailAndPassword(auth, email, password)
    if (name) await updateProfile(cred.user, { displayName: name })
    // Participant accounts log in via the mobile app, not this dashboard.
    await signOut(auth)
  }

  async function handleReset(email: string) {
    await sendPasswordResetEmail(auth, email)
  }

  // The landing and auth screens render immediately while Firebase resolves
  // the session in the background; the dashboard swaps in once it does.
  if (route === '#/demo' || user) {
    return <Suspense fallback={<main className="desk-loading" role="status">Opening the care console…</main>}>
      {route === '#/demo'
        ? <Dashboard key="public-demo" previewOnly onExitPreview={closeAuth} />
        : <Dashboard key={user!.uid} />}
    </Suspense>
  }

  if (hasFirebaseConfig && (route === '#/login' || route === '#/signup')) {
    return (
      <AuthScreen
        key={route}
        onSignIn={handleSignIn}
        onSignUp={handleSignUp}
        onReset={handleReset}
        onBack={closeAuth}
        initialMode={window.location.hash === '#/signup' ? 'signup' : 'signin'}
      />
    )
  }

  return <Landing onLogin={hasFirebaseConfig ? openAuth : undefined} />
}
