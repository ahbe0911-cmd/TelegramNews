const test = require('node:test');
const assert = require('node:assert/strict');
const {authorized, renderHtml, normalize, validCursor, isNewer} = require('../domain');
test('webhook authentication fails closed', () => {
  assert.equal(authorized(undefined, undefined), false);
  assert.equal(authorized('short', 'short'), false);
  assert.equal(authorized('a'.repeat(32), 'a'.repeat(32)), true);
  assert.equal(authorized('b'.repeat(32), 'a'.repeat(32)), false);
  assert.equal(authorized('a'.repeat(33), 'a'.repeat(32)), false);
});
test('HTML escapes user input and rejects unsafe URLs', () => {
  assert.equal(renderHtml('<script>'), '<p>&lt;script&gt;</p>');
  assert.equal(renderHtml('click',[{type:'text_link',offset:0,length:5,url:'javascript:alert(1)'}]), '<p>click</p>');
});
test('entity offsets preserve emoji and Persian bold text', () => {
  assert.equal(renderHtml('😀 سلام',[{type:'bold',offset:3,length:4}]), '<p>😀 <b>سلام</b></p>');
});
test('overlapping styles produce balanced tags', () => {
  assert.equal(renderHtml('abc',[{type:'bold',offset:0,length:2},{type:'italic',offset:1,length:2}]), '<p><b>a</b><b><i>b</i></b><i>c</i></p>');
});
const update = {update_id:10, channel_post:{message_id:2,date:10,text:'#فوری\nسلام', chat:{id:-100123,type:'channel',username:'news'}}};
test('only the configured channel can publish', () => {
  assert.equal(normalize(update, '-100999'), null);
  const post = normalize(update, '-100123');
  assert.equal(post.url, 'https://t.me/news/2');
  assert.equal(post.important, true);
  assert.equal(post.views, null);
  assert.equal(post.edited, false);
});
test('edits and photos are normalized', () => {
  const post = normalize({update_id:11,edited_channel_post:{...update.channel_post,text:undefined,caption:'عکس',photo:[{file_id:'small'},{file_id:'large'}]}},'-100123');
  assert.equal(post.photoId,'large'); assert.equal(post.edited,true);
});
test('cursor rejects unbounded values and injection', () => {
  for (const value of ['0','-1','1e6','1/2','9007199254740993',undefined]) assert.equal(validCursor(value),false);
  assert.equal(validCursor('123'),true);
});

test('new edits survive Telegram update-id resets, old delivery cannot overwrite them', () => {
  assert.equal(isNewer({editedAt:20,updateId:1},{editedAt:10,updateId:999}),true);
  assert.equal(isNewer({editedAt:10,updateId:1000},{editedAt:20,updateId:1}),false);
  assert.equal(isNewer({editedAt:20,updateId:1},{editedAt:20,updateId:1}),false);
});
