import test from 'node:test';
import assert from 'node:assert/strict';
import {validId, normalize, renderHtml} from '../src/index.mjs';

test('post ids reject injections and unsupported numbers',()=>{
  assert.equal(validId('10'),true);
  for(const id of ['0','-1','1 OR 1=1','9007199254740993',undefined])
    assert.equal(validId(id),false);
});
test('HTML escapes text and keeps UTF16 Telegram offsets',()=>{
  assert.equal(renderHtml('<script>'),'<p>&lt;script&gt;</p>');
  assert.equal(renderHtml('😀 سلام',[{offset:3,length:4,type:'bold'}]),'<p>😀 <b>سلام</b></p>');
  assert.equal(renderHtml('click',[{offset:0,length:5,type:'text_link',url:'javascript:alert(1)'}]),'<p>click</p>');
});
test('only configured channel can publish',()=>{
  const update={update_id:5,channel_post:{message_id:12,date:1700000,text:'#مهم خبر',chat:{id:-1002,type:'channel',username:'ahbe1400'}}};
  assert.equal(normalize(update,'@wrong'),null);
  assert.equal(normalize(update,'-1003'),null);
  const result=normalize(update,'@ahbe1400');
  assert.equal(result.id,'12');
  assert.equal(result.important,true);
  assert.equal(result.url,'https://t.me/ahbe1400/12');
});
test('edit and photo are supported',()=>{
  const result=normalize({update_id:8,edited_channel_post:{message_id:3,date:20,caption:'عکس',photo:[{file_id:'a'},{file_id:'b'}],chat:{id:-1002,type:'channel',username:'ahbe1400'}}},'@ahbe1400');
  assert.equal(result.photoId,'b');
});

test('private channel post is accepted only by its numeric chat ID',()=>{
  const message={update_id:22,channel_post:{
    message_id:18,date:1700000,text:'خبر کانال خصوصی',
    chat:{id:-1001234567890,type:'channel',title:'Private channel'}
  }};
  assert.equal(normalize(message,'@ahbe1400'),null);
  assert.equal(normalize(message,'-1001111111111'),null);
  const post=normalize(message,'-1001234567890');
  assert.equal(post.id,'18');
  assert.equal(post.url,'https://t.me/c/1234567890/18');
  assert.equal(post.text,'خبر کانال خصوصی');
});
