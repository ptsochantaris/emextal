var lastDocHeight = 0;
const historyElement = document.getElementById("__emeltal_internal_history");
const newElement = document.getElementById("__emeltal_internal_new");

function reset() {
    historyElement.innerHTML = "";
    liveThinkOpen = {};
}

function decorate(root, live) {
    root.querySelectorAll("pre code").forEach(function(code){
        const tagged = /language-[A-Za-z0-9+#-]+/.test(code.className);
        hljs.highlightElement(code);
        // Fall back to highlight.js's auto-detection only when the
        // markup didn't specify a language, and only if the guess
        // is confident enough to be useful.
        if (!tagged && code.result && code.result.language && code.result.relevance >= 5) {
            code.dataset.detectedLanguage = code.result.language;
        }
    });
    addCopyButtons(root);
    decorateThinkBlocks(root, live);
}

// Icons reference the <symbol> sprite defined in log.html. Using <use> keeps
// the markup inheriting currentColor, so the icons still adopt their control's
// text colour.
function icon(id, size) {
    return '<svg class="ui-icon" width="' + size + '" height="' + size + '"><use href="#' + id + '"></use></svg>';
}

const copyIcon = icon("icon-copy", 15);
const checkIcon = icon("icon-check", 15);
const chevronIcon = icon("icon-chevron", 13);
const thoughtIcon = icon("icon-thought", 13);

// Is there any meaningful content after this node? While a <think> is
// still being generated it is unclosed, so the browser nests the rest
// of the output inside it and there are no following siblings yet.
// Once </think> arrives, the answer appears as a sibling after it.
function hasContentAfter(node) {
    let sibling = node.nextSibling;
    while (sibling) {
        if (sibling.nodeType === Node.TEXT_NODE) {
            if (sibling.textContent.trim()) {
                return true;
            }
        } else if (sibling.nodeType === Node.ELEMENT_NODE) {
            if (sibling.textContent.trim() || sibling.querySelector("img")) {
                return true;
            }
        }
        sibling = sibling.nextSibling;
    }
    return false;
}

// The live stream's innerHTML is rebuilt on every token, so a live
// think bubble is recreated each time. Remember whether the user has
// expanded it (keyed by its order in the stream) and restore that
// state, otherwise it would snap shut on the next token.
var liveThinkOpen = {};

// Wrap each <think> in a collapsed bubble. In the live stream the
// currently-generating thought shows an animated "Thinking..." spinner;
// once it is followed by answer text (or committed to history) it
// settles into a static, expandable "Thought" bubble.
function decorateThinkBlocks(root, live) {
    root.querySelectorAll("think").forEach(function(think, index){
        if (think.closest(".think-bubble")) {
            return;
        }
        const active = live && !hasContentAfter(think);

        const details = document.createElement("details");
        details.className = "think-bubble";

        const summary = document.createElement("summary");
        summary.className = "think-summary";
        // The live block is rebuilt on every token, recreating the spinner and
        // restarting its CSS animation. Phase-align each new spinner to a global
        // clock with a negative animation-delay so it continues seamlessly
        // instead of snapping back to frame zero. (Must match the CSS duration.)
        const spinPhase = (performance.now() % 800) / 1000;
        const icon = active
            ? '<span class="think-spinner" style="animation-delay:-' + spinPhase + 's"></span>'
            : thoughtIcon;
        summary.innerHTML = icon
            + '<span class="think-label">' + (active ? "Thinking..." : "Thought") + "</span>"
            + '<span class="think-chevron">' + chevronIcon + "</span>";

        think.parentNode.insertBefore(details, think);
        details.appendChild(summary);
        details.appendChild(think);

        // Restore the remembered expanded state. This also carries the user's
        // choice across the live -> committed transition: addHistory() renders
        // the finished turn (live === false) before setNewText("") clears the
        // remembered state, so a thought opened while streaming stays open once
        // the reply is done.
        details.open = !!liveThinkOpen[index];

        if (live) {
            // Track toggles only while streaming; committed history bubbles keep
            // their own persistent open state. Wired after the programmatic open
            // above so it doesn't echo back into the map.
            details.addEventListener("toggle", function(){
                liveThinkOpen[index] = details.open;
            });
        }
    });
}

const languageNames = {
    js: "JavaScript", javascript: "JavaScript", jsx: "JavaScript",
    ts: "TypeScript", typescript: "TypeScript", tsx: "TypeScript",
    py: "Python", python: "Python",
    rb: "Ruby", ruby: "Ruby",
    sh: "Shell", bash: "Shell", shell: "Shell", zsh: "Shell",
    objc: "Objective-C", objectivec: "Objective-C",
    cpp: "C++", "c++": "C++", cc: "C++",
    cs: "C#", csharp: "C#",
    c: "C", swift: "Swift", perl: "Perl", java: "Java",
    kotlin: "Kotlin", kt: "Kotlin", go: "Go", golang: "Go",
    rust: "Rust", rs: "Rust", php: "PHP", html: "HTML", xml: "XML",
    css: "CSS", scss: "SCSS", json: "JSON", yaml: "YAML", yml: "YAML",
    md: "Markdown", markdown: "Markdown", sql: "SQL",
    diff: "Diff", dockerfile: "Dockerfile", toml: "TOML",
    plaintext: "", text: ""
};

function languageLabel(code) {
    const match = code.className.match(/language-([A-Za-z0-9+#-]+)/);
    const key = (match ? match[1] : (code.dataset.detectedLanguage || "")).toLowerCase();
    if (!key) {
        return "";
    }
    if (key in languageNames) {
        return languageNames[key];
    }
    return key.charAt(0).toUpperCase() + key.slice(1);
}

function addCopyButtons(root) {
    root.querySelectorAll("pre").forEach(function(pre){
        if (pre.querySelector(".copy-button")) {
            return;
        }
        const code = pre.querySelector("code");
        if (!code) {
            return;
        }
        const holder = document.createElement("div");
        holder.className = "copy-holder";

        function setCollapsed(collapsed) {
            pre.classList.toggle("collapsed", collapsed);
            toggle.setAttribute("aria-expanded", collapsed ? "false" : "true");
            toggle.title = collapsed ? "Expand" : "Collapse";
        }

        const toggle = document.createElement("button");
        toggle.className = "collapse-button";
        toggle.type = "button";
        toggle.title = "Collapse";
        toggle.setAttribute("aria-label", "Toggle code block");
        toggle.setAttribute("aria-expanded", "true");
        toggle.innerHTML = chevronIcon;
        toggle.addEventListener("click", function(){
            setCollapsed(!pre.classList.contains("collapsed"));
        });
        holder.appendChild(toggle);

        const label = languageLabel(code);
        if (label) {
            const tag = document.createElement("span");
            tag.className = "code-lang";
            tag.textContent = label;
            tag.addEventListener("click", function(){
                setCollapsed(!pre.classList.contains("collapsed"));
            });
            holder.appendChild(tag);
        }

        const button = document.createElement("button");
        button.className = "copy-button";
        button.type = "button";
        button.title = "Copy";
        button.setAttribute("aria-label", "Copy");
        button.innerHTML = copyIcon;
        button.addEventListener("click", function(){
            copyText(code.textContent, button);
        });

        holder.appendChild(button);
        pre.insertBefore(holder, pre.firstChild);
    });
}

function copyText(text, button) {
    function finished() {
        button.innerHTML = checkIcon;
        button.classList.add("copied");
        setTimeout(function(){
            button.innerHTML = copyIcon;
            button.classList.remove("copied");
        }, 1200);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(finished).catch(function(){
            fallbackCopy(text, finished);
        });
    } else {
        fallbackCopy(text, finished);
    }
}

function fallbackCopy(text, finished) {
    const area = document.createElement("textarea");
    area.value = text;
    area.style.position = "fixed";
    area.style.top = "0";
    area.style.left = "0";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.focus();
    area.select();
    try {
        document.execCommand("copy");
    } catch (e) {}
    document.body.removeChild(area);
    finished();
}

function addHistory(id, html) {
    const newDiv = document.createElement('div');
    newDiv.className = 'turn';
    newDiv.id = id;
    newDiv.innerHTML = html;
    decorate(newDiv, false);
    historyElement.appendChild(newDiv);
    // Clear the live buffer in the same synchronous pass. On completion the
    // committed turn is appended here and the live copy is cleared by a separate
    // setNewText("") call; doing it together avoids a one-frame paint where the
    // turn appears in both buffers (a brief flash of duplicated content).
    newElement.innerHTML = "";
    return false;
}

function setNewText(html) {
    // Empty means the live turn has been committed to history; forget
    // the remembered bubble state so the next turn starts collapsed.
    if (!html) {
        liveThinkOpen = {};
    }

    newElement.innerHTML = html;

    decorate(newElement, true);

    const newDocHeight = document.body.scrollHeight;
    const atBottom = (window.innerHeight + Math.round(window.scrollY) + 40) >= newDocHeight;
    const shouldScroll = atBottom && (lastDocHeight != newDocHeight);
    if (shouldScroll) {
        lastDocHeight = newDocHeight
        window.scrollTo(0, newDocHeight);
    }
    return shouldScroll;
}
