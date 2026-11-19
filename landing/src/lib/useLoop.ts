import { useInView, useReducedMotion } from 'motion/react'
import { useEffect, useRef, useState } from 'react'

/**
 * Steps through `durations` (ms per phase) forever while the element is on screen.
 * With reduced motion it stays on `stillPhase`.
 */
export function useLoop(durations: number[], stillPhase = 0) {
  const ref = useRef<HTMLDivElement>(null)
  const isInView = useInView(ref, { amount: 0.35 })
  const prefersStill = useReducedMotion()
  const [phase, setPhase] = useState(0)

  useEffect(() => {
    if (!isInView || prefersStill) return

    const timer = setTimeout(() => setPhase((current) => (current + 1) % durations.length), durations[phase])

    return () => clearTimeout(timer)
  }, [isInView, prefersStill, phase, durations])

  return {
    ref,
    phase: prefersStill ? stillPhase : phase,
  }
}
