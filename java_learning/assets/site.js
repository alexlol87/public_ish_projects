// Shared layout: sidebar nav, per-page table of contents, theme toggle, pager, Mermaid and highlight.js setup.
const PAGES = [
  { group: 'Start here' },
  { href: 'index.html', title: 'Home & glossary' },
  { href: 'spring-basics.html', title: 'Spring Boot basics' },
  { group: 'Concurrency' },
  { href: 'multithreading.html', title: '1. Multithreading (Java 25)' },
  { href: 'webflux.html', title: '2. Reactive WebFlux & Netty' },
  { href: 'sync-tools.html', title: '3. Locks, atomics, futures, virtual threads' },
  { href: 'producer-consumer.html', title: '4. Producer-consumer & utilities' },
  { group: '5. Interview questions' },
  { href: 'q-spring.html', title: 'Q31–45 Spring Framework' },
  { href: 'q-distributed.html', title: 'Q46–55 Distributed & caching' },
  { href: 'q-rabbitmq.html', title: 'Q56–65 RabbitMQ' },
  { href: 'q-nosql-sql.html', title: 'Q66–80 NoSQL, ES, SQL & Oracle' },
  { href: 'q-tools.html', title: 'Q81–90 Maven, Jenkins, Git…' },
];

(function () {
  try { const t = localStorage.getItem('theme'); if (t) document.documentElement.dataset.theme = t; } catch (e) {}
})();

function isDark() {
  const t = document.documentElement.dataset.theme;
  if (t) return t === 'dark';
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

document.addEventListener('DOMContentLoaded', () => {
  const here = location.pathname.split('/').pop() || 'index.html';
  const main = document.querySelector('main');

  // ids for h2 so the TOC can link to them
  const h2s = [...main.querySelectorAll('h2')];
  h2s.forEach((h, i) => { if (!h.id) h.id = 's' + (i + 1); });

  const nav = document.createElement('nav');
  nav.className = 'side';
  let html = '<a class="brand" href="index.html">☕ Java & Spring Learning</a>';
  for (const p of PAGES) {
    if (p.group) { html += `<div class="group">${p.group}</div>`; continue; }
    const active = p.href === here;
    html += `<a class="page${active ? ' active' : ''}" href="${p.href}">${p.title}</a>`;
    if (active && h2s.length) {
      html += '<div class="toc">' + h2s.map(h => `<a href="#${h.id}">${h.textContent}</a>`).join('') + '</div>';
    }
  }
  html += '<button class="theme-btn" type="button">Toggle light / dark</button>';
  nav.innerHTML = html;

  const layout = document.createElement('div');
  layout.className = 'layout';
  main.parentNode.insertBefore(layout, main);
  layout.appendChild(nav);
  layout.appendChild(main);

  const top = document.createElement('div');
  top.className = 'topbar';
  top.innerHTML = '<button type="button" aria-label="Open menu">☰ Menu</button><b>Java & Spring Learning</b>';
  document.body.insertBefore(top, layout);
  top.querySelector('button').onclick = () => nav.classList.toggle('open');
  nav.addEventListener('click', e => { if (e.target.tagName === 'A') nav.classList.remove('open'); });

  nav.querySelector('.theme-btn').onclick = () => {
    const next = isDark() ? 'light' : 'dark';
    try { localStorage.setItem('theme', next); } catch (e) {}
    location.reload(); // Mermaid diagrams are rendered once, so re-render them with the new theme
  };

  // previous / next page
  const list = PAGES.filter(p => p.href);
  const idx = list.findIndex(p => p.href === here);
  if (idx >= 0) {
    const pager = document.createElement('div');
    pager.className = 'pager';
    pager.innerHTML = (idx > 0 ? `<a href="${list[idx - 1].href}">← ${list[idx - 1].title}</a>` : '<span></span>') +
      (idx < list.length - 1 ? `<a href="${list[idx + 1].href}">${list[idx + 1].title} →</a>` : '<span></span>');
    main.appendChild(pager);
  }

  // expand / collapse all answers on question pages
  const qas = main.querySelectorAll('details.qa');
  if (qas.length) {
    const tools = document.createElement('div');
    tools.className = 'tools';
    tools.innerHTML = '<button type="button" data-a="open">Show all answers</button><button type="button" data-a="close">Hide all answers</button>';
    tools.onclick = e => { const a = e.target.dataset.a; if (a) qas.forEach(d => d.open = a === 'open'); };
    main.querySelector('h1').after(tools);
    // open the question a link points to
    if (location.hash) { const t = document.querySelector(location.hash); if (t && t.tagName === 'DETAILS') t.open = true; }
  }

  if (window.hljs) document.querySelectorAll('pre code').forEach(el => window.hljs.highlightElement(el));
  if (window.mermaid) {
    window.mermaid.initialize({ startOnLoad: false, theme: isDark() ? 'dark' : 'default', securityLevel: 'strict' });
    // Mermaid can't measure diagrams inside closed <details>, so render those when they are opened.
    const visible = [...document.querySelectorAll('pre.mermaid')].filter(el => !el.closest('details:not([open])'));
    if (visible.length) window.mermaid.run({ nodes: visible });
    document.querySelectorAll('details').forEach(d => d.addEventListener('toggle', () => {
      const todo = [...d.querySelectorAll('pre.mermaid:not([data-processed])')].filter(el => !el.closest('details:not([open])'));
      if (d.open && todo.length) window.mermaid.run({ nodes: todo });
    }));
  }
});
