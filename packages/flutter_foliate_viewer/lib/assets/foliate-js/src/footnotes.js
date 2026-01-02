const getTypes = el => new Set(el?.getAttributeNS?.('http://www.idpf.org/2007/ops', 'type')?.split(' '))
const getRoles = el => new Set(el?.getAttribute?.('role')?.split(' '))

const isSuper = el => {
    try {
        const { verticalAlign } = getComputedStyle(el)
        return verticalAlign === 'super' || /^\d/.test(verticalAlign)
    } catch {
        return false
    }
}

// 检查是否是小图片（可能是脚注上标图片）
const isSmallImage = el => {
    if (el?.tagName !== 'IMG') return false
    try {
        const style = getComputedStyle(el)
        const width = parseFloat(style.width) || el.width || 0
        const height = parseFloat(style.height) || el.height || 0
        // 脚注图片通常很小（小于 30px）
        return (width > 0 && width < 30) || (height > 0 && height < 30)
    } catch {
        return false
    }
}

// 检查链接是否可能是脚注（包含小图片或上标文本）
const looksLikeFootnote = a => {
    const href = a.getAttribute('href') || ''
    const img = a.querySelector('img')
    const text = a.textContent?.trim()

    console.log('[looksLikeFootnote] checking:', {
        href: href.substring(0, 60),
        hasImg: !!img,
        text: text?.substring(0, 20),
        textLength: text?.length
    })

    // kindle:pos: 链接 - 直接视为脚注（Kindle 格式）
    if (href.startsWith('kindle:pos:')) {
        console.log('[looksLikeFootnote] -> true (kindle:pos link)')
        return true
    }

    // 检查是否包含小图片
    if (img && isSmallImage(img)) {
        console.log('[looksLikeFootnote] -> true (small image)')
        return true
    }

    // 检查文本内容是否像脚注标记（纯数字或 [数字]）
    if (text && /^[\[\(]?\d{1,3}[\]\)]?$/.test(text)) {
        console.log('[looksLikeFootnote] -> true (numeric text)')
        return true
    }

    console.log('[looksLikeFootnote] -> false')
    return false
}

const refTypes = ['biblioref', 'glossref', 'noteref']
const refRoles = ['doc-biblioref', 'doc-glossref', 'doc-noteref']
const isFootnoteReference = a => {
    const types = getTypes(a)
    const roles = getRoles(a)
    const yes = refRoles.some(r => roles.has(r)) || refTypes.some(t => types.has(t))

    const maybe = () => {
        const hasBacklink = types.has('backlink') || roles.has('doc-backlink')
        if (hasBacklink) return false

        const isSuperA = isSuper(a)
        const hasOneChildSuper = a.children.length === 1 && isSuper(a.children[0])
        const parentIsSuper = isSuper(a.parentElement)
        const looksLike = looksLikeFootnote(a)

        const result = isSuperA || hasOneChildSuper || parentIsSuper || looksLike
        console.log('[isFootnoteReference] maybe:', result, '(super:', isSuperA, 'childSuper:', hasOneChildSuper, 'parentSuper:', parentIsSuper, 'looksLike:', looksLike, ')')
        return result
    }

    return { yes, maybe }
}

const getReferencedType = el => {
    const types = getTypes(el)
    const roles = getRoles(el)
    return roles.has('doc-biblioentry') || types.has('biblioentry') ? 'biblioentry'
        : roles.has('definition') || types.has('glossdef') ? 'definition'
            : roles.has('doc-endnote') || types.has('endnote') || types.has('rearnote') ? 'endnote'
                : roles.has('doc-footnote') || types.has('footnote') ? 'footnote'
                    : roles.has('note') || types.has('note') ? 'note' : null
}

