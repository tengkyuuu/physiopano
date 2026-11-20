import preset from '../design-system/tailwind.preset.js'

/** @type {import('tailwindcss').Config} */
export default {
  presets: [preset],
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      // Legacy names used across the existing components, resolved to Wayfinding tokens.
      colors: {
        card: 'rgb(var(--pp-surface-rgb) / <alpha-value>)',
        cardAlt: 'rgb(var(--pp-surface-sunk-rgb) / <alpha-value>)',
        lineDim: 'rgb(var(--pp-line-rgb) / <alpha-value>)',
        emerald: {
          DEFAULT: 'rgb(var(--pp-brand-rgb) / <alpha-value>)',
          dim: 'rgb(var(--pp-brand-rgb) / <alpha-value>)',
        },
        teal: 'rgb(var(--pp-brand-rgb) / <alpha-value>)',
        mint: 'rgb(var(--pp-brand-rgb) / <alpha-value>)',
        gold: 'rgb(var(--pp-route-3-rgb) / <alpha-value>)',
        danger: 'rgb(var(--pp-crisis-rgb) / <alpha-value>)',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-14px)' },
        },
        floatSlow: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-8px)' },
        },
        pulseRing: {
          '0%': { transform: 'scale(1)', opacity: '0.6' },
          '100%': { transform: 'scale(2.4)', opacity: '0' },
        },
        ecg: {
          '0%': { strokeDashoffset: '1000' },
          '100%': { strokeDashoffset: '0' },
        },
        scan: {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(200%)' },
        },
        marquee: {
          '0%': { transform: 'translateX(0)' },
          '100%': { transform: 'translateX(-50%)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        blob: {
          '0%, 100%': { transform: 'translate(0, 0) scale(1)' },
          '33%': { transform: 'translate(30px, -40px) scale(1.08)' },
          '66%': { transform: 'translate(-25px, 25px) scale(0.95)' },
        },
        aurora1: {
          '0%, 100%': { transform: 'translate(-6%, -4%) scale(1)' },
          '33%': { transform: 'translate(5%, 4%) scale(1.12)' },
          '66%': { transform: 'translate(-3%, 7%) scale(0.94)' },
        },
        aurora2: {
          '0%, 100%': { transform: 'translate(4%, 5%) scale(1.05)' },
          '33%': { transform: 'translate(-5%, -3%) scale(0.92)' },
          '66%': { transform: 'translate(3%, -6%) scale(1.1)' },
        },
        spinSlow: {
          '0%': { transform: 'rotate(0deg)' },
          '100%': { transform: 'rotate(360deg)' },
        },
      },
      animation: {
        float: 'float 6s ease-in-out infinite',
        floatSlow: 'floatSlow 8s ease-in-out infinite',
        pulseRing: 'pulseRing 2.2s cubic-bezier(0.4, 0, 0.2, 1) infinite',
        ecg: 'ecg 3.2s linear infinite',
        scan: 'scan 3.5s ease-in-out infinite',
        marquee: 'marquee 32s linear infinite',
        shimmer: 'shimmer 3s linear infinite',
        blob: 'blob 14s ease-in-out infinite',
        aurora1: 'aurora1 24s ease-in-out infinite',
        aurora2: 'aurora2 32s ease-in-out infinite',
        spinSlow: 'spinSlow 70s linear infinite',
      },
    },
  },
  plugins: [],
}
