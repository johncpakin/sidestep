#!/usr/bin/env node
// Builds index.html (shuffler) then flattens it into final.html: recipe locked, dev chrome gone.
// Non-chosen variants stay in the DOM (hidden) because section scripts wire up all three; only the chosen one is shown.
const fs=require('fs'),path=require('path'),{execSync}=require('child_process');
const RECIPE=process.argv[2]||'CBCAACA';
execSync('node build.cjs',{cwd:__dirname,stdio:'inherit'});
let h=fs.readFileSync(path.join(__dirname,'index.html'),'utf8');
const cut=(re)=>{ const before=h.length; h=h.replace(re,''); if(h.length===before) console.warn('nothing cut for',re); };
cut(/<!-- Mockup-only:[\s\S]*?<button class="devtog"[^>]*>[^<]*<\/button>\n/);
cut(/<div class="dochead">[\s\S]*?<\/div><\/div>\n\n/);
cut(/<div class="topbar">[\s\S]*?<\/div><\/div>\n\n/);
cut(/<div class="toc">[\s\S]*?<\/div><\/div>\n\n/);
h=h.replace(/<header class="sbar">[\s\S]*?<\/header>\n/g,'');
// lock the recipe: mark chosen variants .on in the markup
const secs=[...h.matchAll(/<section class="sblk" id="(s\d\d)"/g)].map(m=>m[1]);
secs.forEach((id,k)=>{ const want='ABCD'.indexOf(RECIPE[k]||'A');
  const start=h.indexOf(`<section class="sblk" id="${id}"`), end=h.indexOf('</section>',start);
  let sec=h.slice(start,end).replace(/<div class="var( on)?" data-var="(\d)"/g,(m,on,i)=>`<div class="var${+i===want?' on':''}" data-var="${i}"`);
  h=h.slice(0,start)+sec+h.slice(end); });
// swap the shuffler for a minimal runtime: reveal, nav-current, and each chosen variant's _onShow
const s=h.indexOf('<script>\n/* ═══════════ SHUFFLER'), e=h.indexOf('</script>',s)+9;
const runtime=`<script>
(function(){
  const io=new IntersectionObserver(es=>es.forEach(e=>{ if(e.isIntersecting){ e.target.classList.add('in'); io.unobserve(e.target);} }),{threshold:.1});
  document.querySelectorAll('.rv').forEach(r=>io.observe(r));
  const links=[...document.querySelectorAll('.snav ul a')];
  const nio=new IntersectionObserver(es=>es.forEach(e=>{ if(e.isIntersecting) links.forEach(a=>a.classList.toggle('cur',a.getAttribute('href')==='#'+e.target.id)); }),{rootMargin:'-40% 0px -55% 0px'});
  const secs=[...document.querySelectorAll('.sblk')]; secs.forEach(s=>nio.observe(s));
  const pio=new IntersectionObserver(es=>es.forEach(e=>{ if(e.isIntersecting){ const v=e.target; v.querySelectorAll('.app').forEach(a=>a._layout&&a._layout()); if(v._onShow&&!v._played){ v._played=true; v._onShow(); } } }),{threshold:.25});
  document.querySelectorAll('.var.on').forEach(v=>pio.observe(v));
})();
</script>`;
h=h.slice(0,s)+runtime+h.slice(e);
h=h.replace('<title>Sidestep</title>','<title>Sidestep · every Claude account, one menu bar</title>');
fs.writeFileSync(path.join(__dirname,'final.html'),h);
console.log('final.html',(h.length/1024).toFixed(0)+'k · recipe',RECIPE,'·',secs.join(' '));
