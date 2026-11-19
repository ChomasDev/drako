import { motion } from 'motion/react'

import { FAQ, INSTALL_STEPS } from '../lib/content'
import { DOWNLOAD_URL } from '../lib/site'

const EASE = [0.22, 1, 0.36, 1] as const

const PILLARS = [
  {
    title: 'GPU rendered',
    text: 'Ghostty’s Metal renderer. Smooth at 120 Hz, even with a wall of logs.',
    color: 'text-mint',
  },
  { title: 'Truly native', text: 'AppKit and SwiftUI with Liquid Glass. No Electron, no web view.', color: 'text-sky' },
  {
    title: 'Your config',
    text: 'Reads your Ghostty keybindings, fonts and settings as they are.',
    color: 'text-lavender',
  },
  {
    title: 'One ssh per host',
    text: 'Shared connections: new remote panes open in milliseconds.',
    color: 'text-peach',
  },
]

export function Pillars() {
  return (
    <section aria-labelledby="pillars-title" className="px-4 py-20 sm:py-28">
      <div className="mx-auto max-w-6xl">
        <h2
          id="pillars-title"
          className="text-gradient mx-auto max-w-3xl text-center text-4xl font-semibold tracking-[-0.03em] sm:text-5xl"
        >
          Everything you love about Ghostty. Now it remembers.
        </h2>
        <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {PILLARS.map((pillar, index) => (
            <motion.article
              key={pillar.title}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, amount: 0.5 }}
              transition={{ duration: 0.7, delay: index * 0.08, ease: EASE }}
              whileHover={{ y: -4 }}
              className="rounded-3xl border border-line bg-white/[0.025] p-6"
            >
              <h3 className={`font-medium ${pillar.color}`}>{pillar.title}</h3>
              <p className="mt-2 leading-relaxed text-white/55">{pillar.text}</p>
            </motion.article>
          ))}
        </div>
      </div>
    </section>
  )
}

export function Install() {
  return (
    <section id="download" aria-labelledby="download-title" className="scroll-mt-24 px-4 py-20 sm:py-28">
      <motion.div
        initial={{ opacity: 0, y: 30 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, amount: 0.4 }}
        transition={{ duration: 0.9, ease: EASE }}
        className="relative mx-auto max-w-3xl overflow-hidden rounded-[2rem] border border-line bg-gradient-to-b from-mint/[0.07] to-transparent p-8 text-center sm:p-14"
      >
        <img src="/icon.png" alt="Drako app icon" width={96} height={96} loading="lazy" className="mx-auto size-24" />
        <h2 id="download-title" className="text-gradient mt-6 text-4xl font-semibold tracking-[-0.03em] sm:text-5xl">
          Up and running in a minute.
        </h2>
        <p className="mt-4 text-lg text-white/55">
          For macOS 26 or later. Remote hosts only need the drako binary and ssh keys.
        </p>

        <pre className="mx-auto mt-8 max-w-xl overflow-x-auto rounded-2xl bg-black/40 p-5 text-left font-mono text-sm leading-7 ring-1 ring-white/8">
          {INSTALL_STEPS.map((step) => (
            <code key={step.command} className="block">
              <span className="text-white/30"># {step.comment}</span>
              {'\n'}
              <span className="text-mint">❯ </span>
              {step.command}
            </code>
          ))}
        </pre>

        <a
          href={DOWNLOAD_URL}
          className="mt-8 inline-block rounded-full bg-white px-6 py-3 font-medium text-black transition-transform hover:scale-[1.03] active:scale-95"
        >
          Download Drako.app
        </a>
      </motion.div>
    </section>
  )
}

export function Faq() {
  return (
    <section id="faq" aria-labelledby="faq-title" className="scroll-mt-24 px-4 py-20 sm:py-28">
      <div className="mx-auto max-w-3xl">
        <h2 id="faq-title" className="text-gradient text-center text-4xl font-semibold tracking-[-0.03em] sm:text-5xl">
          Questions
        </h2>
        <div className="mt-12 divide-y divide-white/8 border-y border-line">
          {FAQ.map((item) => (
            <details key={item.question} className="group py-5">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-lg text-white/85">
                {item.question}
                <span className="text-white/35 transition-transform duration-300 group-open:rotate-45">+</span>
              </summary>
              <p className="mt-3 leading-relaxed text-white/55">{item.answer}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}

export function Footer() {
  return (
    <footer className="border-t border-line px-4 py-10 text-sm text-white/40">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4">
        <p>© {new Date().getFullYear()} Drako. A fork of Ghostty, MIT licensed.</p>
        <a href="https://ghostty.org" className="hover:text-white/70">
          Built on Ghostty
        </a>
      </div>
    </footer>
  )
}
