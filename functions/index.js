'use strict';
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {getMessaging} = require('firebase-admin/messaging');
const {onRequest} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {defineSecret, defineString} = require('firebase-functions/params');
const {authorized, normalize, validCursor, isNewer} = require('./domain');
initializeApp();
const db = getFirestore();
const BOT_TOKEN = defineSecret('TELEGRAM_BOT_TOKEN');
const WEBHOOK_SECRET = defineSecret('TELEGRAM_WEBHOOK_SECRET');
const CHANNEL_ID = defineString('TELEGRAM_CHANNEL_ID', {default:'@ahbe1400'});
const API_BASE = defineString('PUBLIC_API_BASE_URL');
const region = 'europe-west1';
const posts = () => db.collection('posts');
const timeout = () => AbortSignal.timeout(15000);
async function telegram(method, data) {
  const response = await fetch(`https://api.telegram.org/bot${BOT_TOKEN.value()}/${method}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data), signal:timeout()});
  const body = await response.json();
  if (!response.ok || !body.ok) throw new Error('Telegram request failed');
  return body.result;
}
async function storePhoto(id, photoId, updateId) {
  const info = await telegram('getFile', {file_id:photoId});
  if (info.file_size > 10 * 1024 * 1024) return null;
  const response = await fetch(`https://api.telegram.org/file/bot${BOT_TOKEN.value()}/${info.file_path}`, {signal:timeout()});
  if (!response.ok) throw new Error('Image request failed');
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length > 10 * 1024 * 1024) return null;
  const path = `news/${id}-${updateId}.jpg`;
  await getStorage().bucket().file(path).save(bytes, {metadata:{contentType:'image/jpeg', cacheControl:'public,max-age=3600'}});
  return path;
}
function serialize(doc) {
  const data = doc.data();
  return {id:doc.id, title:data.title, text:data.text, html:data.html, url:data.url, date:data.date, important:data.important, views:null,
    image:data.imagePath ? `${API_BASE.value().replace(/\/$/, '')}/image/${doc.id}?v=${data.updateId}` : null};
}
exports.telegramWebhook = onRequest({region, secrets:[BOT_TOKEN, WEBHOOK_SECRET], maxInstances:3, timeoutSeconds:60}, async (req,res) => {
  if (req.method !== 'POST') return res.status(405).end();
  if (!authorized(req.get('X-Telegram-Bot-Api-Secret-Token'), WEBHOOK_SECRET.value())) return res.status(403).end();
  try {
    if (!req.body?.channel_post && !req.body?.edited_channel_post) return res.status(200).send('ignored');
    // Resolve a public username through Telegram; authorization still compares numeric IDs.
    const configured = CHANNEL_ID.value();
    let channelId = configured;
    if (configured.startsWith('@')) {
      const channel = await telegram('getChat', {chat_id:configured});
      if (channel.type !== 'channel') throw new Error('Configured source is not a channel');
      channelId = channel.id;
    }
    const post = normalize(req.body, channelId);
    if (!post) return res.status(200).send('ignored');
    const ref = posts().doc(post.id);
    const existing = await ref.get();
    if (existing.exists && !isNewer(post, existing.data())) return res.status(200).send('duplicate');
    const imagePath = post.photoId ? await storePhoto(post.id, post.photoId, post.updateId) : null;
    delete post.photoId;
    await db.runTransaction(async tx => {
      const current = await tx.get(ref);
      if (current.exists && !isNewer(post, current.data())) return;
      tx.set(ref, {...post, imagePath});
    });
    return res.status(200).send('ok');
  } catch {
    // Never log the Telegram fetch URL: it contains the bot credential.
    console.error('Webhook ingestion failed; Telegram may retry.');
    return res.status(500).send('retry');
  }
});
exports.api = onRequest({region, cors:true, maxInstances:5, timeoutSeconds:30}, async (req,res) => {
  if (req.method !== 'GET') return res.status(405).end();
  try {
    const parts = req.path.split('/').filter(Boolean);
    if (parts[0] === 'image' && parts.length === 2 && validCursor(parts[1])) {
      const doc = await posts().doc(parts[1]).get();
      const path = doc.data()?.imagePath;
      if (!path) return res.status(404).end();
      const [bytes] = await getStorage().bucket().file(path).download();
      res.set('Cache-Control','public,max-age=300');
      return res.type('image/jpeg').send(bytes);
    }
    if (parts[0] !== 'posts') return res.status(404).end();
    if (parts.length === 2 && validCursor(parts[1])) {
      const doc = await posts().doc(parts[1]).get();
      return doc.exists ? res.json(serialize(doc)) : res.status(404).json({error:'not_found'});
    }
    if (parts.length !== 1) return res.status(404).end();
    const q = typeof req.query.q === 'string' ? req.query.q.trim().toLocaleLowerCase('fa') : '';
    if (q.length > 120 || (req.query.cursor !== undefined && !validCursor(req.query.cursor))) return res.status(400).json({error:'invalid_query'});
    let query = posts().orderBy('messageId','desc');
    if (req.query.cursor) query = query.startAfter(Number(req.query.cursor));
    // Search scans at most 100 records per page. The cursor advances even on zero matches.
    const scan = await query.limit(q ? 100 : 21).get();
    const found = [];
    let examined = 0, cursor = null;
    for (const doc of scan.docs) {
      examined++;
      cursor = doc.id;
      if (!q || doc.data().search.includes(q)) found.push(serialize(doc));
      if (found.length === 20) break;
    }
    const more = examined < scan.size || scan.size === (q ? 100 : 21);
    res.set('Cache-Control', 'public,max-age=10');
    return res.json({posts:found, nextCursor:more ? cursor : null});
  } catch {
    console.error('Public news read failed.');
    return res.status(500).json({error:'unavailable'});
  }
});
exports.notifyPost = onDocumentCreated({document:'posts/{postId}', region, retry:true, maxInstances:3}, async event => {
  const post = event.data?.data();
  if (!post || post.edited) return;
  await getMessaging().send({topic:'channel_news', android:{priority:'high', ttl:3600*1000}, data:{
    postId:event.params.postId, title:post.title,
    body:Array.from(post.text).slice(0,160).join(''), important:String(post.important),
    image:post.imagePath ? `${API_BASE.value().replace(/\/$/, '')}/image/${event.params.postId}?v=${post.updateId}` : '',
  }});
});
