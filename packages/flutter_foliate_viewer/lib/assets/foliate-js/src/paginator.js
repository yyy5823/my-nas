const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

const lerp = (min, max, x) => x * (max - min) + min
const easeOutSine = x => Math.sin((x * Math.PI) / 2)
// const easeOutSine = x => 1 - (1 - x) * (1 - x);
const animate = (a, b, duration, ease, render, { initialProgress = 0 } = {}) => new Promise(resolve => {
  let start
  const clampedInitial = Math.max(0, Math.min(initialProgress, 0.95))
  const step = now => {
    start ??= now - clampedInitial * duration
    const fraction = Math.min(1, (now - start) / duration)
    render(lerp(a, b, ease(fraction)))
    if (fraction < 1) requestAnimationFrame(step)
    else resolve()
  }
  requestAnimationFrame(step)
})

// collapsed range doesn't return client rects sometimes (or always?)
// try make get a non-collapsed range or element
const uncollapse = range => {
  if (!range?.collapsed) return range
  const { endOffset, endContainer } = range
  if (endContainer.nodeType === 1) return endContainer
  if (endOffset + 1 < endContainer.length) range.setEnd(endContainer, endOffset + 1)
  else if (endOffset > 1) range.setStart(endContainer, endOffset - 1)
  else return endContainer.parentNode
  return range
}

const makeRange = (doc, node, start, end = start) => {
  const range = doc.createRange()
  range.setStart(node, start)
  range.setEnd(node, end)
  return range
}

// use binary search to find an offset value in a text node
const bisectNode = (doc, node, cb, start = 0, end = node.nodeValue.length) => {
  if (end - start === 1) {
    const result = cb(makeRange(doc, node, start), makeRange(doc, node, end))
    return result < 0 ? start : end
  }
  const mid = Math.floor(start + (end - start) / 2)
  const result = cb(makeRange(doc, node, start, mid), makeRange(doc, node, mid, end))
  return result < 0 ? bisectNode(doc, node, cb, start, mid)
    : result > 0 ? bisectNode(doc, node, cb, mid, end) : mid
}

const { SHOW_ELEMENT, SHOW_TEXT, SHOW_CDATA_SECTION,
  FILTER_ACCEPT, FILTER_REJECT, FILTER_SKIP } = NodeFilter

const filter = SHOW_ELEMENT | SHOW_TEXT | SHOW_CDATA_SECTION

const getVisibleRange = (doc, start, end, mapRect) => {
  // first get all visible nodes
  const acceptNode = node => {
    const name = node.localName?.toLowerCase()
    // ignore all scripts, styles, and their children
    if (name === 'script' || name === 'style') return FILTER_REJECT
    if (node.nodeType === 1) {
      const { left, right } = mapRect(node.getBoundingClientRect())
      // no need to check child nodes if it's completely out of view
      if (right < start || left > end) return FILTER_REJECT
      // elements must be completely in view to be considered visible
      // because you can't specify offsets for elements
      if (left >= start && right <= end) return FILTER_ACCEPT
      // TODO: it should probably allow elements that do not contain text
      // because they can exceed the whole viewport in both directions
      // especially in scrolled mode
    } else {
      // ignore empty text nodes
      if (!node.nodeValue?.trim()) return FILTER_REJECT
      // create range to get rect
      const range = doc.createRange()
      range.selectNodeContents(node)
      const { left, right } = mapRect(range.getBoundingClientRect())
      // it's visible if any part of it is in view
      if (right >= start && left <= end) return FILTER_ACCEPT
    }
    return FILTER_SKIP
  }
  if (!doc) return
  const walker = doc.createTreeWalker(doc.body, filter, { acceptNode })
  const nodes = []
  for (let node = walker.nextNode(); node; node = walker.nextNode())
    nodes.push(node)

  // we're only interested in the first and last visible nodes
  const from = nodes[0] ?? doc.body
  const to = nodes[nodes.length - 1] ?? from

  // find the offset at which visibility changes
  const startOffset = from.nodeType === 1 ? 0
    : bisectNode(doc, from, (a, b) => {
      const p = mapRect(a.getBoundingClientRect())
      const q = mapRect(b.getBoundingClientRect())
      if (p.right < start && q.left > start) return 0
      return q.left > start ? -1 : 1
    })
  const endOffset = to.nodeType === 1 ? 0
    : bisectNode(doc, to, (a, b) => {
      const p = mapRect(a.getBoundingClientRect())
      const q = mapRect(b.getBoundingClientRect())
      if (p.right < end && q.left > end) return 0
      return q.left > end ? -1 : 1
    })

  const range = doc.createRange()
  range.setStart(from, startOffset)
  range.setEnd(to, endOffset)
  return range
}

const getDirection = doc => {
  const { defaultView } = doc
  const { writingMode, direction } = defaultView.getComputedStyle(doc.body)
  const vertical = writingMode === 'vertical-rl'
    || writingMode === 'vertical-lr'
  const rtl = doc.body.dir === 'rtl'
    || direction === 'rtl'
    || doc.documentElement.dir === 'rtl'
  return { vertical, rtl, writingMode }
}

// const getBackground = doc => {
//   const bodyStyle = doc.defaultView.getComputedStyle(doc.body)
//   return bodyStyle.backgroundColor === 'rgba(0, 0, 0, 0)'
//     && bodyStyle.backgroundImage === 'none'
//     ? doc.defaultView.getComputedStyle(doc.documentElement).background
//     : bodyStyle.background
// }
const getBackground = (bgimgUrl) => {
  let bg
  if (bgimgUrl === 'none') {
    bg = `none`
  } else {
    bg = `url(${bgimgUrl}) repeat scroll 50% 50% / 100% 100%`
  }
  return bg
}

const makeMarginals = (length, part) => Array.from({ length }, () => {
  const div = document.createElement('div')
  const child = document.createElement('div')
  div.append(child)
  child.setAttribute('part', part)
  return div
})

const setStylesImportant = (el, styles) => {
  const { style } = el
  for (const [k, v] of Object.entries(styles)) style.setProperty(k, v, 'important')
}

