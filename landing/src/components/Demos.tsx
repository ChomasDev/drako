import { AnimatePresence, LayoutGroup, motion } from 'motion/react'

import { useLoop } from '../lib/useLoop'
import { Pane, Window } from './Window'

const SPRING = { type: 'spring', stiffness: 260, damping: 28 } as const

const STAGE =
  'relative overflow-hidden rounded-3xl border border-line bg-gradient-to-b from-white/[0.04] to-transparent'

// Quit → closed → reopen, with the tests still running in between.

const PERSIST_PHASES = [3200, 900, 2600, 2800]

const TESTS = [
  'auth › signs a token',
  'auth › rejects a bad password',
  'billing › charges once',
  'billing › retries on 503',
  'sync › merges offline edits',
  'sync › resolves conflicts',
  'export › writes the csv',
]

export function PersistDemo() {
  const { ref, phase } = useLoop(PERSIST_PHASES, 3)
  const isOpen = phase === 0 || phase === 3
  const passed = phase === 3 ? TESTS.length : 3

  return (
    <div ref={ref} className={`${STAGE} h-[380px] p-6`}>
      <AnimatePresence>
        {isOpen && (
          <motion.div
            key="window"
            initial={{ opacity: 0, scale: 0.3, y: 180 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.3, y: 180 }}
            transition={SPRING}
          >
            <Window tabs={['tests']}>
              <Pane title="pnpm test" host="This Mac" className="h-[230px]">
                {TESTS.slice(0, passed).map((test, index) => (
                  <motion.div
                    key={test}
                    initial={{ opacity: 0, x: -6 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: index >= 3 ? 0.35 + (index - 3) * 0.12 : 0 }}
                    className={index >= 3 ? 'text-mint' : 'text-white/55'}
                  >
                    ✓ {test}
                  </motion.div>
                ))}
                {phase === 3 && (
                  <motion.p
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ delay: 0.9 }}
                    className="mt-1 text-white/35"
                  >
                    # 4 finished while Drako was closed
                  </motion.p>
                )}
              </Pane>
            </Window>
          </motion.div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {phase === 1 && <KeyBadge key="quit" label="⌘Q" />}
        {phase === 2 && (
          <motion.div
            key="background"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="absolute inset-x-0 top-24 flex flex-col items-center gap-3 text-center"
          >
            <div className="flex gap-1.5">
              {[0, 1, 2].map((dot) => (
                <motion.span
                  key={dot}
                  className="size-2 rounded-full bg-mint"
                  animate={{ opacity: [0.25, 1, 0.25] }}
                  transition={{ duration: 1.2, repeat: Infinity, delay: dot * 0.2 }}
                />
              ))}
            </div>
            <p className="text-sm text-white/70">App closed. Session still running.</p>
            <p className="font-mono text-xs text-white/35">drako ls → tests · attached: no</p>
          </motion.div>
        )}
      </AnimatePresence>

      <Dock isRunning={isOpen} />
    </div>
  )
}

function Dock({ isRunning }: { isRunning: boolean }) {
  return (
    <div className="glass absolute bottom-4 left-1/2 flex -translate-x-1/2 items-end gap-2 rounded-2xl px-3 pt-2 pb-1.5">
      {['bg-sky/70', 'bg-peach/70'].map((color) => (
        <span key={color} className={`size-9 rounded-[10px] ${color} opacity-40`} />
      ))}
      <div className="flex flex-col items-center gap-1">
        <img src="/favicon.png" alt="" width={36} height={36} className="size-9 rounded-[10px]" />
        <motion.span className="size-1 rounded-full bg-white/70" animate={{ opacity: isRunning ? 1 : 0 }} />
      </div>
    </div>
  )
}

function KeyBadge({ label }: { label: string }) {
  return (
    <motion.kbd
      initial={{ opacity: 0, scale: 0.6 }}
      animate={{ opacity: 1, scale: [0.6, 1.1, 1] }}
      exit={{ opacity: 0, scale: 0.8 }}
      className="glass absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 rounded-xl px-4 py-2 font-sans text-2xl text-white"
    >
      {label}
    </motion.kbd>
  )
}

// One tab, panes split across machines.

const SPLIT_PHASES = [1800, 1800, 3200]

const HOST_PANES = [
  { host: 'This Mac', title: 'zsh', dot: 'bg-mint', lines: ['❯ git pull', 'Already up to date.'] },
  { host: 'devbox', title: 'docker compose', dot: 'bg-sky', lines: ['api   | listening :8080', 'db    | ready'] },
  { host: 'gpu-01', title: 'train.py', dot: 'bg-lavender', lines: ['epoch 14/40', 'loss 0.0381 ▾'] },
]

export function MachinesDemo() {
  const { ref, phase } = useLoop(SPLIT_PHASES, 2)
  const visible = HOST_PANES.slice(0, phase + 1)

  return (
    <div ref={ref} className={`${STAGE} p-6`}>
      <Window host={visible[visible.length - 1].host} tabs={['deploy']}>
        <LayoutGroup>
          <div className="flex h-[240px] gap-1.5">
            {visible.map((pane) => (
              <motion.div
                key={pane.host}
                layout
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={SPRING}
                className="flex min-w-0 flex-1"
              >
                <Pane title={pane.title} host={pane.host} dot={pane.dot} className="flex-1">
                  {pane.lines.map((line) => (
                    <div key={line} className="truncate text-white/55">
                      {line}
                    </div>
                  ))}
                </Pane>
              </motion.div>
            ))}
          </div>
        </LayoutGroup>
      </Window>

      <div className="mt-4 flex flex-wrap gap-2">
        {HOST_PANES.map((pane, index) => (
          <motion.span
            key={pane.host}
            animate={{ opacity: index <= phase ? 1 : 0.35 }}
            className="flex items-center gap-1.5 rounded-full border border-line px-3 py-1 font-mono text-xs text-white/60"
          >
            <span className={`size-1.5 rounded-full ${pane.dot}`} />
            {pane.host}
          </motion.span>
        ))}
      </div>
    </div>
  )
}

