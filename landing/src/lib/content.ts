import { SERVER_URL } from './site'

export const FAQ = [
  {
    question: 'What happens to my terminals when I quit Drako?',
    answer:
      'Nothing. Every pane is a drako session running outside the app. Quitting only detaches; ' +
      'when you reopen Drako every tab comes back with its screen, scrollback and running programs.',
  },
  {
    question: 'Can one tab mix local and remote machines?',
    answer:
      'Yes. Tabs belong to the app, panes belong to a host. You can split a local pane next to one ' +
      'running on a server over ssh, and each keeps its own session on its own machine.',
  },
  {
    question: 'What if my ssh connection drops?',
    answer:
      'The pane shows "disconnected · reconnect". Press Enter or click it and Drako re-attaches to ' +
      'the same session: the build, the logs and the shell are still where you left them.',
  },
  {
    question: 'Does Drako use my Ghostty config?',
    answer:
      'Yes. Drako is a fork of Ghostty and reads your Ghostty config: keybindings, fonts and settings ' +
      'all carry over, with a neutral charcoal theme applied on top.',
  },
  {
    question: 'What do I need on remote hosts?',
    answer:
      'The drako binary in /usr/local/bin and key-based ssh access. Drako shares one ssh connection ' +
      'per host, so new panes open instantly.',
  },
]

export const INSTALL_STEPS = [
  {
    comment: 'the session server for this Mac (the app installs it on remote hosts)',
    command: `curl -fsSL --create-dirs -o ~/.local/bin/drako ${SERVER_URL} && chmod +x ~/.local/bin/drako`,
  },
  { comment: 'add your machines', command: 'echo "me@devbox" >> ~/.config/drako/hosts' },
  { comment: 'open the app', command: 'open -a Drako' },
]
