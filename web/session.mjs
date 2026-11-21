export function category(text) {
  const key=text.trim().toLowerCase();
  return ['phone','mobile','mobile phone'].includes(key) ? 'cell phone' : key;
}
export function counts(items) {
  const result=new Map();
  for(const item of items) result.set(item.class,(result.get(item.class)||0)+1);
  return result;
}
export function changes(before,after) {
  return [...new Set([...before.keys(),...after.keys()])].sort().map(name =>
    [name,before.get(name)||0,after.get(name)||0]);
}
export class Session {
  checklist=new Map([['cell phone',false],['mouse',false],['book',false]]);
  history=new Map(); visible=new Set(); previous=new Set(); previousAt=0;
  end(){ this.visible.clear(); this.previous.clear(); this.previousAt=0; }
  observe(scan,live){
    const names=new Set(scan.items.map(x=>x.class));
    this.visible=new Set([...names].filter(n=>!live || (this.previous.has(n) && scan.time-this.previousAt<=3000)));
    for(const n of this.visible) this.history.set(n,scan);
    this.previous=live?names:new Set(); this.previousAt=scan.time;
  }
  current(name,now){const s=this.history.get(name);return this.visible.has(name)&&s&&(!s.live||now-s.time<3000);}
}
