'use strict';
const {timingSafeEqual} = require('node:crypto');
function authorized(actual, expected) {
  if (typeof actual !== 'string' || typeof expected !== 'string' || expected.length < 32) return false;
  const a = Buffer.from(actual), b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}
const escape = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[c]));
function safeUrl(value) {
  try { const u = new URL(value); return ['https:', 'http:', 'tg:', 'mailto:'].includes(u.protocol) ? u.href : null; } catch { return null; }
}
// Telegram entity offsets are UTF-16 code units, matching JavaScript string offsets.
// Splitting at every boundary also handles nested/overlapping entities correctly.
function renderHtml(text, entities = []) {
  const ranges = entities.filter(e => Number.isInteger(e.offset) && Number.isInteger(e.length) && e.offset >= 0 && e.length > 0 && e.offset + e.length <= text.length);
  const boundaries = [...new Set([0, text.length, ...ranges.flatMap(e => [e.offset, e.offset + e.length])])].sort((a,b) => a-b);
  let result = '';
  for (let i = 0; i < boundaries.length - 1; i++) {
    const from = boundaries[i], to = boundaries[i+1];
    let part = escape(text.slice(from,to)).replace(/\n/g, '<br>');
    for (const e of ranges.filter(e => e.offset <= from && e.offset + e.length >= to).reverse()) {
      const tag = {bold:'b', italic:'i', underline:'u', strikethrough:'s', code:'code', pre:'code', blockquote:'blockquote'}[e.type];
      if (tag) part = `<${tag}>${part}</${tag}>`;
      if (e.type === 'url' || e.type === 'text_link') {
        const url = safeUrl(e.type === 'url' ? text.slice(e.offset, e.offset+e.length) : e.url);
        if (url) part = `<a href="${escape(url)}">${part}</a>`;
      }
    }
    result += part;
  }
  return `<p>${result}</p>`;
}
function normalize(update, channelId) {
  const message = update.channel_post || update.edited_channel_post;
  if (!message || String(message.chat?.id) !== String(channelId) || message.chat?.type !== 'channel') return null;
  if (!Number.isSafeInteger(message.message_id) || !Number.isSafeInteger(update.update_id)) return null;
  const text = message.text || message.caption || (message.photo ? 'خبر تصویری' : 'رسانه جدید؛ برای مشاهده در تلگرام باز کنید');
  return {
    id: String(message.message_id), messageId: message.message_id,
    updateId: update.update_id, date: message.date, editedAt: message.edit_date || message.date,
    title: Array.from(text.split('\n').find(line => line.trim()) || 'خبر جدید').slice(0,100).join(''),
    text, search: text.toLocaleLowerCase('fa'), html: renderHtml(text, message.entities || message.caption_entities || []),
    url: message.chat.username ? `https://t.me/${message.chat.username}/${message.message_id}` : '',
    important: /#(?:مهم|فوری)(?:\s|$|[.,،!])/u.test(text), views: null,
    photoId: message.photo?.at(-1)?.file_id || null,
    edited: Boolean(update.edited_channel_post),
  };
}
function validCursor(value) { return typeof value === 'string' && /^[1-9]\d{0,14}$/.test(value) && Number.isSafeInteger(Number(value)); }
function isNewer(post, current) {
  return !current || post.editedAt > current.editedAt ||
    (post.editedAt === current.editedAt && post.updateId > current.updateId);
}
module.exports = {authorized, escape, renderHtml, normalize, validCursor, isNewer};
