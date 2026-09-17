// The popup Cmd+Shift+, opens. Lists the enabled extensions that have an options page, narrows the list
// as you type, and opens the chosen one's options page in a new tab beside the current one. Before
// anything is typed, Brave's Keyboard Shortcuts page leads the list.
// AGENTS.md covers loading, reloading and testing it, and what did not work.

const input = document.querySelector('input')
const list = document.querySelector('ul')

// chrome://, not brave://: Brave opens either one here, but Chrome leaves brave:// on a blank tab.
const keyboardShortcuts = { name: 'Keyboard Shortcuts', url: 'chrome://extensions/shortcuts' }

let extensions = []
let matches = []
let selected = 0

const wordStart = (name, token) => new RegExp(`(^|[^\\p{L}\\p{N}])${RegExp.escape(token)}`, 'iu').test(name)

/** Returns the extensions whose names contain every word of the query, best match first: a name that starts with the query, then a word that starts with it, then anything else. Ties keep alphabetical order. An empty query returns every extension, after Keyboard Shortcuts. */
const filter = query => {
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean)
  if (!tokens.length) return [keyboardShortcuts, ...extensions]
  const rank = ({ name }) => (name.toLowerCase().startsWith(tokens.join(' ')) ? 0 : wordStart(name, tokens[0]) ? 1 : 2)
  return extensions
    .filter(({ name }) => tokens.every(token => name.toLowerCase().includes(token)))
    .sort((a, b) => rank(a) - rank(b))
}

const render = () => {
  list.replaceChildren(
    ...matches.map((match, i) => {
      const item = document.createElement('li')
      item.role = 'option'
      item.textContent = match.name
      item.ariaSelected = String(i === selected)
      if (match === keyboardShortcuts) item.className = 'keyboard-shortcuts'
      item.addEventListener('click', () => open(match))
      return item
    }),
  )
  list.children[selected]?.scrollIntoView({ block: 'nearest' })
}

const open = async match => {
  const [current] = await chrome.tabs.query({ active: true, currentWindow: true })
  await chrome.tabs.create({ url: match.url, ...(current && { index: current.index + 1 }) })
  window.close()
}

input.addEventListener('input', () => {
  matches = filter(input.value)
  selected = 0
  render()
})

input.addEventListener('keydown', event => {
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault()
    if (!matches.length) return
    selected = (selected + (event.key === 'ArrowDown' ? 1 : -1) + matches.length) % matches.length
    render()
  } else if (event.key === 'Enter' && matches[selected]) {
    open(matches[selected])
  } else if (event.key === 'Escape') {
    window.close()
  }
})

matches = filter(input.value)
render()

chrome.management.getAll().then(all => {
  extensions = all
    .filter(extension => extension.enabled && extension.optionsUrl)
    .map(extension => ({ name: extension.name, url: extension.optionsUrl }))
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }))
  matches = filter(input.value)
  render()
})
