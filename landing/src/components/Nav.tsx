import { motion, useMotionValueEvent, useScroll } from 'motion/react'
import { useState } from 'react'

const LINKS = [
  { href: '#sessions', label: 'Sessions' },
  { href: '#machines', label: 'Machines' },
  { href: '#sidebar', label: 'Sidebar' },
  { href: '#faq', label: 'FAQ' },
]

export function Nav() {
  const { scrollY } = useScroll()
  const [isScrolled, setIsScrolled] = useState(false)

  useMotionValueEvent(scrollY, 'change', (y) => setIsScrolled(y > 24))

  return (
    <motion.header
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
      className="fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-3"
    >
      <nav
        aria-label="Main"
        className={`flex w-full max-w-5xl items-center gap-6 rounded-full px-4 py-2 transition-all duration-500 ${
          isScrolled ? 'glass' : 'border border-transparent'
        }`}
      >
        <a href="#top" className="flex items-center gap-2 font-semibold tracking-tight text-white">
          <img src="/favicon.png" alt="" width={22} height={22} className="rounded-md" />
          Drako
        </a>
        <ul className="ml-auto hidden items-center gap-6 text-sm text-white/60 sm:flex">
          {LINKS.map((link) => (
            <li key={link.href}>
              <a href={link.href} className="transition-colors hover:text-white">
                {link.label}
              </a>
            </li>
          ))}
        </ul>
        <a
          href="#download"
          className="ml-auto rounded-full bg-white px-3.5 py-1.5 text-sm font-medium text-black transition-transform hover:scale-[1.03] active:scale-95 sm:ml-0"
        >
          Download
        </a>
      </nav>
    </motion.header>
  )
}
