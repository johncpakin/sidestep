#!/usr/bin/env node
// Assembles parts/_head.html + parts/s01..sNN.html + parts/_foot.html → index.html
// Section order is this list. One letter per section in the recipe, top to bottom.
const fs = require('fs'), path = require('path');
const ORDER = ['s01','s02','s03','s04','s05','s07','s08'];
const P = f => path.join(__dirname, 'parts', f);
const read = f => fs.existsSync(P(f)) ? fs.readFileSync(P(f), 'utf8') : `<section class="sblk" id="${f.replace('.html','')}"><div class="vars"><div class="var on" data-label="Pending"><div class="w" style="padding:64px 32px;text-align:center;font:500 12px var(--mono);letter-spacing:.14em;color:var(--ink4)">${f} · PENDING</div></div></div></section>\n`;
let out = read('_head.html');
for (const s of ORDER) out += `\n<!-- ═══ ${s} ═══ -->\n` + read(s + '.html');
out += read('_foot.html');
fs.writeFileSync(path.join(__dirname, 'index.html'), out);
console.log('index.html', (out.length/1024).toFixed(0) + 'k', ORDER.map(s => fs.existsSync(P(s+'.html')) ? s : s+'(pending)').join(' '));
