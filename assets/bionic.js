/*
 * claude-bionic-reading - drop-in bionic renderer for an HTML page.
 *
 * Paste this inside a <script> tag at the end of an artifact. It walks the
 * document's text nodes and wraps the fixation prefix of each word in
 * <b class="bionic">, leaving the DOM structure, the text content and every
 * style exactly as they were. Code is never touched.
 *
 * Opt a subtree out with data-no-bionic. Re-running is safe: already-processed
 * text is skipped, and a MutationObserver keeps dynamic content in step.
 */
(function () {
  'use strict';

  /* How much of each word is bolded: 'default', '25', '40' or '75'. Set it
   * before this script runs with either
   *     window.BIONIC_STRENGTH = '75';
   * or  <html data-bionic-strength="75">
   * 'default' is a tuned table - roughly two fifths of the word with a
   * five-letter ceiling, so a long word does not grow an absurd prefix. */
  var RATIOS = { '25': 0.25, '40': 0.40, '75': 0.75 };
  var strength = 'default';

  function setStrength(s) { strength = String(s || 'default'); }

  /* Read at each call rather than once at load, so the strength can be changed
   * while the page is running. */
  function currentStrength() {
    if (typeof window !== 'undefined' && window.BIONIC_STRENGTH) {
      return String(window.BIONIC_STRENGTH);
    }
    if (typeof document !== 'undefined' && document.documentElement) {
      var a = document.documentElement.getAttribute('data-bionic-strength');
      if (a) return a;
    }
    return strength;
  }

  /* Two invariants hold at every strength: a one-letter word is never bolded,
   * and no word is ever bolded whole - a fully bolded word is indistinguishable
   * from real emphasis. */
  function prefixLetters(n) {
    if (n <= 1) return 0;
    var r = RATIOS[currentStrength()];
    if (r === undefined) {
      if (n <= 3) return 1;
      if (n <= 5) return 2;
      if (n <= 7) return 3;
      if (n <= 9) return 4;
      return 5;
    }
    return Math.min(n - 1, Math.max(1, Math.floor(n * r + 0.5)));
  }

  /* Elements whose text is code, markup, or already bold. Bolding inside a
   * bold run renders identically to the run, so there is nothing to gain. */
  var SKIP_TAGS = /^(CODE|PRE|KBD|SAMP|VAR|TT|SCRIPT|STYLE|TEXTAREA|NOSCRIPT|SVG|MATH|B|STRONG|TITLE|OPTION)$/;

  var WORD = /[^\W\d_]+(?:['’][^\W\d_]+)*/gu;

  /* A whitespace-delimited chunk that looks like code, a path, a URL or an
   * identifier rather than a word of prose. */
  var NOT_PROSE = /[_\\/@]|:{2}|\(\)|https?:|www\.|\d/;
  var FILENAME = /^[\w.-]+\.(?:js|mjs|cjs|jsx|ts|tsx|py|rb|go|rs|java|kt|swift|c|h|cc|cpp|cs|php|pl|sh|bash|zsh|fish|ps1|sql|md|mdx|rst|txt|json|jsonc|ya?ml|toml|ini|cfg|conf|env|lock|html?|css|scss|sass|less|xml|svg|png|jpe?g|gif|webp|pdf|csv|tsv|zip|tar|gz|log|plist|gradle)$/i;
  var EDGE = /^[,;:!?()[\]{}"'‘’“”]+|[,;:!?()[\]{}"'‘’“”.]+$/g;

  function shouldSkipChunk(chunk) {
    if (NOT_PROSE.test(chunk)) return true;
    var core = chunk.replace(EDGE, '');
    var first = core.charAt(0);
    if (first === '.' || first === '~' || first === '/') return true;   /* a path */
    if (FILENAME.test(core)) return true;
    /* Acronyms: **AP**I reads worse than API left whole. */
    if (core.length >= 2 && core === core.toUpperCase() && /[^\W\d_]/u.test(core)) {
      return true;
    }
    return false;
  }

  /* Bold the first prefixLetters(n) letters of the token. */
  function split(token) {
    var letters = 0, i;
    for (i = 0; i < token.length; i++) {
      if (/[^\W\d_]/u.test(token[i])) letters++;
    }
    var want = prefixLetters(letters);
    if (want <= 0) return ['', token];
    var taken = 0, cut = token.length;
    for (i = 0; i < token.length; i++) {
      if (/[^\W\d_]/u.test(token[i])) taken++;
      if (taken >= want) { cut = i + 1; break; }
    }
    /* A bionic run is always followed by a letter - the signature --strip
     * recognises. Without this a high strength cuts don't as **don**'t. */
    while (cut > 0 && (cut >= token.length || !/[^\W\d_]/u.test(token[cut]))) cut--;
    if (cut <= 0) return ['', token];
    return [token.slice(0, cut), token.slice(cut)];
  }

  function inSkippedSubtree(node) {
    for (var el = node.parentNode; el && el.nodeType === 1; el = el.parentNode) {
      if (SKIP_TAGS.test(el.nodeName)) return true;
      if (el.hasAttribute('data-no-bionic')) return true;
      if (el.hasAttribute('data-bionic')) return true;
      if (el.isContentEditable) return true;
    }
    return false;
  }

  /* Replace one text node with a fragment carrying the same characters, some
   * of them wrapped. Returns null when the node holds nothing to bold. */
  function fragmentFor(text) {
    var frag = null, cursor = 0, m;
    WORD.lastIndex = 0;
    while ((m = WORD.exec(text)) !== null) {
      var start = m.index, token = m[0];

      /* Widen to the whitespace-delimited chunk this token sits in, so that
       * ./src/app.js and API_KEY are judged whole rather than letter-run by
       * letter-run. */
      var l = start, r = start + token.length;
      while (l > 0 && !/\s/.test(text[l - 1])) l--;
      while (r < text.length && !/\s/.test(text[r])) r++;
      if (shouldSkipChunk(text.slice(l, r))) {
        WORD.lastIndex = r;
        continue;
      }

      var parts = split(token);
      if (!parts[0]) continue;

      if (!frag) frag = document.createDocumentFragment();
      if (start > cursor) {
        frag.appendChild(document.createTextNode(text.slice(cursor, start)));
      }
      var b = document.createElement('b');
      b.className = 'bionic';
      b.setAttribute('data-bionic', '');
      b.textContent = parts[0];
      frag.appendChild(b);
      if (parts[1]) frag.appendChild(document.createTextNode(parts[1]));
      cursor = start + token.length;
    }
    if (frag && cursor < text.length) {
      frag.appendChild(document.createTextNode(text.slice(cursor)));
    }
    return frag;
  }

  function walk(root) {
    if (!root || (root.nodeType !== 1 && root.nodeType !== 11)) return;
    var nodes = [];
    var it = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        if (!n.nodeValue || !/[^\W\d_]/u.test(n.nodeValue)) {
          return NodeFilter.FILTER_REJECT;
        }
        return inSkippedSubtree(n) ? NodeFilter.FILTER_REJECT
                                   : NodeFilter.FILTER_ACCEPT;
      }
    });
    /* Collect first: replacing nodes while walking invalidates the walker. */
    for (var n = it.nextNode(); n; n = it.nextNode()) nodes.push(n);
    for (var i = 0; i < nodes.length; i++) {
      var frag = fragmentFor(nodes[i].nodeValue);
      if (frag && nodes[i].parentNode) nodes[i].parentNode.replaceChild(frag, nodes[i]);
    }
  }

  function addStyle() {
    if (document.getElementById('bionic-style')) return;
    var s = document.createElement('style');
    s.id = 'bionic-style';
    /* bolder is relative, so a fixation stays heavier than whatever weight it
     * sits in, and inherits every other property untouched. */
    s.textContent = 'b.bionic{font-weight:bolder;}';
    (document.head || document.documentElement).appendChild(s);
  }

  function start() {
    addStyle();
    walk(document.body);

    var queue = [], scheduled = false;
    var obs = new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var added = records[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var n = added[j];
          if (n.nodeType === 1) queue.push(n);
          else if (n.nodeType === 3 && !inSkippedSubtree(n)) queue.push(n.parentNode);
        }
      }
      if (scheduled || !queue.length) return;
      scheduled = true;
      requestAnimationFrame(function () {
        scheduled = false;
        var batch = queue.splice(0, queue.length);
        obs.disconnect();
        for (var k = 0; k < batch.length; k++) walk(batch[k]);
        obs.observe(document.body, { childList: true, subtree: true });
      });
    });
    obs.observe(document.body, { childList: true, subtree: true });
  }

  if (typeof document === 'undefined') {
    /* Required from node by the tests. Expose the pure parts, touch nothing. */
    if (typeof module !== 'undefined' && module.exports) {
      module.exports = { prefixLetters: prefixLetters, split: split,
                         shouldSkipChunk: shouldSkipChunk,
                         setStrength: setStrength };
    }
  } else {
    /* A small public API, for a page that wants to re-render part of itself or
     * switch strength at runtime. */
    window.bionic = { walk: walk, setStrength: setStrength,
                      split: split, prefixLetters: prefixLetters };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', start);
    } else {
      start();
    }
  }
})();
