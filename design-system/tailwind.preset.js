/**
 * PHYSIOPAÑO Wayfinding — Tailwind preset for admin-web-react (care console).
 * Usage in admin-web-react/tailwind.config.js:
 *   import preset from '../design-system/tailwind.preset.js'
 *   export default { presets: [preset], content: [...] }
 * and import '../../design-system/tokens.css' in src/index.css.
 * Colours resolve to CSS channel variables, so light/dark follow tokens.css
 * and opacity modifiers (bg-brand/10) work.
 */
const v = (name) => `rgb(var(--pp-${name}-rgb) / <alpha-value>)`;

export default {
  darkMode: ['class', '[data-theme="dark"]'],
  theme: {
    extend: {
      colors: {
        ground: v('ground'),
        surface: { DEFAULT: v('surface'), sunk: v('surface-sunk') },
        panel: { DEFAULT: v('panel'), on: v('on-panel') },
        ink: { DEFAULT: v('ink'), muted: v('ink-muted'), quiet: v('ink-quiet') },
        line: v('line'),
        focus: v('focus'),
        brand: { DEFAULT: v('brand'), on: v('on-brand'), soft: v('brand-soft') },
        route: {
          1: v('route-1'), 2: v('route-2'), 3: v('route-3'), 4: v('route-4'), 5: v('route-5'),
        },
        crisis: { DEFAULT: v('crisis'), on: v('on-crisis') },
      },
      fontFamily: {
        sans: ['Plus Jakarta Sans', 'system-ui', 'sans-serif'],
        display: ['Plus Jakarta Sans', 'system-ui', 'sans-serif'],
        ar: ['Noto Kufi Arabic', 'Plus Jakarta Sans', 'system-ui', 'sans-serif'],
        data: ['JetBrains Mono', 'ui-monospace', 'monospace'],
        mono: ['JetBrains Mono', 'ui-monospace', 'monospace'],
      },
      fontSize: {
        eyebrow: ['12px', { lineHeight: '16px', letterSpacing: '0.16em', fontWeight: '600' }],
        caption: ['12px', { lineHeight: '16px', letterSpacing: '0.04em', fontWeight: '600' }],
        small: ['14px', '20px'],
        body: ['16px', '24px'],
        lead: ['18px', { lineHeight: '28px', fontWeight: '400' }],
        title: ['22px', { lineHeight: '28px', fontWeight: '700', letterSpacing: '-0.02em' }],
        heading: ['30px', { lineHeight: '34px', fontWeight: '800', letterSpacing: '-0.035em' }],
        display: ['44px', { lineHeight: '46px', fontWeight: '800', letterSpacing: '-0.04em' }],
        sign: ['64px', { lineHeight: '64px', fontWeight: '800', letterSpacing: '-0.045em' }],
      },
      borderRadius: { control: '18px', panel: '28px', sheet: '36px', pill: '999px' },
      boxShadow: {
        raised: 'var(--pp-shadow-raised)',
        overlay: 'var(--pp-shadow-overlay)',
        inset: 'var(--pp-shadow-inset)',
        brand: 'var(--pp-shadow-brand)',
      },
      transitionTimingFunction: { pp: 'cubic-bezier(0.16, 1, 0.3, 1)', spring: 'cubic-bezier(0.34, 1.4, 0.64, 1)' },
      transitionDuration: { fast: '160ms', base: '280ms', slow: '520ms' },
      minHeight: { touch: '48px' },
      minWidth: { touch: '48px' },
    },
  },
};