const isInline = 'a, span, sup, sub, em, strong, i, b, small, big'
const extractFootnote = (doc, anchor) => {
    console.log('[extractFootnote] called')
    let el = anchor(doc)
    console.log('[extractFootnote] anchor result:', el, 'tagName:', el?.tagName, 'innerHTML:', el?.innerHTML?.substring(0, 100))
    if (!el) {
        console.error('[extractFootnote] anchor returned null!')
        throw new Error('Anchor element not found')
    }
    const target = el
    while (el.matches(isInline)) {
        console.log('[extractFootnote] traversing up from:', el.tagName)
        const parent = el.parentElement
        if (!parent) break
        el = parent
    }
    console.log('[extractFootnote] final element:', el?.tagName, 'innerHTML:', el?.innerHTML?.substring(0, 200))
    if (el === doc.body) {
        console.log('[extractFootnote] reached body, checking sibling')
        const sibling = target.nextElementSibling
        if (sibling && !sibling.matches(isInline)) {
            console.log('[extractFootnote] returning sibling:', sibling?.tagName)
            return sibling
        }
        throw new Error('Failed to extract footnote')
    }
    return el
}

export class FootnoteHandler extends EventTarget {
    detectFootnotes = true
    // 标记是否正在处理脚注，用于阻止翻页（同时设置到 window 以便 paginator 检查）
    static get processing() { return globalThis.__footnoteProcessing ?? false }
    static set processing(value) { globalThis.__footnoteProcessing = value }

