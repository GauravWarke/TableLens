import {category,counts,changes,Session} from './session.mjs';
const el=id=>document.getElementById(id), video=document.querySelector('video'), session=new Session();
let epoch=0, url, stream, modelPromise, latest, target='',before,after;
function script(src){return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=src;s.onload=resolve;s.onerror=()=>reject(Error('Could not download detector scripts. Check network access.'));document.head.append(s);});}
function model(){
  if(!modelPromise) modelPromise=(async()=>{
    if(!globalThis.tf) await script('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.22.0/dist/tf.min.js');
    if(!globalThis.cocoSsd) await script('https://cdn.jsdelivr.net/npm/@tensorflow-models/coco-ssd@2.2.3/dist/coco-ssd.min.js');
    await globalThis.tf.ready(); return globalThis.cocoSsd.load({base:'lite_mobilenet_v2'});
  })().catch(e=>{modelPromise=null;throw e;});
  return modelPromise;
}
function paint(canvas,scan,items){
  canvas.hidden=false;canvas.width=scan.image.width;canvas.height=scan.image.height;
  const ctx=canvas.getContext('2d');ctx.drawImage(scan.image,0,0);ctx.font='bold 15px sans-serif';
  for(const item of items){const [x,y,w,h]=item.bbox;ctx.strokeStyle='#ffd966';ctx.lineWidth=3;ctx.strokeRect(x,y,w,h);const top=Math.max(0,y-18);ctx.fillStyle='#152f32';ctx.fillRect(x,top,ctx.measureText(item.class).width+8,19);ctx.fillStyle='white';ctx.fillText(item.class,x+4,top+15);}
}
function render(){
  el('list').replaceChildren();
  for(const [name,packed] of session.checklist){
    const li=document.createElement('li'),b=document.createElement('button');
    li.append(name+' · '+(packed?'Packed by you':session.current(name,Date.now())?'Seen in latest scan':'Unconfirmed')+' ');
    b.textContent=packed?'Undo packed':'Mark packed';b.onclick=()=>{session.checklist.set(name,!packed);render();};li.append(b);el('list').append(li);
  }
  if(!target){el('last').hidden=true;el('found').textContent='';}
  if(target){const s=session.history.get(target);el('last').hidden=!s;
    if(s){const matches=s.items.filter(i=>i.class===target);el('found').textContent=target+' · '+matches.length+' candidate(s) · scanned '+new Date(s.time).toLocaleTimeString();paint(el('last'),s,matches);}
    else el('found').textContent='No reliable sighting of '+target+' this session.';
  }
}
function stop(){
  epoch++;stream?.getTracks().forEach(t=>t.stop());stream=null;video.pause();video.srcObject=null;video.removeAttribute('src');video.load();
  if(url)URL.revokeObjectURL(url);url=null;session.end();render();
}
async function run(file, camera=false){
  stop();const id=epoch;latest=null;el('before').disabled=el('after').disabled=true;el('view').hidden=true;el('counts').textContent='';
  try{
    el('status').textContent='Loading detector…';const detector=await model();if(id!==epoch)return;
    let src=video, continuous=true;
    if(camera){
      if(!navigator.mediaDevices?.getUserMedia)throw Error('Camera unavailable. Open over HTTPS or choose a file.');
      const acquired=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});
      if(id!==epoch){acquired.getTracks().forEach(t=>t.stop());return;}stream=acquired;video.srcObject=stream;await video.play();
    }else{
      url=URL.createObjectURL(file);
      if(file.type.startsWith('image/')){src=new Image();src.src=url;await src.decode();continuous=false;}
      else{video.src=url;await video.play();}
    }
    while(id===epoch){
      const w=src.videoWidth||src.naturalWidth,h=src.videoHeight||src.naturalHeight;
      if(!w||!h)throw Error('No readable image frame.');
      const f=document.createElement('canvas'),scale=Math.min(1,800/w);f.width=Math.round(w*scale);f.height=Math.round(h*scale);
      f.getContext('2d').drawImage(src,0,0,f.width,f.height);
      const items=(await detector.detect(f,40,0.5)).filter(x=>x.class!=='dining table');
      if(id!==epoch)return;
      latest={image:f,items,time:Date.now(),live:continuous};session.observe(latest,continuous);paint(el('view'),latest,items);
      el('counts').textContent=[...counts(items)].map(([n,k])=>n+' × '+k).join(' · ')||'No supported items detected.';
      el('status').textContent=continuous?'Scanning · '+new Date().toLocaleTimeString():'Photo analysed.';
      el('before').disabled=el('after').disabled=false;render();
      if(!continuous)return;
      if(video.ended){stop();el('status').textContent='Video ended.';return;}
      await new Promise(r=>setTimeout(r,400));
    }
  }catch(e){if(id===epoch){stop();el('status').textContent=e.message+' You can choose another input.';}}
}
el('file').onchange=e=>{const f=e.target.files[0];e.target.value='';if(f)run(f);};
el('camera').onclick=()=>run(null,true);el('stop').onclick=()=>{stop();el('status').textContent='Stopped.';};
el('find').onclick=()=>{target=category(el('query').value);render();};
el('add').onclick=()=>{const n=category(el('query').value);if(n&&!session.checklist.has(n))session.checklist.set(n,false);render();};
for(const side of ['before','after'])el(side).onclick=()=>{
  if(!latest)return;if(side==='before')before=counts(latest.items);else after=counts(latest.items);
  el('diff').textContent=before&&after?(changes(before,after).map(([n,a,b])=>n+' '+a+' → '+b).join(' · ')||'No detections in either scan.') :side+' saved. Choose the other scan.';
};
window.addEventListener('pagehide',stop);render();
