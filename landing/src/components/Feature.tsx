import { motion } from 'motion/react'
import type { ReactNode } from 'react'

const EASE = [0.22, 1, 0.36, 1] as const

/** A feature block: copy on one side, a live demo on the other. */
export function Feature({
  id,
  eyebrow,
  eyebrowColor,
  title,
  children,
  demo,
  isReversed = false,
}: {
  id?: string
  eyebrow: string
  eyebrowColor: string
  title: ReactNode
  children: ReactNode
  demo: ReactNode
  isReversed?: boolean
}) {
  return (
    <section id={id} className="scroll-mt-24 px-4 py-20 sm:py-28">
      <div
        className={`mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:gap-16 ${
          isReversed ? 'lg:[&>*:first-child]:order-2' : ''
        }`}
      >
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.4 }}
          transition={{ duration: 0.9, ease: EASE }}
        >
          <p className={`mb-4 text-sm font-medium ${eyebrowColor}`}>{eyebrow}</p>
          <h2 className="text-gradient text-4xl font-semibold tracking-[-0.03em] sm:text-5xl">{title}</h2>
          <div className="mt-5 space-y-4 text-lg leading-relaxed text-white/55">{children}</div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 40, scale: 0.97 }}
          whileInView={{ opacity: 1, y: 0, scale: 1 }}
          viewport={{ once: true, amount: 0.3 }}
          transition={{ duration: 1, ease: EASE, delay: 0.1 }}
        >
          {demo}
        </motion.div>
      </div>
    </section>
  )
}
