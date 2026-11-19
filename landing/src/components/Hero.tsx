import { motion, useScroll, useTransform } from 'motion/react'
import { useRef } from 'react'

const EASE = [0.22, 1, 0.36, 1] as const

const HEADLINE = ['Terminals', 'that', 'never', 'close.']

export function Hero() {
  const ref = useRef<HTMLElement>(null)
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] })
  const tilt = useTransform(scrollYProgress, [0, 0.6], [14, 0])
  const scale = useTransform(scrollYProgress, [0, 0.6], [0.92, 1])

  return (
    <section ref={ref} id="top" className="relative px-4 pt-36 pb-24 sm:pt-44">
      <Glow />

      <div className="relative mx-auto max-w-4xl text-center">
        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: EASE }}
          className="mb-6 inline-flex items-center gap-2 rounded-full border border-line px-3 py-1 text-xs text-white/60"
        >
          <span className="size-1.5 rounded-full bg-mint" />A native macOS terminal, built on Ghostty
        </motion.p>

        <h1 className="text-5xl font-semibold tracking-[-0.04em] sm:text-7xl md:text-8xl">
          {HEADLINE.map((word, index) => (
            <motion.span
              key={word}
              initial={{ opacity: 0, y: 28, filter: 'blur(10px)' }}
              animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
              transition={{ duration: 0.9, delay: 0.1 + index * 0.08, ease: EASE }}
              className="text-gradient inline-block pr-[0.22em]"
            >
              {word}
            </motion.span>
          ))}
        </h1>

        <motion.p
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.5, ease: EASE }}
          className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-white/55 sm:text-xl"
        >
          Every pane in Drako is a persistent session. Quit the app, close the lid, lose the Wi‑Fi. Open it again and
          every tab, screen and scrollback is right where you left it, on every machine.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.65, ease: EASE }}
          className="mt-9 flex flex-wrap items-center justify-center gap-3"
        >
          <a
            href="#download"
            className="rounded-full bg-white px-6 py-3 font-medium text-black transition-transform hover:scale-[1.03] active:scale-95"
          >
            Download for macOS
          </a>
          <a href="#sessions" className="rounded-full px-6 py-3 text-white/70 transition-colors hover:text-white">
            See how it works →
          </a>
        </motion.div>
      </div>

      <div className="relative mx-auto mt-20 max-w-5xl [perspective:1600px]">
        <motion.div
          initial={{ opacity: 0, y: 60 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 1.1, delay: 0.7, ease: EASE }}
          style={{ rotateX: tilt, scale }}
          className="origin-top"
        >
          <img
            src="/shots/drako-window.webp"
            alt="The Drako window: a sidebar with machines, tabs and pane layouts next to a live log stream"
            width={2400}
            height={1500}
            fetchPriority="high"
            className="w-full rounded-2xl shadow-2xl ring-1 shadow-black/60 ring-white/10"
          />
        </motion.div>
      </div>
    </section>
  )
}

function Glow() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-x-0 top-0 -z-0 h-[900px] overflow-hidden">
      <motion.div
        className="absolute top-40 left-1/2 h-[520px] w-[820px] -translate-x-1/2 rounded-full bg-mint/12 blur-[120px]"
        animate={{ scale: [1, 1.12, 1], opacity: [0.6, 0.9, 0.6] }}
        transition={{ duration: 9, repeat: Infinity, ease: 'easeInOut' }}
      />
      <motion.div
        className="absolute top-72 left-[30%] h-[360px] w-[420px] rounded-full bg-lavender/10 blur-[110px]"
        animate={{ x: [0, 60, 0] }}
        transition={{ duration: 12, repeat: Infinity, ease: 'easeInOut' }}
      />
    </div>
  )
}
