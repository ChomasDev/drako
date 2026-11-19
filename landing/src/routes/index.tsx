import { createFileRoute } from '@tanstack/react-router'

import { Faq, Footer, Install, Pillars } from '../components/Closing'
import { MachinesDemo, MenuBarDemo, PersistDemo, ReconnectDemo, SidebarShot } from '../components/Demos'
import { Feature } from '../components/Feature'
import { Hero } from '../components/Hero'
import { Nav } from '../components/Nav'

export const Route = createFileRoute('/')({
  component: Home,
})

function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />

        <Feature
          id="sessions"
          eyebrow="Persistent sessions"
          eyebrowColor="text-mint"
          title="Quit. Reopen. Nothing lost."
          demo={<PersistDemo />}
        >
          <p>
            Every pane runs in a drako session outside the app. Quitting Drako only detaches, so your tests, servers and
            shells keep going.
          </p>
          <p>Open it again and every tab is rebuilt, with its split layout, screen and scrollback.</p>
        </Feature>

        <Feature
          id="machines"
          eyebrow="Multi-host tabs"
          eyebrowColor="text-sky"
          title="One tab. Every machine."
          demo={<MachinesDemo />}
          isReversed
        >
          <p>
            Tabs belong to you, panes belong to a host. Put your laptop shell next to a server’s logs and a training run
            on a GPU box, all in the same tab.
          </p>
          <p>The Machines menu shows every host with its status, latency and live terminals.</p>
        </Feature>

        <Feature
          eyebrow="Network drops"
          eyebrowColor="text-rose"
          title="Wi‑Fi gone? Press Enter."
          demo={<ReconnectDemo />}
        >
          <p>
            When ssh drops, the session stays alive on the remote machine. The pane just says “disconnected ·
            reconnect”.
          </p>
          <p>Press Enter and you are back inside the same migration, exactly where it is now.</p>
        </Feature>

        <Feature
          id="sidebar"
          eyebrow="Sidebar"
          eyebrowColor="text-lavender"
          title="Your layout, by drag and drop."
          demo={<SidebarShot />}
          isReversed
        >
          <p>
            Machines, tabs with their panes, and detached terminals in one sidebar (⌘⇧S). Drag a pane to another tab,
            swap two panes, or attach a detached session with a click.
          </p>
        </Feature>

        <Feature
          eyebrow="Menu bar agent"
          eyebrowColor="text-peach"
          title="Always one click away."
          demo={<MenuBarDemo />}
        >
          <p>
            A tiny agent lives in the menu bar and outlives the app. It lists every window’s layout and brings it to the
            front, or relaunches Drako right into it.
          </p>
        </Feature>

        <Pillars />
        <Install />
        <Faq />
      </main>
      <Footer />
    </>
  )
}
