/*
 * Free Cloudflare Workers + D1 backend for one public Telegram channel.
 * No bot token is included in the Android app or public repository.
 */
const jsonHeaders = {'content-type':'application/json; charset=utf-8','access-control-allow-origin':'*','cache-control':'public, max-age=10'};
function json(data,status=200){return new Response(JSON.stringify(data),{status,headers:jsonHeaders});}
function textResponse(body,status=200){return new Response(body,{status,headers:{'content-type':'text/plain; charset=utf-8'}});}
function validId(value){return typeof value==='string' && /^[1-9][0-9]{0,14}$/.test(value) && Number.isSafeInteger(Number(value));}
const escapeHtml = value=>String(value).replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
function safeUrl(s){
  try {const u=new URL(s);return ['https:','http:','tg:','mailto:'].includes(u.protocol)?u.href:null;}
  catch {return null;}
}
function renderHtml(body,entities=[]){
  const ranges=entities.filter(e=>Number.isInteger(e.offset)&&Number.isInteger(e.length)&&e.offset>=0&&e.length>0&&e.offset+e.length<=body.length);
  const bounds=[...new Set([0,body.length,...ranges.flatMap(e=>[e.offset,e.offset+e.length])])].sort((a,b)=>a-b);
  let out='';
  for(let i=0;i<bounds.length-1;i++){
    const start=bounds[i],end=bounds[i+1];
    let part=escapeHtml(body.slice(start,end)).replace(/\n/g,'<br>');
    for(const e of ranges.filter(e=>e.offset<=start&&e.offset+e.length>=end).reverse()){
      const tag={bold:'b',italic:'i',underline:'u',strikethrough:'s',code:'code',pre:'code'}[e.type];
      if(tag)part='<'+tag+'>'+part+'</'+tag+'>';
      if(e.type==='url'||e.type==='text_link'){
        const link=safeUrl(e.type==='url'?body.slice(e.offset,e.offset+e.length):e.url);
        if(link)part='<a href="'+escapeHtml(link)+'">'+part+'</a>';
      }
    }
    out+=part;
  }
  return '<p>'+out+'</p>';
}
function normalize(update,channel){
  const m=update.channel_post||update.edited_channel_post;
  if(!m||m.chat?.type!=='channel'||!Number.isSafeInteger(m.message_id)||!Number.isSafeInteger(update.update_id))return null;
  const match=String(channel||'').startsWith('@')
    ? String(m.chat.username||'').toLowerCase()===String(channel).slice(1).toLowerCase()
    : String(m.chat.id)===String(channel);
  if(!match)return null;
  const body=m.text||m.caption||(m.photo?'خبر تصویری':'رسانه جدید؛ برای مشاهده در تلگرام باز کنید');
  const id=String(m.message_id);
  return {id,messageId:m.message_id,updateId:update.update_id,date:m.date,
    editedAt:m.edit_date||m.date,
    title:Array.from(body.split('\n').find(line=>line.trim())||'خبر جدید').slice(0,100).join(''),
    text:body,html:renderHtml(body,m.entities||m.caption_entities||[]),
    url:m.chat.username?'https://t.me/'+m.chat.username+'/'+id:'',
    important:/#(?:مهم|فوری)(?:\s|$|[.,،!])/u.test(body),
    photoId:m.photo?.at(-1)?.file_id||null};
}
async function telegram(env,method,payload){
  const r=await fetch('https://api.telegram.org/bot'+env.TELEGRAM_BOT_TOKEN+'/'+method,
    {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});
  if(!r.ok)throw new Error('Telegram API failed');
  const data=await r.json();
  if(!data.ok)throw new Error('Telegram API rejected operation');
  return data.result;
}
function serial(row,base){
  return {id:String(row.id),title:row.title,text:row.text,html:row.html,url:row.url,
    date:row.date,important:Boolean(row.important),views:null,
    image:row.photo_id?base+'/image/'+row.id+'?v='+row.update_id:null};
}
async function feed(request,env,url,parts){
  if(request.method!=='GET')return textResponse('Method not allowed',405);
  if(parts.length===2&&validId(parts[1])){
    const row=await env.DB.prepare('SELECT * FROM posts WHERE id=?').bind(Number(parts[1])).first();
    return row?json(serial(row,url.origin)):json({error:'not_found'},404);
  }
  if(parts.length!==1)return json({error:'not_found'},404);
  const q=(url.searchParams.get('q')||'').trim().toLocaleLowerCase('fa');
  const cursor=url.searchParams.get('cursor');
  if(q.length>120||(cursor!==null&&!validId(cursor)))return json({error:'invalid_query'},400);
  let sql='SELECT * FROM posts WHERE id < ?';
  const args=[cursor?Number(cursor):Number.MAX_SAFE_INTEGER];
  if(q){sql+=' AND search LIKE ? ESCAPE '+"'\\'";args.push('%'+q.replace(/[\\%_]/g,'\\$&')+'%');}
  sql+=' ORDER BY id DESC LIMIT 21';
  const rows=(await env.DB.prepare(sql).bind(...args).all()).results||[];
  return json({posts:rows.slice(0,20).map(row=>serial(row,url.origin)),
    nextCursor:rows.length>20?String(rows[19].id):null});
}
async function webhook(request,env){
  if(request.method!=='POST')return textResponse('Method not allowed',405);
  if(typeof env.TELEGRAM_WEBHOOK_SECRET!=='string'||env.TELEGRAM_WEBHOOK_SECRET.length<32||
     request.headers.get('X-Telegram-Bot-Api-Secret-Token')!==env.TELEGRAM_WEBHOOK_SECRET)return textResponse('Forbidden',403);
  const ct=request.headers.get('content-type')||'';
  if(!ct.includes('application/json'))return textResponse('Bad request',400);
  const body=await request.text();
  if(body.length>256000)return textResponse('Payload too large',413);
  const post=normalize(JSON.parse(body),env.TELEGRAM_CHANNEL_ID||'@ahbe1400');
  if(!post)return textResponse('ignored');
  const row=await env.DB.prepare('SELECT edited_at,update_id FROM posts WHERE id=?').bind(Number(post.id)).first();
  if(row&&(row.edited_at>post.editedAt||(row.edited_at===post.editedAt&&row.update_id>=post.updateId)))
    return textResponse('duplicate');
  await env.DB.prepare('INSERT INTO posts(id,update_id,edited_at,date,title,text,html,url,search,important,photo_id) VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET update_id=excluded.update_id,edited_at=excluded.edited_at,date=excluded.date,title=excluded.title,text=excluded.text,html=excluded.html,url=excluded.url,search=excluded.search,important=excluded.important,photo_id=excluded.photo_id WHERE excluded.edited_at>posts.edited_at OR (excluded.edited_at=posts.edited_at AND excluded.update_id>posts.update_id)')
    .bind(Number(post.id),post.updateId,post.editedAt,post.date,post.title,post.text,post.html,post.url,post.text.toLocaleLowerCase('fa'),post.important?1:0,post.photoId).run();
  return textResponse('ok');
}
async function image(env,id){
  const row=await env.DB.prepare('SELECT photo_id FROM posts WHERE id=?').bind(Number(id)).first();
  if(!row?.photo_id)return textResponse('Not found',404);
  const info=await telegram(env,'getFile',{file_id:row.photo_id});
  if(!info.file_path||info.file_size>10*1024*1024)return textResponse('Not found',404);
  const img=await fetch('https://api.telegram.org/file/bot'+env.TELEGRAM_BOT_TOKEN+'/'+info.file_path);
  if(!img.ok)return textResponse('Image unavailable',502);
  const bytes=await img.arrayBuffer();
  if(bytes.byteLength>10*1024*1024)return textResponse('Image too large',413);
  return new Response(bytes,{headers:{'content-type':'image/jpeg','cache-control':'public,max-age=300','access-control-allow-origin':'*'}});
}
export default {
 async fetch(request,env){
  try{
   const url=new URL(request.url),parts=url.pathname.split('/').filter(Boolean);
   if(parts.length===1&&parts[0]==='health'&&request.method==='GET')return json({ok:true,backend:'cloudflare-d1'});
   if(parts[0]==='telegram'&&parts[1]==='webhook'&&parts.length===2)return await webhook(request,env);
   if(parts[0]==='posts')return await feed(request,env,url,parts);
   if(parts[0]==='image'&&parts.length===2&&validId(parts[1])&&request.method==='GET')return await image(env,parts[1]);
   return json({error:'not_found'},404);
  }catch(err){
   console.error('News backend request failed:',err instanceof SyntaxError?'bad_json':'server_error');
   return json({error:'unavailable'},500);
  }
 }
};
export {validId,normalize,renderHtml};
