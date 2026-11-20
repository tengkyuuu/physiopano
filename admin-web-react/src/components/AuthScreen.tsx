import { useState } from 'react'
import { ArrowLeft, ArrowRight, Eye, EyeOff, LockKeyhole } from 'lucide-react'
import { ConsoleBrand, Pano } from './ConsoleBrand'

type Mode = 'signin' | 'signup' | 'reset'

interface AuthScreenProps {
  onSignIn: (email: string, password: string) => Promise<void>
  onSignUp: (name: string, email: string, password: string) => Promise<void>
  onReset: (email: string) => Promise<void>
  onBack: () => void
  initialMode?: 'signin' | 'signup'
}

// Map raw Firebase error codes to friendly copy.
function friendlyError(message: string): string {
  if (
    message.includes('auth/invalid-credential') ||
    message.includes('auth/wrong-password') ||
    message.includes('auth/user-not-found')
  )
    return 'Incorrect email or password. Please try again.'
  if (message.includes('auth/email-already-in-use'))
    return 'An account with this email already exists. Try signing in instead.'
  if (message.includes('auth/weak-password')) return 'Password is too weak — use at least 6 characters.'
  if (message.includes('auth/invalid-email')) return "That email address doesn't look valid."
  if (message.includes('auth/too-many-requests'))
    return 'Too many attempts. Please wait a moment and try again.'
  if (message.includes('auth/network-request-failed'))
    return 'Network error — check your connection and try again.'
  return message
}

export function AuthScreen({
  onSignIn,
  onSignUp,
  onReset,
  onBack,
  initialMode = 'signin',
}: AuthScreenProps) {
  const [mode, setMode] = useState<Mode>(initialMode)
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [showPw, setShowPw] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [loading, setLoading] = useState(false)

  function switchMode(m: Mode) {
    setMode(m)
    setError('')
    setSuccess('')
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setSuccess('')

    if (mode === 'signup') {
      if (password !== confirm) {
        setError("Passwords don't match.")
        return
      }
      if (password.length < 6) {
        setError('Password must be at least 6 characters.')
        return
      }
    }

    setLoading(true)
    try {
      if (mode === 'signin') {
        await onSignIn(email.trim(), password)
      } else if (mode === 'signup') {
        await onSignUp(name.trim(), email.trim(), password)
        setSuccess(
          'Account created! Sign in on the PHYSIOPAÑO mobile app to start monitoring. The care console requires a navigator or research administrator account.',
        )
        setName('')
        setPassword('')
        setConfirm('')
      } else {
        await onReset(email.trim())
        setSuccess('Password reset email sent — check your inbox.')
        setMode('signin')
      }
    } catch (err: unknown) {
      setError(friendlyError(err instanceof Error ? err.message : 'Something went wrong'))
    } finally {
      setLoading(false)
    }
  }

  const titles = {
    signin: ['Sign in', 'Use your navigator or research administrator account.'],
    signup: ['Create a participant account', 'Use this account in the PHYSIOPAÑO mobile app.'],
    reset: ['Reset your password', 'Enter your email and we’ll send a password reset link.'],
  }
  return (
    <div className="desk-public auth-page">
      <header className="public-head">
        <button onClick={onBack} aria-label="Physiopaño home">
          <ConsoleBrand />
        </button>
        <button className="text-link" onClick={onBack}>
          <ArrowLeft size={16} /> Back to home
        </button>
      </header>
      <main className="auth-layout">
        <section className="auth-welcome">
          <Pano pose="greeting" />
          <p className="desk-kicker">PHYSIOPAÑO</p>
          <h2>
            Care navigator <br />
            console.
          </h2>
          <p>One place to review requests and coordinate follow-up.</p>
        </section>
        <section className="auth-form">
          <LockKeyhole className="form-mark" size={23} />
          <h1>{titles[mode][0]}</h1>
          <p>{titles[mode][1]}</p>
          <form onSubmit={handleSubmit}>
            {mode === 'signup' && (
              <label>
                Full name
                <input
                  autoComplete="name"
                  required
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </label>
            )}
            <label>
              Email address
              <input
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </label>
            {mode !== 'reset' && (
              <div className="password-field">
                <label htmlFor="account-password">Password</label>
                <div>
                  <input
                    id="account-password"
                    type={showPw ? 'text' : 'password'}
                    required
                    autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                  />
                  <button
                    type="button"
                    aria-label={showPw ? 'Hide password' : 'Show password'}
                    aria-pressed={showPw}
                    onClick={() => setShowPw(!showPw)}
                  >
                    {showPw ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
              </div>
            )}
            {mode === 'signup' && (
              <label>
                Confirm password
                <input
                  type={showPw ? 'text' : 'password'}
                  required
                  autoComplete="new-password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                />
              </label>
            )}
            {mode === 'signin' && (
              <button type="button" className="text-link forgot" onClick={() => switchMode('reset')}>
                Forgot password?
              </button>
            )}
            {error && (
              <p role="alert" className="form-feedback">
                {error}
              </p>
            )}
            {success && (
              <p role="status" className="form-feedback">
                {success}
              </p>
            )}
            <button type="submit" disabled={loading} className="desk-btn primary">
              {loading
                ? 'Please wait…'
                : mode === 'reset'
                  ? 'Send reset link'
                  : mode === 'signup'
                    ? 'Create account'
                    : 'Sign in'}{' '}
              <ArrowRight size={16} />
            </button>
          </form>
          <div className="auth-secondary">
            {mode === 'signin' ? (
              <>
                <span>Using the mobile app?</span>{' '}
                <button className="text-link" onClick={() => switchMode('signup')}>
                  Create a participant account
                </button>
              </>
            ) : (
              <button className="text-link" onClick={() => switchMode('signin')}>
                <ArrowLeft size={15} /> Back to sign in
              </button>
            )}
          </div>
        </section>
      </main>
    </div>
  )
}
