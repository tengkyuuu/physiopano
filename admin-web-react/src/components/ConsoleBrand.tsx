import calm from '../assets/pano-calm.webp'
import wave from '../assets/pano-wave.webp'
import greeting from '../assets/pano-wave.gif'
import sleepy from '../assets/pano-sleepy.webp'

export function Pano({ pose = 'calm' }: { pose?: 'calm' | 'greeting' | 'sleepy' }) {
  if (pose === 'greeting')
    return (
      <picture className="desk-pano">
        <source media="(prefers-reduced-motion: reduce)" srcSet={wave} />
        <img src={greeting} alt="" width="64" height="64" />
      </picture>
    )
  return (
    <img className="desk-pano" src={pose === 'sleepy' ? sleepy : calm} alt="" width="64" height="64" />
  )
}

export function ConsoleBrand() {
  return (
    <span className="desk-brand">
      <span className="brand-tile">
        <Pano />
      </span>
      <span>PHYSIOPAÑO</span>
    </span>
  )
}
