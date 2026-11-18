// Painel do Jarvis: monta numa caixa qualquer (a página própria fora de reunião, ou a aba Jarvis do meeting.html).
// O Swift chama window.jarvis.* e recebe {do: ...} pelo handler "jarvis". Textos fixos já em português.
(() => {
  if (window.jarvis) return;
  const post = m => window.webkit?.messageHandlers.jarvis?.postMessage(m);
  const css = `
.jv{display:flex;flex-direction:column;gap:8px;height:100%;min-height:0;font:13px/1.45 -apple-system,system-ui,sans-serif;color:#f5f5f7}
.jv .topo{display:flex;align-items:center;gap:8px;flex:none}
.jv .topo b{flex:1;font-size:13px}
.jv .estado{font-size:11px;color:#a1a1a6}
.jv .ponto{width:8px;height:8px;border-radius:50%;background:#8e8e93;flex:none}
.jv[data-fase=ouvindo] .ponto{background:#ff453a;animation:jvpulso 1s infinite}
.jv[data-fase=pensando] .ponto,.jv[data-fase=confirmando] .ponto{background:#0a84ff;animation:jvpulso 1s infinite}
@keyframes jvpulso{50%{opacity:.35}}
.jv .rolo{flex:1;min-height:0;overflow:auto;display:flex;flex-direction:column;gap:8px}
.jv .rolo::-webkit-scrollbar{display:none}
.jv .msg{padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);white-space:pre-wrap;-webkit-user-select:text;user-select:text}
.jv .msg.eu{background:rgba(10,132,255,.22);align-self:flex-end;max-width:90%}
.jv .msg .hora{display:block;font-size:10px;color:#8e8e93;margin-bottom:2px}
.jv .msg .det{margin-top:6px;font-size:12px;color:#d1d1d6}
.jv .msg .det ul{margin:4px 0;padding-left:18px}
.jv .passos{font-size:11.5px;color:#a1a1a6}
.jv .legenda{min-height:18px;color:#f5f5f7;font-size:14px}
.jv .legenda.vazia{color:#8e8e93}
.jv .cartao{padding:10px;border-radius:12px;background:rgba(255,159,10,.16);box-shadow:inset 0 0 0 .5px rgba(255,159,10,.5)}
.jv .cartao p{margin:0 0 8px}
.jv .cartao div{display:flex;gap:8px}
.jv button{border:0;border-radius:999px;background:rgba(255,255,255,.1);color:inherit;font:inherit;padding:6px 12px;cursor:pointer}
.jv button.azul{background:#0a84ff;font-weight:500}
.jv form{display:flex;gap:6px;flex:none}
.jv input{flex:1;min-width:0;background:rgba(0,0,0,.18);border:0;box-shadow:inset 0 0 0 .5px rgba(255,255,255,.12);border-radius:10px;padding:8px 10px;color:inherit;font:inherit;outline:none;-webkit-user-select:text;user-select:text}
.jv input:focus{box-shadow:inset 0 0 0 1px rgba(10,132,255,.7)}
.jv .erro{color:#ff9f0a;font-size:12px}
.jv details summary{cursor:pointer;color:#a1a1a6;font-size:11.5px}
[hidden]{display:none!important}`;
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  // markdown curto do detalhe_md: negrito, itens e quebras; tudo escapado antes
  const md = t => {
    const esc = String(t || '').replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
    const linhas = esc.split('\n');
    let html = '', lista = false;
    for (const l of linhas) {
      const item = /^\s*[-*] (.*)/.exec(l);
      if (item && !lista) { html += '<ul>'; lista = true; }
      if (!item && lista) { html += '</ul>'; lista = false; }
      const conteudo = (item ? item[1] : l).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
      html += item ? `<li>${conteudo}</li>` : conteudo + '<br>';
    }
    return html + (lista ? '</ul>' : '');
  };
  const hora = d => d ? new Date(d).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'}) : '';
  const FASES = {pronto: 'Pronto', ouvindo: 'Ouvindo…', pensando: 'Pensando…', confirmando: 'Esperando você', respondeu: 'Pronto'};

  let raiz, rolo, antigos, legenda, passos, cartao, erro, campo, estado, encerrar;
  // a sessão do Claude no servidor dura até 6 h sem uso: o que é dela fica aberto no painel
  const CONVERSA_MS = 6 * 3600 * 1000;

  function mensagem(papel, texto, detalhe, quando, onde) {
    const m = el('div', 'msg' + (papel === 'gabriel' ? ' eu' : ''));
    if (quando) m.append(el('span', 'hora', hora(quando)));
    m.append(document.createTextNode(texto));
    if (detalhe) { const d = el('div', 'det'); d.innerHTML = md(detalhe); m.append(d); }
    (onde || rolo).append(m);
    return m;
  }
  const rolar = () => { rolo.scrollTop = rolo.scrollHeight; };

  window.jarvis = {
    mount(caixa, opcoes = {}) {
      if (!document.getElementById('jvcss')) { const s = el('style'); s.id = 'jvcss'; s.textContent = css; document.head.append(s); }
      raiz = el('div', 'jv'); raiz.dataset.fase = 'pronto';
      const topo = el('div', 'topo');
      topo.append(el('span', 'ponto'), el('b', null, 'Jarvis'));
      estado = el('span', 'estado', 'Pronto');
      topo.append(estado);
      encerrar = el('button', null, 'Encerrar'); encerrar.hidden = true;
      encerrar.title = 'Parar de ouvir e encerrar a conversa';
      encerrar.onclick = () => post({do: 'encerrar'});
      topo.append(encerrar);
      if (opcoes.sozinho) {
        const fechar = el('button', null, '✕'); fechar.title = 'Fechar'; fechar.setAttribute('aria-label', 'Fechar');
        fechar.onclick = () => post({do: 'fechar'});
        topo.append(fechar);
      }
      rolo = el('div', 'rolo');
      const hist = el('details'); hist.hidden = true;
      hist.append(el('summary', null, 'Antes'));
      antigos = el('div'); antigos.style.cssText = 'display:flex;flex-direction:column;gap:6px;margin-top:6px';
      hist.append(antigos);
      rolo.append(hist);
      passos = el('div', 'passos');
      legenda = el('div', 'legenda vazia', 'Diga “Hey Jarvis” ou digite abaixo.');
      cartao = el('div', 'cartao'); cartao.hidden = true;
      erro = el('div', 'erro'); erro.hidden = true;
      const form = el('form');
      campo = el('input'); campo.placeholder = 'Peça ao Jarvis…'; campo.maxLength = 2000; campo.autocomplete = 'off';
      campo.setAttribute('aria-label', 'Pedido para o Jarvis');
      const mic = el('button', null, '🎙'); mic.type = 'button'; mic.title = 'Falar'; mic.setAttribute('aria-label', 'Falar');
      mic.onclick = () => post({do: 'ouvir'});
      const enviar = el('button', 'azul', '↑'); enviar.type = 'submit'; enviar.setAttribute('aria-label', 'Enviar');
      form.append(campo, mic, enviar);
      form.onsubmit = e => { e.preventDefault(); const t = campo.value.trim(); if (!t) return; campo.value = ''; post({do: 'pedir', texto: t}); };
      campo.addEventListener('input', () => post({do: 'ativo'}));
      campo.addEventListener('focus', () => post({do: 'foco'}));
      raiz.append(topo, rolo, legenda, passos, cartao, erro, form);
      caixa.append(raiz);
      post({do: 'pronto'});
    },
    fase(f) { if (!raiz) return; raiz.dataset.fase = f; estado.textContent = FASES[f] || f; },
    legenda(t) { legenda.textContent = t || ''; legenda.classList.remove('vazia'); },
    pedido(t) {
      legenda.textContent = ''; passos.textContent = ''; erro.hidden = true; cartao.hidden = true;
      mensagem('gabriel', t); rolar();
    },
    passo(t) { passos.textContent = t + '…'; },
    confirmar({id, resumo}) {
      cartao.replaceChildren();
      cartao.append(el('p', null, resumo));
      const linha = el('div');
      const sim = el('button', 'azul', 'Confirmo'), nao = el('button', null, 'Recuso');
      sim.onclick = () => { cartao.hidden = true; post({do: 'confirmar', id, sim: true}); };
      nao.onclick = () => { cartao.hidden = true; post({do: 'confirmar', id, sim: false}); };
      linha.append(sim, nao); cartao.append(linha); cartao.hidden = false; rolar();
    },
    resposta({fala, detalhe}) {
      passos.textContent = ''; cartao.hidden = true;
      mensagem('jarvis', fala, detalhe); rolar();
    },
    historico(itens) {
      // a conversa corrente (até 6 h) aparece aberta, depois de "Antes"; o resto fica recolhido
      antigos.replaceChildren();
      rolo.querySelectorAll(':scope > .msg.h').forEach(m => m.remove());
      const corte = Date.now() - CONVERSA_MS, depois = antigos.parentElement.nextSibling;
      let velhas = 0;
      for (const m of itens) {
        if (m.quando && m.quando < corte) { mensagem(m.papel, m.texto, m.detalhe, m.quando, antigos); velhas++; continue; }
        const e = mensagem(m.papel, m.texto, m.detalhe, m.quando);
        e.classList.add('h');
        rolo.insertBefore(e, depois);
      }
      antigos.parentElement.hidden = !velhas;
      rolar();
    },
    conversa(on) { if (encerrar) encerrar.hidden = !on; },
    erro(t) { passos.textContent = ''; erro.textContent = t; erro.hidden = !t; },
    focar() { campo?.focus(); },
  };
})();
