import type { ReactNode } from 'react'

/** A macOS-style window frame with Drako's titlebar (traffic lights, host, tab pills). */
export function Window({
  host = 'This Mac',
  tabs = [],
  activeTab = 0,
  children,
  className = '',
}: {
  host?: string
  tabs?: string[]
  activeTab?: number
  children: ReactNode
  className?: string
}) {
  return (
    <div className={`glass overflow-hidden rounded-2xl shadow-2xl shadow-black/60 ${className}`}>
      <div className="flex h-9 items-center gap-3 px-3.5">
        <TrafficLights />
        <span className="font-mono text-[11px] text-white/45">{host}</span>
        <div className="ml-2 flex gap-1 overflow-hidden">
          {tabs.map((tab, index) => (
            <span
              key={tab}
              className={`rounded-full px-2.5 py-0.5 text-[11px] whitespace-nowrap ${
                index === activeTab ? 'bg-white/10 text-white/85 ring-1 ring-white/12' : 'text-white/40'
              }`}
            >
              {tab}
            </span>
          ))}
        </div>
      </div>
      <div className="p-1.5 pt-0">{children}</div>
    </div>
  )
}

export function TrafficLights() {
  return (
    <div className="flex gap-1.5" aria-hidden>
      <span className="size-2.5 rounded-full bg-[#ff5f57]" />
      <span className="size-2.5 rounded-full bg-[#febc2e]" />
      <span className="size-2.5 rounded-full bg-[#28c840]" />
    </div>
  )
}

/** One terminal pane card, with the host it lives on in its header. */
export function Pane({
  title,
  host,
  dot = 'bg-mint',
  children,
  className = '',
}: {
  title: string
  host: string
  dot?: string
  children: ReactNode
  className?: string
}) {
  return (
    <div className={`flex min-w-0 flex-col overflow-hidden rounded-xl bg-card ring-1 ring-white/6 ${className}`}>
      <div className="flex items-center gap-2 border-b border-line px-3 py-1.5 text-[11px]">
        <span className={`size-1.5 rounded-full ${dot}`} />
        <span className="truncate text-white/75">{title}</span>
        <span className="ml-auto truncate font-mono text-white/35">{host}</span>
      </div>
      <div className="flex-1 p-3 font-mono text-[11.5px] leading-[1.6] text-white/75">{children}</div>
    </div>
  )
}