class View {
  #observer = new ResizeObserver(() => {
    try {
      this.expand()
    } catch (e) {
      console.error('[View] ResizeObserver expand error:', e)
    }
  })
  #element = document.createElement('div')
  #iframe = document.createElement('iframe')
  #contentRange = document.createRange()
  #overlayer
  #vertical = false
  #rtl = false
  #writingMode = 'horizontal-ltr'
  #column = true
  #size
  #layout = {}
  constructor({ container, onExpand }) {
    this.container = container
    this.onExpand = onExpand
    this.#iframe.setAttribute('part', 'filter')
    this.#element.append(this.#iframe)
    Object.assign(this.#element.style, {
      boxSizing: 'content-box',
      position: 'relative',
      overflow: 'hidden',
      flex: '0 0 auto',
      width: '100%', height: '100%',
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'center',
      contain: 'layout paint size',
      contentVisibility: 'auto',
      willChange: 'transform',
    })
    Object.assign(this.#iframe.style, {
      overflow: 'hidden',
      border: '0',
      display: 'none',
      width: '100%', height: '100%',
    })
    // `allow-scripts` is needed for events because of WebKit bug
    // https://bugs.webkit.org/show_bug.cgi?id=218086
    this.#iframe.setAttribute('sandbox', 'allow-same-origin allow-scripts')
    this.#iframe.setAttribute('scrolling', 'no')
  }
  get element() {
    return this.#element
  }
  get document() {
    return this.#iframe.contentDocument
  }
  async load(src, afterLoad, beforeRender) {
    console.log('[View] load() called, src length:', src?.length, 'src:', src?.substring?.(0, 50))
    if (typeof src !== 'string') throw new Error(`${src} is not string`)

    const handleLoad = (doc) => {
      console.log('[View] handleLoad called, doc:', !!doc)
      afterLoad?.(doc)
      console.log('[View] afterLoad done')

      // it needs to be visible for Firefox to get computed style
      this.#iframe.style.display = 'block'
      console.log('[View] calling getDirection...')
      const { vertical, rtl, writingMode } = getDirection(doc)
      console.log('[View] getDirection result:', { vertical, rtl, writingMode })
      this.#iframe.style.display = 'none'

      this.#vertical = vertical
      this.#rtl = rtl
      this.#writingMode = writingMode

      console.log('[View] selecting content range...')
      this.#contentRange.selectNodeContents(doc.body)
      console.log('[View] calling beforeRender...')
      const layout = beforeRender?.({ vertical, rtl })
      console.log('[View] beforeRender result:', layout)
      this.#iframe.style.display = 'block'
      console.log('[View] calling render...')
      this.render(layout)
      console.log('[View] render done')
      this.#observer.observe(doc.body)
      console.log('[View] observer setup done')

      // the resize observer above doesn't work in Firefox
      // (see https://bugzilla.mozilla.org/show_bug.cgi?id=1832939)
      // until the bug is fixed we can at least account for font load
      doc.fonts?.ready?.then(() => {
        try {
          this.expand()
        } catch (e) {
          console.error('[View] fonts.ready expand error:', e)
        }
      }).catch(e => console.warn('[View] fonts.ready failed:', e))
    }

    // Check if we're on Windows WebView2 - it has cross-origin issues with blob URLs in iframes
    const isWindowsWebView = navigator.userAgent.includes('Windows') && navigator.userAgent.includes('Edg/')

    // On Windows WebView2, use srcdoc for blob URLs to avoid cross-origin issues
    // srcdoc creates an about:srcdoc origin which is same-origin to the parent
    if (isWindowsWebView && src.startsWith('blob:')) {
      console.log('[View] Windows WebView2 detected, using srcdoc for blob URL')
      try {
        const response = await fetch(src)
        const html = await response.text()
        console.log('[View] Fetched blob content, length:', html.length)

        return new Promise(resolve => {
          this.#iframe.addEventListener('load', () => {
            console.log('[View] srcdoc iframe loaded')
            try {
              const doc = this.document
              console.log('[View] got document from srcdoc:', !!doc)
              if (!doc) {
                console.error('[View] document is null after srcdoc load!')
                return
              }
              handleLoad(doc)
              console.log('[View] srcdoc handleLoad completed, resolving')
              resolve()
            } catch (e) {
              console.error('[View] srcdoc handleLoad error:', e)
              throw e
            }
          }, { once: true })
          // Use srcdoc - creates about:srcdoc origin
          console.log('[View] setting srcdoc...')
          this.#iframe.srcdoc = html
        })
      } catch (e) {
        console.error('[View] Failed to fetch blob URL:', e)
        throw e
      }
    }

    // Other platforms or non-blob URL - use regular src
    return new Promise(resolve => {
      console.log('[View] load() - setting up iframe load listener')
      this.#iframe.addEventListener('load', () => {
        console.log('[View] iframe load event fired')
        try {
          const doc = this.document
          console.log('[View] got document:', !!doc)
          if (!doc) {
            console.error('[View] document is null!')
            return
          }
          handleLoad(doc)
          console.log('[View] resolving promise')
          resolve()
        } catch (e) {
          console.error('[View] iframe load error:', e)
          throw e
        }
      }, { once: true })
      console.log('[View] setting iframe.src...')
      this.#iframe.src = src
      console.log('[View] iframe.src set')
    })
  }
  render(layout) {
    if (!layout) return
    this.#column = layout.flow !== 'scrolled'
    this.#layout = layout
    if (this.#column) this.columnize(layout)
    else this.scrolled(layout)
  }
  scrolled({ gap, columnWidth }) {
    const vertical = this.#vertical
    const doc = this.document
    if (!doc) return
    setStylesImportant(doc.documentElement, {
      'box-sizing': 'border-box',
      'padding': vertical ? `${gap}px 0` : `0 ${gap}px`,
      'column-width': 'auto',
      'height': 'auto',
      'width': 'auto',
    })
    setStylesImportant(doc.body, {
      [vertical ? 'max-height' : 'max-width']: `${columnWidth}px`,
      'margin': 'auto',
    })
    this.setImageSize()
    this.expand()
  }
  columnize({ width, height, gap, columnWidth, topMargin, bottomMargin }) {
    const vertical = this.#vertical
    this.#size = vertical ? height : width

    const doc = this.document
    if (!doc) return

    const verticlePadding = `${gap / 2}px ${topMargin}px ${gap / 2}px ${bottomMargin}px`
    const horizontalPadding = `${topMargin}px ${gap / 2}px ${bottomMargin}px ${gap / 2}px`

    setStylesImportant(doc.documentElement, {
      'box-sizing': 'border-box',
      'column-width': `${Math.trunc(columnWidth)}px`,
      'column-gap': `${gap}px`,
      'column-fill': 'auto',
      ...(vertical
        ? { 'width': `${width}px` }
        : { 'height': `${height}px` }),
      'padding': vertical ? verticlePadding : horizontalPadding,
      'overflow': 'hidden',
      // force wrap long words
      'overflow-wrap': 'break-word',
      // reset some potentially problematic props
      'position': 'static', 'border': '0', 'margin': '0',
      'max-height': 'none', 'max-width': 'none',
      'min-height': 'none', 'min-width': 'none',
      // fix glyph clipping in WebKit
      '-webkit-line-box-contain': 'block glyphs replaced',
    })
    setStylesImportant(doc.body, {
      'max-height': 'none',
      'max-width': 'none',
      'margin': '0',
    })
    this.setImageSize()
    this.expand()
  }
  setImageSize() {
    const { width, height, margin } = this.#layout
    const vertical = this.#vertical
    const doc = this.document
    if (!doc) return
    for (const el of doc.body.querySelectorAll('img, svg, video')) {
      // preserve max size if they are already set
      const { maxHeight, maxWidth } = doc.defaultView.getComputedStyle(el)
      setStylesImportant(el, {
        'max-height': vertical
          ? (maxHeight !== 'none' && maxHeight !== '0px' ? maxHeight : '100%')
          : `${height - margin * 2}px`,
        'max-width': vertical
          ? `${width - margin * 2}px`
          : (maxWidth !== 'none' && maxWidth !== '0px' ? maxWidth : '100%'),
        'object-fit': 'contain',
        'page-break-inside': 'avoid',
        'break-inside': 'avoid',
        'box-sizing': 'border-box',
      })
    }
  }
  expand() {
    const doc = this.document
    if (!doc) return
    const { documentElement } = doc
    if (this.#column) {
      const side = this.#vertical ? 'height' : 'width'
      const otherSide = this.#vertical ? 'width' : 'height'
      this.#contentRange.selectNodeContents(doc.body)
      const contentRect = this.#contentRange.getBoundingClientRect()
      const rootRect = documentElement.getBoundingClientRect()
      // offset caused by column break at the start of the page
      // which seem to be supported only by WebKit and only for horizontal writing
      const contentStart = this.#vertical ? 0
        : this.#rtl ? rootRect.right - contentRect.right : contentRect.left - rootRect.left
      const contentSize = contentStart + contentRect[side]
      const pageCount = Math.ceil(contentSize / this.#size)
      const expandedSize = pageCount * this.#size
      this.#element.style.padding = '0'
      this.#iframe.style[side] = `${expandedSize}px`
      this.#element.style[side] = `${expandedSize + this.#size * 2}px`
      this.#iframe.style[otherSide] = '100%'
      this.#element.style[otherSide] = '100%'
      documentElement.style[side] = `${this.#size}px`
      if (this.#overlayer) {
        this.#overlayer.element.style.margin = '0'
        this.#overlayer.element.style.left = this.#vertical ? '0' : `${this.#size}px`
        this.#overlayer.element.style.top = this.#vertical ? `${this.#size}px` : '0'
        this.#overlayer.element.style[side] = `${expandedSize}px`
        this.#overlayer.redraw()
      }
    } else {
      const side = this.#vertical ? 'width' : 'height'
      const otherSide = this.#vertical ? 'height' : 'width'
      const contentSize = documentElement.getBoundingClientRect()[side]
      const expandedSize = contentSize
      const { margin } = this.#layout
      const padding = this.#vertical ? `0 ${margin}px` : `${margin}px 0`
      this.#element.style.padding = padding
      this.#iframe.style[side] = `${expandedSize}px`
      this.#element.style[side] = `${expandedSize}px`
      this.#iframe.style[otherSide] = '100%'
      this.#element.style[otherSide] = '100%'
      if (this.#overlayer) {
        this.#overlayer.element.style.margin = padding
        this.#overlayer.element.style.left = '0'
        this.#overlayer.element.style.top = '0'
        this.#overlayer.element.style[side] = `${expandedSize}px`
        this.#overlayer.redraw()
      }
    }
    this.onExpand()
  }
  set overlayer(overlayer) {
    this.#overlayer = overlayer
    this.#element.append(overlayer.element)
  }
  get overlayer() {
    return this.#overlayer
  }
  get writingMode() {
    return this.#writingMode
  }
  destroy() {
    if (this.document) this.#observer.unobserve(this.document.body)
  }
}

// NOTE: everything here assumes the so-called "negative scroll type" for RTL
export class Paginator extends HTMLElement {
  static observedAttributes = [
    'flow', 'gap', 'top-margin', 'bottom-margin', 'background-color',
    'max-inline-size', 'max-block-size', 'max-column-count', 'page-turn-style',
  ]
  // Page turn style: 'slide' (default), 'simulation', 'cover'
  #pageTurnStyle = 'slide'
  #root = this.attachShadow({ mode: 'open' })
  #observer = new ResizeObserver(() => this.render())
  #top
  #background
  #container
  // #header
  // #footer
  #view
  #vertical = false
  #rtl = false
  #margin = 0
  #index = -1
  #anchor = 0 // anchor view to a fraction (0-1), Range, or Element
  #justAnchored = false
  #locked = false // while true, prevent any further navigation
  #styles
  #styleMap = new WeakMap()
  #mediaQuery = matchMedia('(prefers-color-scheme: dark)')
  #mediaQueryListener
  #ignoreNativeScroll = false
  #pendingScrollFrame = null
  #touchState
  #touchScrolled
  #loadingNext = false
  #loadingPrev = false
  #momentumDisabled = false
  #prevOverflowScrolling = ''
  #prevOverflowX = ''
  #prevOverflowY = ''
  #momentumTimer = null
  #pendingRelocate = null
  #snapping = false // Prevent concurrent snap operations
  #sectionChangeTime = 0 // Timestamp of last section change, used to prevent immediate bounce-back
  #cancelMomentumTimer() {
    if (this.#momentumTimer) {
      clearTimeout(this.#momentumTimer)
      this.#momentumTimer = null
    }
  }
  #disableMomentum() {
    this.#cancelMomentumTimer()
    if (this.#momentumDisabled) return
    const style = this.#container.style
    this.#prevOverflowScrolling = style.webkitOverflowScrolling
    this.#prevOverflowX = style.overflowX
    this.#prevOverflowY = style.overflowY
    style.webkitOverflowScrolling = 'auto'
    if (this.scrollProp === 'scrollLeft') style.overflowX = 'hidden'
    else style.overflowY = 'hidden'
    this.#momentumDisabled = true
  }
  #restoreMomentum() {
    this.#cancelMomentumTimer()
    if (!this.#momentumDisabled) return
    const style = this.#container.style
    style.webkitOverflowScrolling = this.#prevOverflowScrolling || 'touch'
    style.overflowX = this.#prevOverflowX || ''
    style.overflowY = this.#prevOverflowY || ''
    this.#prevOverflowScrolling = ''
    this.#prevOverflowX = ''
    this.#prevOverflowY = ''
    this.#momentumDisabled = false
  }
  constructor() {
    super()
    this.#root.innerHTML = `<style>
        :host {
            display: block;
            container-type: size;
        }
        :host, #top {
            box-sizing: border-box;
            position: relative;
            overflow: hidden;
            width: 100%;
            height: 100%;
        }
        #top {
            height: 100%;
            // --_gap: 7%;
            background-color: var(--_background-color);
            --_max-inline-size: 720px;
            --_max-block-size: 1440px;
            --_max-column-count: 2;
            --_max-column-count-portrait: 1;
            --_max-column-count-spread: var(--_max-column-count);
            --_half-gap: calc(var(--_gap) / 2);
            --_max-width: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            --_max-height: var(--_max-block-size);
            display: grid;
            grid-template-columns:
                minmax(var(--_half-gap), 1fr)
                var(--_half-gap)
                minmax(0, calc(var(--_max-width) - var(--_gap)))
                var(--_half-gap)
                minmax(var(--_half-gap), 1fr);
            grid-template-rows:
                var(--_top-margin)
                1fr
                var(--_bottom-margin);
            &.vertical {
                --_max-column-count-spread: var(--_max-column-count-portrait);
                --_max-width: var(--_max-block-size);
                --_max-height: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            }
            @container (orientation: portrait) {
                & {
                    --_max-column-count-spread: var(--_max-column-count-portrait);
                }
                &.vertical {
                    --_max-column-count-spread: var(--_max-column-count);
                }
            }
        }
        #background {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
        }
        #container {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
            overflow-x: auto;
            overflow-y: hidden;
            -webkit-overflow-scrolling: touch;
            -ms-overflow-style: none;  /* Internet Explorer 10+ */
            scrollbar-width: none;  /* Firefox */
        }
        #container::-webkit-scrollbar {
            display: none;  /* Safari and Chrome */
        }
        :host([flow="scrolled"]) #container {
            grid-column: 1 / -1;
            grid-row: 2;
            overflow: auto;
        }
        #header {
            grid-column: 3 / 4;
            grid-row: 1;
        }
        #footer {
            grid-column: 3 / 4;
            grid-row: 3;
            align-self: end;
        }
        #header, #footer {
            display: grid;
            height: var(--_margin);
        }
        :is(#header, #footer) > * {
            display: flex;
            align-items: center;
            min-width: 0;
        }
        :is(#header, #footer) > * > * {
            width: 100%;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
            text-align: center;
            font-size: .75em;
            opacity: .6;
        }
        </style>
        <div id="top">
            <div id="background" part="filter"></div>
            <div id="container"></div>
        </div>
        `

    this.#top = this.#root.getElementById('top')
    this.#background = this.#root.getElementById('background')
    this.#container = this.#root.getElementById('container')
    // this.#header = this.#root.getElementById('header')
    // this.#footer = this.#root.getElementById('footer')

    this.#observer.observe(this.#container)
    this.#container.addEventListener('scroll', () => {
      if (this.#ignoreNativeScroll) return
      if (this.#justAnchored) {
        this.#justAnchored = false
        return
      }
      if (this.#pendingScrollFrame)
        cancelAnimationFrame(this.#pendingScrollFrame)
      this.#pendingScrollFrame = requestAnimationFrame(() => {
        this.#pendingScrollFrame = null
        this.#afterScroll('scroll')
        if (this.scrolled) this.#handleScrollBoundaries()
      })
    })

    const opts = { passive: false }
    this.addEventListener('touchstart', this.#onTouchStart.bind(this), opts)
    this.addEventListener('touchmove', this.#onTouchMove.bind(this), opts)
    this.addEventListener('touchend', this.#onTouchEnd.bind(this), opts)
    this.addEventListener('load', ({ detail: { doc } }) => {
      doc.addEventListener('touchstart', this.#onTouchStart.bind(this), opts)
      doc.addEventListener('touchmove', this.#onTouchMove.bind(this), opts)
      doc.addEventListener('touchend', this.#onTouchEnd.bind(this), opts)
    })

    this.#mediaQueryListener = () => {
      if (!this.#view) return
      this.#background.style.background = getBackground(this.getAttribute('bgimg-url'))
    }
    this.#mediaQuery.addEventListener('change', this.#mediaQueryListener)
  }
  attributeChangedCallback(name, _, value) {
    switch (name) {
      case 'flow':
        this.render()
        break
      case 'top-margin':
      case 'max-block-size':
      case 'background-color':
        this.#top.style.setProperty('--_' + name, value)
        break
      case 'bottom-margin':
      case 'gap':
      case 'max-column-count':
      case 'max-inline-size':
        // needs explicit `render()` as it doesn't necessarily resize
        this.#top.style.setProperty('--_' + name, value)
        this.render()
        break
      case 'page-turn-style':
        this.#pageTurnStyle = value || 'slide'
        // Reset state when page turn style changes
        this.#snapping = false
        this.#locked = false
        this.#touchState = null
        this.#touchScrolled = false
        this.#restoreMomentum()
        // Snap to nearest page without animation to fix any intermediate scroll state
        if (!this.scrolled && this.#view) {
          const page = this.page
          if (page >= 0 && this.size > 0) {
            this.#scrollToPage(this.#rtl ? -page : page, 'mode-change', { animate: false })
          }
        }
        console.log('[Paginator] page-turn-style changed to:', this.#pageTurnStyle)
        break
    }
  }
  get pageTurnStyle() {
    return this.#pageTurnStyle
  }
  set pageTurnStyle(value) {
    const oldValue = this.#pageTurnStyle
    this.#pageTurnStyle = value || 'slide'
    // Only reset if value actually changed
    if (oldValue !== this.#pageTurnStyle) {
      // Reset state when page turn style changes
      this.#snapping = false
      this.#locked = false
      this.#touchState = null
      this.#touchScrolled = false
      this.#restoreMomentum()
      // Snap to nearest page without animation
      if (!this.scrolled && this.#view) {
        const page = this.page
        if (page >= 0 && this.size > 0) {
          this.#scrollToPage(this.#rtl ? -page : page, 'mode-change', { animate: false })
        }
      }
    }
    this.setAttribute('page-turn-style', this.#pageTurnStyle)
  }
  open(book) {
    this.bookDir = book.dir
    this.sections = book.sections
  }
  #createView() {
    if (this.#view) {
      this.#view.destroy()
      this.#container.removeChild(this.#view.element)
    }
    this.#view = new View({
      container: this,
      onExpand: () => this.scrollToAnchor(this.#anchor),
    })
    this.#container.append(this.#view.element)
    return this.#view
  }
  #beforeRender({ vertical, rtl }) {
    this.#vertical = vertical
    this.#rtl = rtl
    this.#top.classList.toggle('vertical', vertical)

    // set background to `doc` background
    // this is needed because the iframe does not fill the whole element
    this.#background.style.background = getBackground(this.getAttribute('bgimg-url'))

    const { width, height } = this.#container.getBoundingClientRect()
    const size = vertical ? height : width

    const style = getComputedStyle(this.#top)
    const maxInlineSize = parseFloat(style.getPropertyValue('--_max-inline-size'))
    const maxColumnCount = parseInt(style.getPropertyValue('--_max-column-count'))
    const margin = parseFloat(style.getPropertyValue('--_top-margin'))
    this.#margin = margin

    const g = parseFloat(style.getPropertyValue('--_gap')) / 100
    // The gap will be a percentage of the #container, not the whole view.
    // This means the outer padding will be bigger than the column gap. Let
    // `a` be the gap percentage. The actual percentage for the column gap
    // will be (1 - a) * a. Let us call this `b`.
    //
    // To make them the same, we start by shrinking the outer padding
    // setting to `b`, but keep the column gap setting the same at `a`. Then
    // the actual size for the column gap will be (1 - b) * a. Repeating the
    // process again and again, we get the sequence
    //     x₁ = (1 - b) * a
    //     x₂ = (1 - x₁) * a
    //     ...
    // which converges to x = (1 - x) * a. Solving for x, x = a / (1 + a).
    // So to make the spacing even, we must shrink the outer padding with
    //     f(x) = x / (1 + x).
    // But we want to keep the outer padding, and make the inner gap bigger.
    // So we apply the inverse, f⁻¹ = -x / (x - 1) to the column gap.
    const gap = -g / (g - 1) * size

    const topMargin = parseFloat(style.getPropertyValue('--_top-margin'))
    const bottomMargin = parseFloat(style.getPropertyValue('--_bottom-margin'))

    const flow = this.getAttribute('flow')
    if (flow === 'scrolled') {
      this.#container.style.overflowX = 'auto'
      this.#container.style.overflowY = 'auto'
    } else if (vertical) {
      this.#container.style.overflowX = 'hidden'
      this.#container.style.overflowY = 'auto'
    } else {
      this.#container.style.overflowX = 'auto'
      this.#container.style.overflowY = 'hidden'
    }
    if (flow === 'scrolled') {
      // FIXME: vertical-rl only, not -lr
      this.setAttribute('dir', vertical ? 'rtl' : 'ltr')
      this.#top.style.padding = '0'
      const columnWidth = maxInlineSize

      this.heads = null
      this.feet = null
      // this.#header.replaceChildren()
      // this.#footer.replaceChildren()

      return { flow, margin, gap, columnWidth, topMargin, bottomMargin }
    }

    const divisor = maxColumnCount == 0
      ? Math.min(2, Math.ceil(size / maxInlineSize))
      : maxColumnCount

    const columnWidth = (size / divisor) - gap
    this.setAttribute('dir', rtl ? 'rtl' : 'ltr')

    const marginalDivisor = vertical
      ? Math.min(2, Math.ceil(width / maxInlineSize))
      : divisor
    const marginalStyle = {
      gridTemplateColumns: `repeat(${marginalDivisor}, 1fr)`,
      gap: `${gap}px`,
      direction: this.bookDir === 'rtl' ? 'rtl' : 'ltr',
    }
    // Object.assign(this.#header.style, marginalStyle)
    // Object.assign(this.#footer.style, marginalStyle)
    const heads = makeMarginals(marginalDivisor, 'head')
    const feet = makeMarginals(marginalDivisor, 'foot')
    this.heads = heads.map(el => el.children[0])
    this.feet = feet.map(el => el.children[0])
    // this.#header.replaceChildren(...heads)
    // this.#footer.replaceChildren(...feet)

    return { height, width, margin, gap, columnWidth, topMargin, bottomMargin }
  }
  render() {
    if (!this.#view) return
    this.#view.render(this.#beforeRender({
      vertical: this.#vertical,
      rtl: this.#rtl,
    }))
    this.scrollToAnchor(this.#anchor)
  }
  get scrolled() {
    return this.getAttribute('flow') === 'scrolled'
  }
  get scrollProp() {
    const { scrolled } = this
    return this.#vertical ? (scrolled ? 'scrollLeft' : 'scrollTop')
      : scrolled ? 'scrollTop' : 'scrollLeft'
  }
  get sideProp() {
    const { scrolled } = this
    return this.#vertical ? (scrolled ? 'width' : 'height')
      : scrolled ? 'height' : 'width'
  }
  get vertical() {
    return this.#vertical
  }
  get size() {
    return this.#container.getBoundingClientRect()[this.sideProp]
  }
  get viewSize() {
    if (!this.#view) return 0
    return this.#view.element.getBoundingClientRect()[this.sideProp]
  }
  get start() {
    return Math.abs(this.#container[this.scrollProp])
  }
  get end() {
    return this.start + this.size
  }
  get page() {
    return Math.floor(((this.start + this.end) / 2) / this.size)
  }
  get pages() {
    return Math.round(this.viewSize / this.size)
  }
  scrollBy(dx, dy) {
    const element = this.#container
    const prop = this.scrollProp
    const horizontal = prop === 'scrollLeft'
    const delta = horizontal ? dx : dy
    if (horizontal) element.scrollBy({ left: delta, top: 0, behavior: 'auto' })
    else element.scrollBy({ left: 0, top: delta, behavior: 'auto' })
  }
  // Prepare 3D flip animation
  // Returns the overlay element and a function to run the animation
  #prepareFlipAnimation(direction, duration) {
    const isForward = direction > 0
    const bgColor = this.getAttribute('background-color') || '#ffffff'

    // Container with 3D perspective
    const container = document.createElement('div')
    container.style.cssText = `
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      pointer-events: none;
      z-index: 100;
      perspective: 2000px;
      perspective-origin: ${isForward ? '0% 50%' : '100% 50%'};
    `

    if (this.#pageTurnStyle === 'simulation') {
      // 3D Page flip simulation with curl effect
      // Create multiple segments to simulate page curve
      const segments = 5
      const segmentWidth = 100 / segments

      const pageWrapper = document.createElement('div')
      pageWrapper.style.cssText = `
        position: absolute;
        top: 0; bottom: 0;
        width: 100%;
        transform-style: preserve-3d;
        transform-origin: ${isForward ? 'left center' : 'right center'};
      `

      // Create page segments for curve effect
      for (let i = 0; i < segments; i++) {
        const segment = document.createElement('div')
        segment.className = 'page-segment'
        segment.style.cssText = `
          position: absolute;
          top: 0; bottom: 0;
          width: ${segmentWidth}%;
          left: ${i * segmentWidth}%;
          background: ${bgColor};
          transform-style: preserve-3d;
          backface-visibility: hidden;
        `
        // Add subtle gradient for depth
        if (i === segments - 1 && isForward) {
          segment.style.background = `linear-gradient(to right, ${bgColor} 80%, rgba(0,0,0,0.03) 100%)`
        } else if (i === 0 && !isForward) {
          segment.style.background = `linear-gradient(to left, ${bgColor} 80%, rgba(0,0,0,0.03) 100%)`
        }
        pageWrapper.appendChild(segment)
      }

      // Shadow on the page being revealed (under the flipping page)
      const underShadow = document.createElement('div')
      underShadow.style.cssText = `
        position: absolute;
        top: 0; bottom: 0;
        width: 100%;
        background: transparent;
        pointer-events: none;
        z-index: -1;
      `

      // Shadow cast by the lifted page
      const castShadow = document.createElement('div')
      castShadow.style.cssText = `
        position: absolute;
        top: 5%; bottom: 5%;
        width: 80px;
        ${isForward ? 'left: 0;' : 'right: 0;'}
        background: linear-gradient(${isForward ? 'to right' : 'to left'},
          rgba(0,0,0,0.3) 0%,
          rgba(0,0,0,0.1) 40%,
          transparent 100%);
        opacity: 0;
        pointer-events: none;
        filter: blur(3px);
      `

      container.appendChild(underShadow)
      container.appendChild(pageWrapper)
      container.appendChild(castShadow)

      const animate = () => new Promise(resolve => {
        let start
        const step = now => {
          start ??= now
          const progress = Math.min(1, (now - start) / duration)
          // Use custom easing for more natural feel
          const eased = 1 - Math.pow(1 - progress, 3) // ease-out cubic

          // Rotation angle: 0 to 180 degrees
          const baseAngle = eased * 180
          const rotateDir = isForward ? -1 : 1

          // Apply rotation to wrapper
          pageWrapper.style.transform = `rotateY(${rotateDir * baseAngle}deg)`

          // Create curve effect by rotating segments slightly differently
          const segmentElements = pageWrapper.querySelectorAll('.page-segment')
          segmentElements.forEach((seg, i) => {
            // Curve is strongest in the middle of the flip
            const curveFactor = Math.sin(progress * Math.PI) * 0.15
            const segmentCurve = (isForward ? (segments - 1 - i) : i) * curveFactor * 15
            seg.style.transform = `rotateY(${rotateDir * segmentCurve}deg)`
          })

          // Shadow intensity follows the flip
          const shadowIntensity = Math.sin(progress * Math.PI)
          castShadow.style.opacity = shadowIntensity * 0.8

          // Move shadow position as page lifts
          const shadowOffset = Math.sin(progress * Math.PI) * 30
          if (isForward) {
            castShadow.style.left = `${shadowOffset}px`
          } else {
            castShadow.style.right = `${shadowOffset}px`
          }

          // Darken the revealed area slightly
          const revealDarkness = Math.sin(progress * Math.PI) * 0.1
          underShadow.style.background = `rgba(0,0,0,${revealDarkness})`

          if (progress < 1) requestAnimationFrame(step)
          else resolve()
        }
        requestAnimationFrame(step)
      })

      return { overlay: container, animate }

    } else if (this.#pageTurnStyle === 'cover') {
      // Cover mode: 3D page slides over
      const page = document.createElement('div')
      page.style.cssText = `
        position: absolute;
        top: 0; bottom: 0;
        width: 100%;
        background: ${bgColor};
        transform-style: preserve-3d;
        transform-origin: ${isForward ? 'right center' : 'left center'};
        box-shadow: ${isForward ? '-5px' : '5px'} 0 25px rgba(0,0,0,0.3);
      `

      // Add slight page texture
      const pageInner = document.createElement('div')
      pageInner.style.cssText = `
        position: absolute;
        top: 0; left: 0; right: 0; bottom: 0;
        background: linear-gradient(${isForward ? 'to left' : 'to right'},
          transparent 0%,
          rgba(0,0,0,0.02) 100%);
      `
      page.appendChild(pageInner)

      // Shadow underneath
      const shadow = document.createElement('div')
      shadow.style.cssText = `
        position: absolute;
        top: 0; bottom: 0;
        width: 100px;
        ${isForward ? 'left: 0;' : 'right: 0;'}
        background: linear-gradient(${isForward ? 'to right' : 'to left'},
          rgba(0,0,0,0.2) 0%,
          transparent 100%);
        opacity: 0;
        z-index: -1;
      `

      container.appendChild(shadow)
      container.appendChild(page)

      const animate = () => new Promise(resolve => {
        let start
        const step = now => {
          start ??= now
          const progress = Math.min(1, (now - start) / duration)
          const eased = 1 - Math.pow(1 - progress, 2.5) // ease-out

          // Combine translation with slight rotation for 3D effect
          const translateX = eased * 100
          const rotateY = eased * 15 // Slight rotation for depth

          if (isForward) {
            page.style.transform = `translateX(-${translateX}%) rotateY(${rotateY}deg)`
          } else {
            page.style.transform = `translateX(${translateX}%) rotateY(-${rotateY}deg)`
          }

          // Shadow follows
          const shadowOpacity = Math.sin(progress * Math.PI) * 0.8
          shadow.style.opacity = shadowOpacity

          if (progress < 1) requestAnimationFrame(step)
          else resolve()
        }
        requestAnimationFrame(step)
      })

      return { overlay: container, animate }
    }

    return null
  }
  async snap(vx, vy, touchState) {
    // Prevent concurrent snap operations
    if (this.#snapping) {
      console.log('[Paginator] Snap already in progress, ignoring')
      return
    }
    // Skip if footnote is being processed
    if (globalThis.__footnoteProcessing) {
      console.log('[Paginator] snap: footnote processing, skipping')
      return
    }
    this.#snapping = true

    try {
      const state = touchState ?? this.#touchState
      const velocity = this.#vertical ? vy : vx
      const { pages, size } = this
      if (!pages || size === 0) {
        this.#restoreMomentum()
        return
      }
      const currentOffset = this.#container[this.scrollProp]
      const signedOffset = this.#rtl ? -currentOffset : currentOffset
      let page = Math.round(signedOffset / size)
      const velocityThreshold = 0.25
      if (Math.abs(velocity) > velocityThreshold)
        page += velocity > 0 ? 1 : -1
      const originPage = state?.startPage ?? this.page
      if (!this.scrolled) {
        const deltaPages = page - originPage
        if (deltaPages > 1) page = originPage + 1
        else if (deltaPages < -1) page = originPage - 1
      }
      page = Math.max(0, Math.min(pages - 1, page))
      const targetOffset = page * size
      const distance = Math.abs(targetOffset - signedOffset)
      const baseDuration = 450
      const duration = Math.max(260, Math.min(380,
        baseDuration * (distance / (size || 1) + 0.2)))

      const pageArg = this.#rtl ? -page : page
      this.#disableMomentum()

      // For simulation and cover modes, show flip animation
      const useFlipAnimation = (this.#pageTurnStyle === 'simulation' || this.#pageTurnStyle === 'cover')
        && !this.scrolled && page !== originPage

      if (useFlipAnimation) {
        const direction = page > originPage ? 1 : -1
        // Use appropriate duration for 3D flip (longer than slide animation)
        const flipDuration = this.#pageTurnStyle === 'simulation' ? 500 : 400
        let flipData = null

        try {
          // 1. Prepare overlay BEFORE scrolling (covers current page)
          flipData = this.#prepareFlipAnimation(direction, flipDuration)
          if (flipData) {
            this.#top.appendChild(flipData.overlay)
          }

          // 2. Scroll to target page instantly (hidden by overlay)
          await this.#scrollToPage(pageArg, 'snap', {
            animate: false,
            restoreMomentum: true,
            momentumDelay: 20
          })

          // 3. Run animation to reveal new page
          if (flipData) {
            await flipData.animate()
          }

        } catch (e) {
          console.warn('[Paginator] Flip animation failed:', e)
        } finally {
          // Always clean up overlay
          if (flipData?.overlay?.parentNode) {
            flipData.overlay.parentNode.removeChild(flipData.overlay)
          }
        }

        // Check if we need to go to next/prev section
        const dir = page <= 0 ? -1 : page >= pages - 1 ? 1 : null
        if (dir) {
          await this.#goTo({
            index: this.#adjacentIndex(dir),
            anchor: dir < 0 ? () => 1 : () => 0,
          })
        }
        return
      }

      await this.#scrollToPage(pageArg, 'snap', { animate: true, duration, restoreMomentum: true, momentumDelay: 20, initialVelocity: velocity })
      const dir = page <= 0 ? -1 : page >= pages - 1 ? 1 : null
      if (dir) {
        await this.#goTo({
          index: this.#adjacentIndex(dir),
          anchor: dir < 0 ? () => 1 : () => 0,
        })
      }
    } finally {
      this.#snapping = false
    }
  }
  #onTouchStart(e) {
    const touch = e.changedTouches[0]
    const scrollProp = this.scrollProp
    this.#touchState = {
      x: touch?.screenX, y: touch?.screenY,
      t: e.timeStamp,
      vx: 0, vy: 0,
      pinched: false,
      direction: 'none',
      startTouch: {
        x: e.touches[0].screenX,
        y: e.touches[0].screenY,
      },
      delta: { x: 0, y: 0 },
      startScroll: this.#container[scrollProp],
      startPage: this.page,
      lockedOffset: null,
      axis: scrollProp,
    }
    this.dispatchEvent(new CustomEvent('doctouchstart', {
      detail: {
        touch: e.changedTouches[0],
        touchState: this.#touchState,
      },
      bubbles: true,
      composed: true
    }))
  }
  #onTouchMove(e) {
    if (window.getSelection()?.toString()) return

    const touch = e.changedTouches[0]
    const state = this.#touchState
    if (!state) return

    const deltaX = touch.screenX - state.startTouch.x
    const deltaY = touch.screenY - state.startTouch.y

    const absDeltaX = Math.abs(deltaX);
    const absDeltaY = Math.abs(deltaY);

    state.delta.x = deltaX
    state.delta.y = deltaY



    const threshold = 5

    const notHorizontal = state.direction === 'horizontal' && absDeltaY > absDeltaX;
    const notVertical = state.direction === 'vertical' && absDeltaX > absDeltaY;

    if (state.direction !== 'none' || (notHorizontal && notVertical)) {
      if (absDeltaX < threshold && absDeltaY < threshold) return;
    }

    if ((absDeltaX > threshold || absDeltaY > threshold) && state.direction === 'none') {
      if (absDeltaX > absDeltaY) {
        state.direction = 'horizontal'
      } else {
        state.direction = 'vertical'
        if (this.scrollProp === 'scrollLeft' && state.lockedOffset == null)
          state.lockedOffset = state.startScroll ?? this.#container.scrollLeft
      }
    }

    const axisProp = this.scrollProp
    state.axis = axisProp
    const horizontalAxis = axisProp === 'scrollLeft'
    const verticalAxis = axisProp === 'scrollTop'
    const horizontalDrag = state.direction === 'horizontal'
    const verticalDrag = state.direction === 'vertical'

    const forwarded = new CustomEvent('doctouchmove', {
      detail: {
        touch,
        touchState: state,
      },
      preventDefault: () => e.preventDefault(),
      bubbles: true,
      composed: true
    })
    this.dispatchEvent(forwarded)

    if (state.pinched) return
    state.pinched = globalThis.visualViewport.scale > 1
    if (state.pinched) return

    if (e.touches.length > 1) {
      if (this.#touchScrolled) e.preventDefault()
      return
    }

    const dt = e.timeStamp - state.t || 16.7
    const stepX = state.x - touch.screenX
    const stepY = state.y - touch.screenY
    state.x = touch.screenX
    state.y = touch.screenY
    state.t = e.timeStamp
    state.vx = stepX / dt
    state.vy = stepY / dt

    if (this.scrolled) return

    if (verticalDrag && horizontalAxis) {
      e.preventDefault()
      this.#disableMomentum()
      if (state.lockedOffset == null)
        state.lockedOffset = state.startScroll ?? this.#container.scrollLeft
      this.#container.scrollLeft = state.lockedOffset
      return
    }

    if (verticalDrag && verticalAxis) {
      this.#touchScrolled = true
      return
    }

    if (horizontalDrag && horizontalAxis) {
      this.#touchScrolled = true
      // In paged mode, limit scroll to prevent showing multiple pages
      if (!this.scrolled && state.startPage !== undefined) {
        const { size } = this
        if (size > 0) {
          const startOffset = state.startPage * size
          const minOffset = Math.max(0, startOffset - size) // Allow at most prev page
          const maxOffset = Math.min((this.pages - 1) * size, startOffset + size) // Allow at most next page
          const currentOffset = this.#container[this.scrollProp]
          const signedOffset = this.#rtl ? -currentOffset : currentOffset
          if (signedOffset < minOffset || signedOffset > maxOffset) {
            const clampedOffset = Math.max(minOffset, Math.min(maxOffset, signedOffset))
            this.#container[this.scrollProp] = this.#rtl ? -clampedOffset : clampedOffset
          }
        }
      }
    }
  }
  #onTouchEnd(e) {
    const state = this.#touchState
    this.dispatchEvent(new CustomEvent('doctouchend', {
      detail: {
        touch: e.changedTouches[0],
        touchState: state,
      },
      bubbles: true,
      composed: true
    }))

    this.#touchScrolled = false
    if (this.scrolled) {
      this.#touchState = null
      return
    }

    const verticalLocked = state?.direction === 'vertical'
      && state.axis === 'scrollLeft'
      && state.lockedOffset != null

    if (verticalLocked) {
      // restore original horizontal position and skip snapping to avoid accidental page turns
      this.#container.scrollLeft = state.lockedOffset
      this.#restoreMomentum()
      this.#touchState = null
      if (this.#pendingRelocate) {
        const detail = this.#pendingRelocate
        this.#pendingRelocate = null
        this.dispatchEvent(new CustomEvent('relocate', { detail }))
      }
      return
    }


    // XXX: Firefox seems to report scale as 1... sometimes...?
    // at this point I'm basically throwing `requestAnimationFrame` at
    // anything that doesn't work
    requestAnimationFrame(() => {
      // Skip if footnote is being processed
      if (globalThis.__footnoteProcessing) {
        console.log('[Paginator] onTouchEnd: footnote processing, skipping snap')
        this.#touchState = null
        return
      }
      if (globalThis.visualViewport.scale === 1 && state)
        Promise.resolve(this.snap(state.vx, state.vy, state))
          .finally(() => { this.#touchState = null })
      else this.#touchState = null
    })
  }
  // allows one to process rects as if they were LTR and horizontal
  #getRectMapper() {
    if (this.scrolled) {
      const size = this.viewSize
      const margin = this.#margin
      return this.#vertical
        ? ({ left, right }) =>
          ({ left: size - right - margin, right: size - left - margin })
        : ({ top, bottom }) => ({ left: top + margin, right: bottom + margin })
    }
    const pxSize = this.pages * this.size
    return this.#rtl
      ? ({ left, right }) =>
        ({ left: pxSize - right, right: pxSize - left })
      : this.#vertical
        ? ({ top, bottom }) => ({ left: top, right: bottom })
        : f => f
  }
  async #scrollToRect(rect, reason) {
    if (this.scrolled) {
      const offset = this.#getRectMapper()(rect).left - this.#margin
      return this.#scrollTo(offset, reason)
    }
    const mappedRect = this.#getRectMapper()(rect)
    const left = mappedRect.left
    const pageIndex = Math.floor(left / this.size)
    const pageStart = pageIndex * this.size
    const pageEnd = pageStart + this.size
    const nudgedLeft = Math.min(left + this.#margin / 2, pageEnd - 1)
    const normalizedLeft = Math.max(pageStart, nudgedLeft)
    return this.#scrollToPage(Math.floor(normalizedLeft / this.size) + (this.#rtl ? -1 : 1), reason)
  }
  async #scrollTo(offset, reason, smooth) {
    const element = this.#container
    const { scrollProp, size } = this
    this.#ignoreNativeScroll = true
    const opts = typeof smooth === 'object' ? smooth ?? {} : {}
    const shouldAnimate = opts.animate ?? (reason === 'snap' || smooth === true)
    const easing = opts.easing ?? easeOutSine
    const finish = () => {
      this.#afterScroll(reason)
      this.#ignoreNativeScroll = false
      if (reason === 'snap' || opts.restoreMomentum) {
        const delay = opts.momentumDelay ?? 20
        this.#cancelMomentumTimer()
        this.#momentumTimer = setTimeout(() => {
          this.#restoreMomentum()
        }, delay)
      }
    }
    if (reason === 'snap' || opts.disableMomentum) this.#disableMomentum()

    const previousBehavior = element.style.scrollBehavior
    if (shouldAnimate) element.style.scrollBehavior = 'auto'

    if (Math.abs(element[scrollProp] - offset) < 1) {
      finish()
      element.style.scrollBehavior = previousBehavior
      return
    }

    // FIXME: vertical-rl only, not -lr
    if (this.scrolled && this.#vertical) offset = -offset

    const useAnimation = shouldAnimate && this.hasAttribute('animated')
    const propKey = scrollProp === 'scrollLeft' ? 'left' : 'top'

    if (useAnimation) {
      const distance = Math.abs(element[scrollProp] - offset)
      const baseDuration = 300
      const adaptiveDuration = opts.duration ?? Math.min(
        400,
        Math.max(200, baseDuration * (distance / (size || 1)))
      )

      // Give the snap animation an initial kick based on release velocity so it
      // doesn't start from a standstill and then accelerate.
      const averageSpeed = adaptiveDuration ? distance / adaptiveDuration : 0
      const initialSpeed = Math.abs(opts.initialVelocity ?? 0) * 0.3
      const initialProgress = averageSpeed > 0
        ? Math.min(0.45, (initialSpeed / averageSpeed) * 0.2)
        : 0

      // Prefer native smooth scroll (runs on compositor and can keep 120Hz on Safari)
      const isSafari = /^(?!.*(Chrome|CriOS|Edg|Edge)).*AppleWebKit/i.test(navigator.userAgent)
      const supportsSmooth = 'scrollBehavior' in document.documentElement.style && isSafari
      if (supportsSmooth && !opts.forceJsAnimation) {
        this.#justAnchored = true
        element.style.scrollBehavior = 'smooth'
        element.scrollTo({ [propKey]: offset, behavior: 'smooth' })

        // Resolve when we get close to target or after the expected duration.
        return new Promise(resolve => {
          const start = performance.now()
          const check = now => {
            const done = Math.abs(element[scrollProp] - offset) < 0.5
              || now - start > adaptiveDuration + 120
            if (done) resolve()
            else requestAnimationFrame(check)
          }
          requestAnimationFrame(check)
        }).then(() => {
          element[scrollProp] = offset
          return wait(10)
        }).then(() => {
          finish()
          element.style.scrollBehavior = previousBehavior
        })
      }

      this.#justAnchored = true

      return animate(
        element[scrollProp],
        offset,
        adaptiveDuration,
        easing,
        x => element[scrollProp] = x,
        { initialProgress },
      ).then(() => {
        element[scrollProp] = offset
        return wait(10)
      }).then(() => {
        finish()
        element.style.scrollBehavior = previousBehavior
      }).catch(err => {
        this.#ignoreNativeScroll = false
        this.#restoreMomentum()
        element.style.scrollBehavior = previousBehavior
        throw err
      })
    } else {
      element.style.scrollBehavior = 'auto'
      element[scrollProp] = offset
      finish()
      element.style.scrollBehavior = previousBehavior
    }
  }
  async #scrollToPage(page, reason, smooth) {
    const offset = this.size * (this.#rtl ? -page : page)
    return this.#scrollTo(offset, reason, smooth)
  }
  async scrollToAnchor(anchor, select) {
    this.#anchor = anchor
    const rects = uncollapse(anchor)?.getClientRects?.()
    // if anchor is an element or a range
    if (rects) {
      // when the start of the range is immediately after a hyphen in the
      // previous column, there is an extra zero width rect in that column
      const rect = Array.from(rects)
        .find(r => r.width > 0 && r.height > 0) || rects[0]
      if (!rect) return
      await this.#scrollToRect(rect, 'anchor')
      if (select) this.#selectAnchor()
      return
    }
    // if anchor is a fraction
    if (this.scrolled) {
      await this.#scrollTo(anchor * this.viewSize, 'anchor')
      return
    }
    const { pages } = this
    if (!pages) return
    const textPages = pages - 2
    const newPage = Math.round(anchor * (textPages - 1))
    await this.#scrollToPage(newPage + 1, 'anchor')
  }
  #selectAnchor() {
    const { defaultView } = this.#view.document
    if (this.#anchor.startContainer) {
      const sel = defaultView.getSelection()
      sel.removeAllRanges()
      sel.addRange(this.#anchor)
    }
  }
  #getVisibleRange() {
    if (this.scrolled) return getVisibleRange(this.#view.document,
      this.start + this.#margin, this.end - this.#margin, this.#getRectMapper())
    const size = this.#rtl ? -this.size : this.size
    return getVisibleRange(this.#view.document,
      this.start - size, this.end - size, this.#getRectMapper())
  }
  #afterScroll(reason) {
    const range = this.#getVisibleRange()
    // don't set new anchor if relocation was to scroll to anchor
    if (reason !== 'anchor') this.#anchor = range
    else this.#justAnchored = true

    const index = this.#index
    const detail = { reason, range, index }
    if (this.scrolled) detail.fraction = this.start / this.viewSize
    else if (this.pages > 0) {
      const { page, pages } = this
      // this.#header.style.visibility = page > 1 ? 'visible' : 'hidden'
      detail.fraction = (page - 1) / (pages - 2)
      detail.size = 1 / (pages - 2)
    }
    if (!this.scrolled && reason === 'scroll' && (this.#touchState || this.#touchScrolled)) {
      this.#pendingRelocate = detail
      return
    }

    this.#pendingRelocate = null
    this.dispatchEvent(new CustomEvent('relocate', { detail }))
  }
  async #handleScrollBoundaries() {
    if (!this.scrolled) return
    if (this.#locked || this.#loadingNext || this.#loadingPrev) {
      return
    }

    // Prevent immediate bounce-back after section change
    // Wait at least 500ms before allowing another section change
    const now = Date.now()
    if (now - this.#sectionChangeTime < 500) {
      return
    }

    const threshold = Math.min(50, this.size * 0.05)
    const { start, end, viewSize } = this
    const atEnd = viewSize - end <= threshold
    const atStart = start <= threshold

    if (atEnd) {
      const nextIndex = this.#adjacentIndex(1)
      if (nextIndex != null && nextIndex !== this.#index) {
        console.log('[Paginator] Scroll: loading next section', nextIndex, 'from', this.#index)
        this.#loadingNext = true
        this.#locked = true
        try {
          await this.#goTo({
            index: nextIndex,
            anchor: () => 0,
          })
          this.#sectionChangeTime = Date.now()
          console.log('[Paginator] Next section loaded, now at index', this.#index)
        } catch (e) {
          console.error('[Paginator] Failed to load next section:', e)
        } finally {
          this.#loadingNext = false
          this.#locked = false
        }
      }
    } else if (atStart) {
      const prevIndex = this.#adjacentIndex(-1)
      if (prevIndex != null && prevIndex !== this.#index) {
        console.log('[Paginator] Scroll: loading prev section', prevIndex, 'from', this.#index)
        this.#loadingPrev = true
        this.#locked = true
        try {
          await this.#goTo({
            index: prevIndex,
            anchor: () => 1,
          })
          this.#sectionChangeTime = Date.now()
          console.log('[Paginator] Prev section loaded, now at index', this.#index)
        } catch (e) {
          console.error('[Paginator] Failed to load prev section:', e)
        } finally {
          this.#loadingPrev = false
          this.#locked = false
        }
      }
    }
  }
  async #display(promise) {
    console.log('[Paginator] #display started')
    const { index, src, anchor, onLoad, select } = await promise
    console.log('[Paginator] #display - promise resolved, index:', index, 'src type:', typeof src)
    // Guard against corrupted state from failed section loads
    if (index === undefined || index === null) {
      console.warn('[Paginator] #display: invalid index, skipping')
      return
    }
    this.#index = index
    console.log('[Paginator] #display - set index:', index)
    if (src) {
      console.log('[Paginator] #display - creating view...')
      const view = this.#createView()
      console.log('[Paginator] #display - view created:', view)
      const afterLoad = doc => {
        console.log('[Paginator] #display - afterLoad callback, doc:', !!doc)
        if (doc.head) {
          const $styleBefore = doc.createElement('style')
          doc.head.prepend($styleBefore)
          const $style = doc.createElement('style')
          doc.head.append($style)
          this.#styleMap.set(doc, [$styleBefore, $style])
        }
        console.log('[Paginator] #display - afterLoad calling onLoad')
        onLoad?.({ doc, index })
        console.log('[Paginator] #display - afterLoad done')
      }
      const beforeRender = this.#beforeRender.bind(this)
      console.log('[Paginator] #display - calling view.load()...')
      try {
        await view.load(src, afterLoad, beforeRender)
        console.log('[Paginator] #display - view.load() completed')
      } catch (e) {
        console.error('[Paginator] #display - view.load() error:', e)
        throw e
      }
      console.log('[Paginator] #display - dispatching create-overlayer event')
      this.dispatchEvent(new CustomEvent('create-overlayer', {
        detail: {
          doc: view.document, index,
          attach: overlayer => view.overlayer = overlayer,
        },
      }))
      console.log('[Paginator] #display - setting this.#view')
      this.#view = view
    }
    console.log('[Paginator] #display - calling scrollToAnchor...')
    await this.scrollToAnchor((typeof anchor === 'function'
      ? anchor(this.#view.document) : anchor) ?? 0, select)
    console.log('[Paginator] #display completed')
  }
  #canGoToIndex(index) {
    return index >= 0 && index <= this.sections.length - 1
  }
  async #goTo({ index, anchor, select }) {
    console.log('[Paginator] #goTo called, index:', index, 'current index:', this.#index)
    if (index === this.#index) {
      console.log('[Paginator] #goTo - same index, calling #display directly')
      await this.#display({ index, anchor, select })
    } else {
      console.log('[Paginator] #goTo - different index, loading section...')
      const oldIndex = this.#index
      const onLoad = detail => {
        console.log('[Paginator] onLoad callback fired')
        this.sections[oldIndex]?.unload?.()
        this.setStyles(this.#styles)
        this.dispatchEvent(new CustomEvent('load', { detail }))
      }
      console.log('[Paginator] #goTo - calling section.load() for index:', index)
      try {
        await this.#display(Promise.resolve(this.sections[index].load())
          .then(src => {
            console.log('[Paginator] section.load() succeeded, src type:', typeof src)
            return { index, src, anchor, onLoad, select }
          })
          .catch(e => {
            console.warn('[Paginator] section.load() failed:', e)
            console.warn(new Error(`Failed to load section ${index}`))
            return {}
          }))
        console.log('[Paginator] #goTo - #display completed')
      } catch (e) {
        console.error('[Paginator] #goTo - #display error:', e)
      }
    }
  }
  async goTo(target) {
    console.log('[Paginator] goTo called, locked:', this.#locked, 'target:', target)
    if (this.#locked) {
      console.log('[Paginator] goTo - locked, returning early')
      return
    }
    const resolved = await target
    console.log('[Paginator] goTo resolved:', resolved, 'index:', resolved?.index)
    const canGo = this.#canGoToIndex(resolved?.index)
    console.log('[Paginator] canGoToIndex:', canGo, 'sections.length:', this.sections?.length)
    if (canGo) {
      console.log('[Paginator] calling #goTo...')
      const result = await this.#goTo(resolved)
      console.log('[Paginator] #goTo completed')
      return result
    } else {
      console.log('[Paginator] cannot go to index:', resolved?.index)
    }
  }
  #scrollPrev(distance) {
    if (!this.#view) return true
    if (this.scrolled) {
      if (this.start > 0) return this.#scrollTo(
        Math.max(0, this.start - (distance ?? this.size)), null, { animate: true })
      return true
    }
    if (this.atStart) return
    const page = this.page - 1
    return this.#scrollToPage(page, 'page', { animate: true }).then(() => page <= 0)
  }
  #scrollNext(distance) {
    if (!this.#view) return true
    if (this.scrolled) {
      if (this.viewSize - this.end > 2) return this.#scrollTo(
        Math.min(this.viewSize, distance ? this.start + distance : this.end), null, { animate: true })
      return true
    }
    if (this.atEnd) return
    const page = this.page + 1
    const pages = this.pages
    return this.#scrollToPage(page, 'page', { animate: true }).then(() => page >= pages - 1)
  }
  get atStart() {
    return this.#adjacentIndex(-1) == null && this.page <= 1
  }
  get atEnd() {
    return this.#adjacentIndex(1) == null && this.page >= this.pages - 2
  }
  #adjacentIndex(dir) {
    for (let index = this.#index + dir; this.#canGoToIndex(index); index += dir)
      if (this.sections[index]?.linear !== 'no') return index
  }
  async #turnPage(dir, distance) {
    // Skip if view not ready
    if (!this.#view) {
      console.log('[Paginator] turnPage: view not ready, skipping')
      return
    }
    // Skip if already processing
    if (this.#locked) {
      console.log('[Paginator] turnPage: locked, skipping')
      return
    }
    if (this.#snapping) {
      console.log('[Paginator] turnPage: snapping, skipping')
      return
    }
    // Skip if footnote is being processed
    if (globalThis.__footnoteProcessing) {
      console.log('[Paginator] turnPage: footnote processing, skipping')
      return
    }

    this.#locked = true

    try {
      const prev = dir === -1
      const useFlipAnimation = (this.#pageTurnStyle === 'simulation' || this.#pageTurnStyle === 'cover')
        && !this.scrolled

      console.log('[Paginator] turnPage:', { dir, prev, useFlipAnimation, pageTurnStyle: this.#pageTurnStyle })

      if (useFlipAnimation) {
        // Use 3D flip animation for simulation and cover modes
        const { page, pages, size } = this
        console.log('[Paginator] turnPage flip:', { page, pages, size })

        if (!pages || size === 0) {
          console.log('[Paginator] turnPage: no pages or size')
          return
        }

        // Check boundaries first
        const canGoPrev = page > 1 || this.#adjacentIndex(-1) != null
        const canGoNext = page < pages - 2 || this.#adjacentIndex(1) != null

        if (prev && !canGoPrev) {
          console.log('[Paginator] turnPage: at absolute start')
          return
        }
        if (!prev && !canGoNext) {
          console.log('[Paginator] turnPage: at absolute end')
          return
        }

        // Check if we need to go to adjacent section
        if (prev && page <= 1) {
          console.log('[Paginator] turnPage: going to prev section')
          await this.#goTo({
            index: this.#adjacentIndex(-1),
            anchor: () => 1,
          })
          return
        }
        if (!prev && page >= pages - 2) {
          console.log('[Paginator] turnPage: going to next section')
          await this.#goTo({
            index: this.#adjacentIndex(1),
            anchor: () => 0,
          })
          return
        }

        // Calculate target page within current section
        const targetPage = prev ? page - 1 : page + 1
        console.log('[Paginator] turnPage: targetPage =', targetPage)

        // Use flip animation
        const flipDuration = this.#pageTurnStyle === 'simulation' ? 500 : 400
        let flipData = null

        try {
          flipData = this.#prepareFlipAnimation(dir, flipDuration)
          if (flipData) {
            this.#top.appendChild(flipData.overlay)
          }

          // Scroll to target page instantly
          const pageArg = this.#rtl ? -targetPage : targetPage
          await this.#scrollToPage(pageArg, 'page', { animate: false })

          // Run flip animation
          if (flipData) {
            await flipData.animate()
          }
        } catch (e) {
          console.warn('[Paginator] turnPage flip animation failed:', e)
        } finally {
          if (flipData?.overlay?.parentNode) {
            flipData.overlay.parentNode.removeChild(flipData.overlay)
          }
        }

        return
      }

      // Default behavior for other modes (slide, noAnimation)
      const shouldGo = await (prev ? this.#scrollPrev(distance) : this.#scrollNext(distance))

      if (shouldGo) await this.#goTo({
        index: this.#adjacentIndex(dir),
        anchor: prev ? () => 1 : () => 0,
      })
      if (shouldGo || !this.hasAttribute('animated')) await wait(100)
    } finally {
      this.#locked = false
    }
  }
  prev(distance) {
    return this.#turnPage(-1, distance)
  }
  next(distance) {
    return this.#turnPage(1, distance)
  }
  prevSection() {
    return this.goTo({ index: this.#adjacentIndex(-1) })
  }
  nextSection() {
    return this.goTo({ index: this.#adjacentIndex(1) })
  }
  firstSection() {
    const index = this.sections.findIndex(section => section.linear !== 'no')
    return this.goTo({ index })
  }
  lastSection() {
    const index = this.sections.findLastIndex(section => section.linear !== 'no')
    return this.goTo({ index })
  }
  getContents() {
    if (this.#view) return [{
      index: this.#index,
      overlayer: this.#view.overlayer,
      doc: this.#view.document,
    }]
    return []
  }
  setStyles(styles) {
    this.#styles = styles
    const $$styles = this.#styleMap.get(this.#view?.document)
    if (!$$styles) return
    const [$beforeStyle, $style] = $$styles
    if (Array.isArray(styles)) {
      const [beforeStyle, style] = styles
      $beforeStyle.textContent = beforeStyle
      $style.textContent = style
    } else $style.textContent = styles

    this.#background.style.background = getBackground(this.getAttribute('bgimg-url'))

    // needed because the resize observer doesn't work in Firefox
    this.#view?.document?.fonts?.ready?.then(() => {
      try {
        this.#view?.expand()
      } catch (e) {
        console.error('[Paginator] fonts.ready expand error:', e)
      }
    }).catch(e => console.warn('[Paginator] fonts.ready failed:', e))
  }
  get writingMode() {
    return this.#view?.writingMode
  }
  destroy() {
    this.#observer.unobserve(this)
    this.#view.destroy()
    this.#view = null
    this.sections[this.#index]?.unload?.()
    this.#mediaQuery.removeEventListener('change', this.#mediaQueryListener)
    if (this.#pendingScrollFrame) {
      cancelAnimationFrame(this.#pendingScrollFrame)
      this.#pendingScrollFrame = null
    }
    this.#restoreMomentum()
    this.#pendingRelocate = null
  }
}

customElements.define('foliate-paginator', Paginator)