    // 直接加载脚注内容（快速版本，不使用 foliate-view）
    async #showFragmentDirect(book, { index, anchor }, href, anchorRect) {
        console.log('[FootnoteHandler] #showFragmentDirect called:', { index, href, anchorRect })
        try {
            const section = book.sections[index]
            if (!section) {
                throw new Error(`Section ${index} not found`)
            }

            // 直接创建文档
            const doc = await section.createDocument()
            console.log('[FootnoteHandler] document created, body length:', doc?.body?.innerHTML?.length)

            // 提取脚注元素
            const el = anchor(doc)
            console.log('[FootnoteHandler] anchor element:', el?.tagName, 'innerHTML:', el?.innerHTML?.substring(0, 200))

            if (!el) {
                throw new Error('Footnote element not found')
            }

            // 获取脚注 HTML 内容
            let htmlContent = ''
            if (el.matches('li, aside')) {
                htmlContent = el.innerHTML
            } else {
                htmlContent = el.outerHTML
            }

            console.log('[FootnoteHandler] extracted HTML content length:', htmlContent.length)

            // 触发事件，传递 HTML 内容和锚点位置
            const type = getReferencedType(el)
            const detail = { htmlContent, href, type, target: el, anchorRect }
            this.dispatchEvent(new CustomEvent('footnote-content', { detail }))

        } catch (e) {
            console.error('[FootnoteHandler] error in #showFragmentDirect:', e)
            throw e
        }
    }

    // 使用 foliate-view 显示脚注（原版本，作为备用）
    #showFragment(book, { index, anchor }, href) {
        console.log('[FootnoteHandler] #showFragment called:', { index, href })
        const view = document.createElement('foliate-view')
        return new Promise((resolve, reject) => {
            view.addEventListener('load', e => {
                console.log('[FootnoteHandler] view load event received')
                try {
                    const { doc } = e.detail
                    console.log('[FootnoteHandler] doc body innerHTML length:', doc?.body?.innerHTML?.length)
                    const el = anchor(doc)
                    console.log('[FootnoteHandler] anchor element:', el, 'tagName:', el?.tagName, 'innerHTML:', el?.innerHTML?.substring(0, 200))
                    const type = getReferencedType(el)
                    const hidden = el?.matches?.('aside') && type === 'footnote'
                    console.log('[FootnoteHandler] type:', type, 'hidden:', hidden)
                    if (el) {
                        const range = el.startContainer ? el : doc.createRange()
                        if (!el.startContainer) {
                            if (el.matches('li, aside')) range.selectNodeContents(el)
                            else range.selectNode(el)
                        }
                        const frag = range.extractContents()
                        console.log('[FootnoteHandler] extracted fragment childNodes:', frag.childNodes?.length)
                        doc.body.replaceChildren()
                        doc.body.appendChild(frag)
                        console.log('[FootnoteHandler] after append, body innerHTML:', doc.body.innerHTML?.substring(0, 200))
                    } else {
                        console.log('[FootnoteHandler] el is null/undefined!')
                    }
                    const detail = { view, href, type, hidden, target: el }
                    this.dispatchEvent(new CustomEvent('render', { detail }))
                    resolve()
                } catch (e) {
                    console.error('[FootnoteHandler] error in load handler:', e)
                    reject(e)
                }
            })
            view.open(book)
                .then(() => {
                    console.log('[FootnoteHandler] view.open completed, dispatching before-render')
                    this.dispatchEvent(new CustomEvent('before-render', { detail: { view } }))
                })
                .then(() => {
                    console.log('[FootnoteHandler] calling view.goTo with index:', index)
                    return view.goTo(index)
                })
                .catch(e => {
                    console.error('[FootnoteHandler] error in promise chain:', e)
                    reject(e)
                })
        })
    }
    // 获取锚点元素的位置（考虑 iframe 和 transform）
    #getAnchorRect(a) {
        try {
            const rect = a.getBoundingClientRect()
            const rootNode = a.getRootNode?.()
            const frameElement = rootNode?.defaultView?.frameElement

            let offsetX = 0, offsetY = 0
            let scaleX = 1, scaleY = 1

            if (frameElement) {
                const frameRect = frameElement.getBoundingClientRect()
                offsetX = frameRect.left
                offsetY = frameRect.top

                // 检查 transform scale
                const transform = getComputedStyle(frameElement).transform
                const matches = transform.match(/matrix\((.+)\)/)
                if (matches) {
                    [scaleX, , , scaleY] = matches[1].split(/\s*,\s*/).map(Number)
                }
            }

            return {
                left: offsetX + rect.left * scaleX,
                top: offsetY + rect.top * scaleY,
                right: offsetX + rect.right * scaleX,
                bottom: offsetY + rect.bottom * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            }
        } catch (e) {
            console.warn('[FootnoteHandler] failed to get anchor rect:', e)
            return null
        }
    }

    handle(book, e) {
        const { a, href } = e.detail
        const { yes, maybe } = isFootnoteReference(a)
        console.log('[FootnoteHandler] checking:', href, 'yes:', yes, 'maybe:', maybe(), 'detectFootnotes:', this.detectFootnotes)

        // 获取锚点位置
        const anchorRect = this.#getAnchorRect(a)
        console.log('[FootnoteHandler] anchorRect:', anchorRect)

        if (yes) {
            console.log('[FootnoteHandler] is footnote reference, preventing default')
            e.preventDefault()
            // 设置标志阻止翻页
            FootnoteHandler.processing = true
            return Promise.resolve(book.resolveHref(href)).then(target =>
                this.#showFragmentDirect(book, target, href, anchorRect))
                .finally(() => {
                    // 延迟一点再重置标志，确保脚注弹框已显示
                    setTimeout(() => { FootnoteHandler.processing = false }, 100)
                })
        }
        else if (this.detectFootnotes && maybe()) {
            console.log('[FootnoteHandler] detected as footnote, preventing default')
            e.preventDefault()
            // 设置标志阻止翻页
            FootnoteHandler.processing = true
            return Promise.resolve(book.resolveHref(href)).then(({ index, anchor }) => {
                const target = { index, anchor: doc => extractFootnote(doc, anchor) }
                return this.#showFragmentDirect(book, target, href, anchorRect)
            }).finally(() => {
                // 延迟一点再重置标志，确保脚注弹框已显示
                setTimeout(() => { FootnoteHandler.processing = false }, 100)
            })
        }
        console.log('[FootnoteHandler] not a footnote, will navigate')
    }
}
