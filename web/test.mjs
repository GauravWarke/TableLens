import assert from 'node:assert/strict';
import {Session,category,counts,changes} from './session.mjs';
const s=new Session(),frame=(time,names,live=true)=>({time,live,items:names.map(n=>({class:n}))});
s.observe(frame(1000,['mouse']),true);assert.equal(s.history.size,0);
s.observe(frame(1500,['mouse']),true);assert.ok(s.current('mouse',1600));assert.equal(s.current('mouse',5000),false);
s.observe(frame(2200,[]),true);assert.equal(s.history.get('mouse').time,1500);assert.equal(s.checklist.get('mouse'),false);
s.observe(frame(6000,['cup','cup'],false),false);
assert.deepEqual(changes(counts(s.history.get('cup').items),counts([{class:'cup'}])),[['cup',2,1]]);
s.end();assert.equal(s.visible.size,0);assert.equal(category('Phone'),'cell phone');console.log('Session checks passed');
