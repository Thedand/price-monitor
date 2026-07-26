(() => {
  const rows = Array.isArray(window.PRICE_DATA) ? window.PRICE_DATA : [];
  const state = { segment: 'economy', color: '', package: '', search: '' };
  const money = new Intl.NumberFormat('ru-RU', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const num = value => Number(String(value ?? '').replace(',', '.')) || 0;
  const groups = buildGroups(rows);

  function buildGroups(data) {
    const map = new Map();
    data.forEach(item => {
      const key = [item.segment, item.color_normalized, item.package_group].join('|');
      if (!map.has(key)) map.set(key, { segment:item.segment, color:item.color_normalized, package:item.package_group, offers:[] });
      map.get(key).offers.push({...item, price:num(item.analysis_price), unit:num(item.unit_price_per_kg)});
    });
    return [...map.values()].map(g => {
      g.offers.sort((a,b) => a.unit-b.unit);
      g.best=g.offers[0]; g.worst=g.offers[g.offers.length-1];
      g.saving=g.offers.length>1 ? g.worst.unit-g.best.unit : 0;
      g.percent=g.offers.length>1 ? g.saving/g.worst.unit*100 : 0;
      return g;
    });
  }

  const els = Object.fromEntries(['updatedAt','metricGroups','metricSaving','metricSavingLabel','metricAverage','metricSources','searchInput','colorFilter','packageFilter','resetFilters','resultCount','priceTable','emptyState','drawer','drawerTitle','drawerMeta','drawerSaving','offerList','overlay','closeDrawer'].map(id=>[id,document.getElementById(id)]));
  document.querySelectorAll('.segment-btn').forEach(btn => btn.addEventListener('click', () => { state.segment=btn.dataset.segment; document.querySelectorAll('.segment-btn').forEach(b=>b.classList.toggle('active',b===btn)); populateColors(); render(); }));
  els.searchInput.addEventListener('input',e=>{state.search=e.target.value.trim().toLowerCase();render()});
  els.colorFilter.addEventListener('change',e=>{state.color=e.target.value;render()});
  els.packageFilter.addEventListener('change',e=>{state.package=e.target.value;render()});
  els.resetFilters.addEventListener('click',()=>{state.color='';state.package='';state.search='';els.searchInput.value='';els.packageFilter.value='';populateColors();render()});
  els.closeDrawer.addEventListener('click',closeDrawer); els.overlay.addEventListener('click',closeDrawer); document.addEventListener('keydown',e=>{if(e.key==='Escape')closeDrawer()});

  function populateColors(){ const colors=[...new Set(groups.filter(g=>g.segment===state.segment).map(g=>g.color))].sort((a,b)=>a.localeCompare(b,'ru')); els.colorFilter.innerHTML='<option value="">Все цвета</option>'+colors.map(c=>`<option ${c===state.color?'selected':''}>${esc(c)}</option>`).join(''); if(!colors.includes(state.color))state.color=''; }
  function filtered(){return groups.filter(g=>g.segment===state.segment&&(!state.color||g.color===state.color)&&(!state.package||g.package===state.package)&&(!state.search||g.color.toLowerCase().includes(state.search)||g.offers.some(o=>(o.brand+' '+o.store).toLowerCase().includes(state.search)))).sort((a,b)=>b.percent-a.percent||a.color.localeCompare(b.color,'ru'));}
  function render(){const list=filtered(); const comparable=list.filter(g=>g.offers.length>1); els.metricGroups.textContent=list.length; const top=[...comparable].sort((a,b)=>b.saving-a.saving)[0]; els.metricSaving.textContent=top?`${money.format(top.saving)} р/кг`:'—'; els.metricSavingLabel.textContent=top?`${top.color} · ${packageName(top.package)}`:'нет сравнения'; const avg=comparable.length?comparable.reduce((s,g)=>s+g.percent,0)/comparable.length:0; els.metricAverage.textContent=`${money.format(avg)}%`; els.metricSources.textContent=new Set(list.flatMap(g=>g.offers.map(o=>o.offer_key))).size; els.resultCount.textContent=`${list.length} групп · ${comparable.length} с прямым сравнением`; els.emptyState.hidden=!!list.length; els.priceTable.innerHTML=list.map(rowHtml).join(''); els.priceTable.querySelectorAll('tr').forEach(tr=>tr.addEventListener('click',()=>openDrawer(list[Number(tr.dataset.index)]))); }
  function rowHtml(g,i){return `<tr data-index="${i}" tabindex="0"><td><div class="color-cell"><i class="swatch" style="--swatch:${swatch(g.color)}"></i>${esc(g.color)}</div></td><td><span class="package-chip">${packageName(g.package)}</span></td><td><div class="source"><strong>${esc(g.best.brand)}</strong><small>${esc(g.best.store)} · ${g.offers.length} предлож.</small></div></td><td><span class="money big">${money.format(g.best.price)} руб.</span><br><small>${money.format(g.best.unit)} р/кг</small></td><td><span class="saving">${g.offers.length>1?money.format(g.saving)+' р/кг':'—'}</span></td><td>${g.offers.length>1?`<span class="percent">${money.format(g.percent)}%</span>`:'—'}</td><td class="go">›</td></tr>`}
  function openDrawer(g){els.drawerTitle.textContent=g.color;els.drawerMeta.textContent=`${state.segment==='economy'?'Эконом':'Стандарт'} · ${packageName(g.package)} · ${g.offers.length} предложений`;els.drawerSaving.innerHTML=g.offers.length>1?`Максимальная экономия на килограмм<strong>${money.format(g.saving)} руб. · ${money.format(g.percent)}%</strong>`:'Для этого варианта пока доступно одно предложение';els.offerList.innerHTML=g.offers.map((o,i)=>`<article class="offer-card ${i===0?'best-offer':''}"><span class="rank">${i+1}</span><div class="offer-info"><strong>${esc(o.brand)}</strong><small>${esc(o.store)} · ${String(o.package_kg).replace('.',',')} кг</small><span class="stock-label ${String(o.in_stock).toLowerCase()==='true'?'':'out'}">${String(o.in_stock).toLowerCase()==='true'?'В наличии':'Нет в наличии'}</span></div><div class="offer-price"><strong>${money.format(o.price)} руб.</strong><small>${money.format(o.unit)} р/кг</small></div><a class="offer-link" href="${esc(o.url)}" target="_blank" rel="noopener">Открыть товар ↗</a></article>`).join('');els.overlay.hidden=false;els.drawer.classList.add('open');els.drawer.setAttribute('aria-hidden','false');document.body.style.overflow='hidden'}
  function closeDrawer(){els.overlay.hidden=true;els.drawer.classList.remove('open');els.drawer.setAttribute('aria-hidden','true');document.body.style.overflow=''}
  function packageName(p){return p==='small'?'Малая фасовка':'Большая фасовка'} function esc(v){return String(v??'').replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]))}
  function swatch(c){const s=c.toLowerCase();const map=[['бел','#f5f4ea'],['черн','#242722'],['красн','#a82b2b'],['вишн','#712a3b'],['голуб','#79b7d1'],['син','#285a9c'],['зел','#4f813c'],['салат','#8fcf58'],['желт','#e7c42e'],['оранж','#de7a2f'],['беж','#cbb693'],['корич','#775036'],['сереб','#bfc4c4'],['сер','#888f8b'],['бирюз','#39a7a3'],['фиолет','#7c5b9d'],['сирен','#a989bc'],['изумруд','#19835e'],['шоколад','#573b2e']];return (map.find(([k])=>s.includes(k))||[])[1]||'#d9ddd4'}
  const newest=rows.map(r=>new Date(r.collected_at)).sort((a,b)=>b-a)[0];els.updatedAt.textContent=newest?`Данные: ${newest.toLocaleString('ru-RU',{dateStyle:'medium',timeStyle:'short'})}`:'Нет данных';populateColors();render();
})();