// The network drops, the pane waits, Enter re-attaches.

const RECONNECT_PHASES = [2600, 2800, 2400]

const LOGS = ['migrating 1/4  users', 'migrating 2/4  orders', 'migrating 3/4  invoices']

export function ReconnectDemo() {
  const { ref, phase } = useLoop(RECONNECT_PHASES, 2)
  const isDisconnected = phase === 1

  return (
    <div ref={ref} className={`${STAGE} p-6`}>
      <Window host="devbox" tabs={['db']}>
        <div className="relative">
          <Pane title="migrate" host="devbox" dot={isDisconnected ? 'bg-rose' : 'bg-mint'} className="h-[230px]">
            {LOGS.map((line) => (
              <div key={line} className="text-white/55">
                {line}
              </div>
            ))}
            {phase === 2 && (
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.4 }}>
                <div className="text-white/55">migrating 4/4 payments</div>
                <div className="text-mint">✓ done in 6m 12s</div>
              </motion.div>
            )}
          </Pane>

          <AnimatePresence>
            {isDisconnected && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="absolute inset-0 flex items-center justify-center rounded-xl bg-black/50 backdrop-blur-[3px]"
              >
                <motion.span
                  initial={{ y: 8, scale: 0.95 }}
                  animate={{ y: 0, scale: 1 }}
                  className="rounded-full border border-rose/30 bg-rose/10 px-4 py-1.5 text-sm text-rose"
                >
                  disconnected · <span className="underline underline-offset-2">reconnect</span>
                </motion.span>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </Window>

      <div className="mt-4 flex items-center gap-3 font-mono text-xs text-white/45">
        <WifiIcon isOff={isDisconnected} />
        <AnimatePresence mode="wait">
          <motion.span
            key={phase}
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
          >
            {
              ['ssh devbox · 18 ms', 'Wi‑Fi lost · session kept on devbox', '↵ Enter · re-attached, nothing lost'][
                phase
              ]
            }
          </motion.span>
        </AnimatePresence>
      </div>
    </div>
  )
}

function WifiIcon({ isOff }: { isOff: boolean }) {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden
      className={isOff ? 'text-rose' : 'text-mint'}
    >
      <path
        d="M2 9a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16a5 5 0 0 1 6 0"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
      <circle cx="12" cy="19.5" r="1.4" fill="currentColor" />
      <motion.path
        d="M3 3l18 18"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        initial={false}
        animate={{ pathLength: isOff ? 1 : 0 }}
      />
    </svg>
  )
}

// The real sidebar, floating in gently.

export function SidebarShot() {
  return (
    <div className={`${STAGE} flex justify-center p-6 sm:p-10`}>
      <motion.img
        src="/shots/drako-sidebar.webp"
        alt="Drako sidebar listing three tabs, each with its panes, and the Split pane and Move pane controls"
        width={528}
        height={930}
        loading="lazy"
        initial={{ y: 24, rotate: -1.5 }}
        whileInView={{ y: 0, rotate: 0 }}
        viewport={{ once: true, amount: 0.4 }}
        transition={SPRING}
        className="w-full max-w-[264px] rounded-2xl shadow-2xl shadow-black/60"
      />
    </div>
  )
}

// The menu bar agent lists every window's layout.

const MENU_PHASES = [1600, 3400]

const MENU_ITEMS = [
  { title: 'Drako', detail: 'web · api · infra' },
  { title: 'Drako — research', detail: 'notebooks · gpu-01' },
  { title: 'Drako — on-call', detail: 'quit 2h ago · relaunch' },
]

export function MenuBarDemo() {
  const { ref, phase } = useLoop(MENU_PHASES, 1)
  const isOpen = phase === 1

  return (
    <div ref={ref} className={`${STAGE} h-[340px]`}>
      <div className="flex h-8 items-center justify-end gap-4 bg-white/[0.06] px-4 text-xs text-white/70 backdrop-blur">
        <motion.span
          animate={{ backgroundColor: isOpen ? 'rgba(255,255,255,0.18)' : 'rgba(255,255,255,0)' }}
          className="flex h-6 items-center rounded-md px-1.5"
        >
          <img src="/menubar.png" alt="Drako menu bar icon" width={16} height={16} className="invert" />
        </motion.span>
        <span>Wed 9:41</span>
      </div>

      <AnimatePresence>
        {isOpen && (
          <motion.ul
            initial={{ opacity: 0, y: -6, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.2 }}
            className="glass absolute top-10 right-16 w-64 rounded-xl p-1.5 text-sm shadow-2xl"
          >
            {MENU_ITEMS.map((item, index) => (
              <motion.li
                key={item.title}
                initial={{ opacity: 0, x: -4 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.08 * index }}
                className={`rounded-md px-3 py-1.5 ${index === 0 ? 'bg-sky/25' : ''}`}
              >
                <div className="text-white/90">{item.title}</div>
                <div className="text-xs text-white/45">{item.detail}</div>
              </motion.li>
            ))}
          </motion.ul>
        )}
      </AnimatePresence>
    </div>
  )
}
