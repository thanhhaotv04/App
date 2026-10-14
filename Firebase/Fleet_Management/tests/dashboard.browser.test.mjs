// Dữ liệu giả chỉ dùng trong Chromium; không đăng nhập/ghi Firebase thật.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import axe from 'axe-core';

let browser, server, baseURL;
const root = new URL('../dashboard/', import.meta.url);
const authMock = `
export const browserSessionPersistence={}, inMemoryPersistence={};
const admin=['admin','admin-short','unverified'].includes(window.scenario);
const user={uid:admin?'admin':'driver-a',email:admin?'thanhhao.admin@gmail.com':'driver@example.test',
 emailVerified:window.scenario!=='unverified',getIdToken:async()=>{}};
const auth={currentUser:window.scenario==='login'?null:user}; let callback;
window.auth=auth;
export const getAuth=()=>auth, setPersistence=async()=>{}, reload=async()=>{};
export const sendPasswordResetEmail=async()=>{window.resetEmail=true;};
export const sendEmailVerification=async()=>{window.verifyEmail=true;};
export const onAuthStateChanged=(a,cb)=>{callback=cb;queueMicrotask(()=>cb(auth.currentUser));};
export const signOut=async()=>{auth.currentUser=null;callback(null);};
export const signInWithEmailAndPassword=async()=>{auth.currentUser=user;callback(user);};
`;
const dbMock = `
export const getFirestore=()=>({});
export const doc=(db,...p)=>({path:p.join('/'),id:p.at(-1)}),collection=doc;
export const collectionGroup=(db,id)=>({path:'GROUP/'+id});
export const query=(ref,...constraints)=>({...ref,constraints});
export const where=(...args)=>({where:args}),orderBy=(...args)=>({order:args}),limit=n=>({limit:n});
export const startAfter=()=>({}),documentId=()=> '__name__';
export const Timestamp={fromDate:date=>({toDate:()=>date})};
export const serverTimestamp=()=>({server:true});
const ts=(mins=0)=>({toDate:()=>new Date(Date.now()-mins*60000)});
const tripId='550e8400-e29b-41d4-a716-446655440001';
window.callbacks={};window.writes=[];window.deferred=[];
const row=(id,data,path)=>({id,ref:{path:path||'fleets/demo/vehicles/'+id},exists:()=>true,data:()=>data});
const vehicle=()=>({label:'Bike 01',driverUid:'driver-a',archived:!!window.archived});
const listing=docs=>({docs,size:docs.length,metadata:{fromCache:false}});
export const getDocFromServer=async ref=>{
 if(ref.path.endsWith('/photos/image')) {
   if(window.deferPhoto) await new Promise(resolve=>window.deferred.push(resolve));
   return row('image',{contentType:'image/jpeg',data:window.photoData||''});
 }
 if(window.scenario==='admin-short' && ref.path.includes('/trips/'))
   return row(ref.id,{startedAt:ts(60),endedAt:ts(30)},ref.path);
 if(window.deferVehicle && ref.path.endsWith('/bike-01')) await new Promise(resolve=>window.deferred.push(resolve));
 if(window.offlineVehicle) throw {code:'unavailable'};
 if(ref.path.endsWith('/members/driver-a')) return row('driver-a',{role:'driver'});
 if(ref.path==='fleets/new-fleet') return {exists:()=>false,data:()=>undefined};
 if(ref.path.endsWith('/new-bike')) return {exists:()=>false,data:()=>undefined};
 return row(ref.id,ref.path.endsWith('/bike-01')?vehicle():{name:'Demo'});
};
export const getDocsFromServer=async ref=>{
 if(ref.path==='GROUP/vehicles') return listing([row('bike-01',vehicle(),'fleets/demo/vehicles/bike-01')]);
 if(ref.path.endsWith('/trips')) return listing(window.scenario==='admin-short' ?
   [row(tripId,{startedAt:ts(60),endedAt:ts(30)},ref.path+'/'+tripId)] : []);
 if(ref.path.endsWith('/track_points')) return listing([row('p1',{},ref.path+'/p1')]);
 if(ref.path.endsWith('/members')) return listing([row('driver-a',{role:'driver',displayName:'Driver A'})]);
 return listing([row('bike-01',vehicle())]);
};
export const deleteDoc=async ref=>{window.writes.push({delete:ref.path});};
export const writeBatch=()=>{const writes=[];return {
 set:(ref,data)=>writes.push({path:ref.path,data}),update:(ref,data)=>writes.push({path:ref.path,data}),
 delete:(ref)=>writes.push({delete:ref.path}),
 commit:async()=>{window.writes.push(...writes);for(const w of writes) if(w.path?.endsWith('/bike-01')&&'archived' in w.data) window.archived=w.data.archived;}
};};
export function onSnapshot(ref,options,cb,error){
 if(typeof options==='function'){error=cb;cb=options;}
 let result;
 if(ref.path==='system/access') result=row('access',{adminUid:'admin'});
 else if(ref.path.endsWith('/members/driver-a')) result=row('driver-a',{role:'driver'});
 else if(ref.path.includes('/members/')) result={exists:()=>false,data:()=>undefined};
 else if(ref.path.endsWith('/vehicles')) result=listing([row('bike-01',vehicle())]);
 else if(ref.path.endsWith('/bike-01')) result=row('bike-01',vehicle());
 else if(ref.path.endsWith('/status/current')) result={metadata:{fromCache:false},exists:()=>true,data:()=>({tripActive:true,capturedAt:ts(),updatedAt:ts()})};
 else if(ref.path.endsWith('/trips')) result=listing(window.scenario==='midnight'?[]:[row(tripId,{startedAt:ts(60),endedAt:window.scenario==='admin-short'?ts(30):null})]);
 else if(ref.path.includes('/trips/')) result=row(ref.id,{startedAt:ts(24*60),endedAt:null});
 else if(ref.path.endsWith('/markers')) result=listing(['markers','admin-short'].includes(window.scenario) ?
   ['save_point','food','danger'].map((kind,index)=>row('550e8400-e29b-41d4-a716-44665544000'+(index+2),
     {kind,tripId,latitude:10.776+index/100,longitude:106.701+index/100,accuracyMeters:8,
      capturedAt:ts(30-index),hasPhoto:index===0})) : []);
 else result=listing([row('p1',{tripId,latitude:10.776,longitude:106.701,accuracyMeters:8,speedKmh:15,capturedAt:ts(30)}),
   ...(window.scenario==='admin-short'?[]:[row('p2',{tripId,latitude:10.779,longitude:106.705,accuracyMeters:9,speedKmh:20,capturedAt:ts(10)})])]);
 let active=true;const entry={cb,error,result,ref};window.callbacks[ref.path]=entry;
 queueMicrotask(()=>{if(active)cb(result);});return ()=>{active=false;};
}
`;

before(async () => {
  server = createServer(async (req, res) => {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    if (pathname.includes('..')) { res.writeHead(400).end(); return; }
    try {
      const file = new URL(`.${pathname === '/' ? '/index.html' : pathname}`, root);
      const type = pathname.endsWith('.css') ? 'text/css' : /\.(js|mjs)$/.test(pathname) ? 'text/javascript'
        : pathname.endsWith('.png') ? 'image/png' : 'text/html';
      res.writeHead(200, { 'Content-Type': type }); res.end(await readFile(file));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseURL = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch();
});
after(async () => { await browser?.close(); await new Promise((resolve) => server?.close(resolve)); });

async function pageFor(scenario = 'driver', blocked = false) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.errors = [];
  page.on('pageerror', (error) => page.errors.push(error.message));
  await page.addInitScript((value) => { window.scenario = value; }, scenario);
  await page.route('https://www.gstatic.com/firebasejs/**', (route) => blocked ? route.abort() : route.fulfill({
    contentType: 'text/javascript', body: route.request().url().endsWith('firebase-app.js')
      ? 'export const initializeApp=()=>({});' : route.request().url().endsWith('firebase-app-check.js')
        ? 'export class ReCaptchaEnterpriseProvider { constructor() {} } export const initializeAppCheck=()=>({});'
        : route.request().url().endsWith('firebase-auth.js') ? authMock : dbMock,
  }));
  await page.goto(baseURL);
  if (!blocked) await page.waitForFunction(() => window.navrideAuthReady &&
    (window.scenario === 'login' || window.scenario === 'unverified' ||
      document.querySelector('#point-count').textContent === (window.scenario === 'admin-short' ? '0' : '2')));
  return page;
}

test('blocked SDK gives a useful error and never submits credentials in the URL', async () => {
  const page = await pageFor('login', true);
  await page.locator('#email').fill('driver@example.test'); await page.locator('#password').fill('synthetic-value');
  await page.locator('#login-button').click();
  assert.equal(await page.locator('#retry-auth').isVisible(), true);
  assert.match(await page.locator('#auth-startup').textContent(), /unavailable/);
  assert.equal(page.url(), `${baseURL}/`); await page.close();
});

test('login/logout focus, password reset and role isolation', async () => {
  const page = await pageFor('login');
  await page.locator('#email').fill('driver@example.test'); await page.locator('#reset-password').click();
  assert.match(await page.locator('#login-error').textContent(), /If this account exists/);
  await page.locator('#password').fill('synthetic-value'); await page.locator('#login-button').click();
  await page.waitForFunction(() => document.querySelector('#point-count').textContent === '2');
  assert.equal(await page.evaluate(() => document.activeElement.id), 'dashboard-title');
  assert.equal(await page.locator('#admin-panel').isVisible(), false);
  assert.equal(await page.locator('#vehicle-id option').count(), 1);
  assert.equal(await page.locator('#password').inputValue(), '');
  await page.locator('#sign-out').click();
  assert.equal(await page.evaluate(() => document.activeElement.id), 'login-title');
  assert.equal(await page.locator('#points-list li').count(), 0); assert.deepEqual(page.errors, []); await page.close();
});

test('live rerenders retain keyboard focus, and revocation clears private route data', async () => {
  const page = await pageFor(); const button = page.locator('.trip-button').last();
  await button.focus(); await page.keyboard.press('Enter');
  assert.equal(await page.evaluate(() => document.activeElement.className), 'trip-button');
  await page.evaluate(() => { const entry = window.callbacks['fleets/demo/vehicles/bike-01/track_points']; entry.cb(entry.result); });
  assert.equal(await page.evaluate(() => document.activeElement.className), 'trip-button');
  assert.match(await button.textContent(), /In progress/);
  await page.evaluate(() => window.callbacks['fleets/demo/vehicles/bike-01/track_points'].error({ code: 'permission-denied' }));
  assert.equal(await page.locator('#point-count').textContent(), '0');
  assert.equal(await page.locator('#connection-state').textContent(), 'Access unavailable');
  assert.equal(await page.locator('#fit-route').isDisabled(), true); assert.deepEqual(page.errors, []); await page.close();
});

test('marker icons, trip filter, photo on demand, and logout clear private image', async () => {
  const page = await pageFor('markers');
  await page.waitForFunction(() => document.querySelector('#marker-count').textContent === '3');
  assert.equal(await page.locator('#markers-list li').count(), 3);
  assert.equal(await page.locator('.navride-marker').count(), 3);
  assert.match(await page.locator('#markers-list').textContent(), /Save Point.*Food.*Danger|Danger.*Food.*Save Point/);
  assert.equal(await page.locator('#marker-photo').getAttribute('src'), null);
  await page.evaluate(() => {
    const canvas = document.createElement('canvas'); canvas.width=2; canvas.height=2;
    window.photoData=canvas.toDataURL('image/jpeg').split(',')[1];
  });
  await page.locator('#markers-list .marker-row').last().getByRole('button', { name: 'View photo for Save Point' }).click();
  await page.waitForFunction(() => document.querySelector('#marker-photo').complete && document.querySelector('#marker-photo').naturalWidth > 0);
  assert.equal(await page.locator('#marker-photo-dialog').isVisible(), true);
  await page.locator('#marker-photo-dialog').getByRole('button', { name: 'Close' }).click();
  await page.locator('#sign-out').click();
  assert.equal(await page.locator('#marker-photo-dialog').isVisible(), false);
  assert.equal(await page.locator('#marker-photo').getAttribute('src'), null);
  assert.equal(await page.locator('#marker-count').textContent(), '0');
  assert.deepEqual(page.errors, []); await page.close();
});

test('a late photo response cannot show after marker access is revoked', async () => {
  const page = await pageFor('markers');
  await page.waitForFunction(() => document.querySelector('#marker-count').textContent === '3');
  await page.evaluate(() => { window.deferPhoto=true; });
  await page.locator('#markers-list .marker-row').last().getByRole('button', { name: 'View photo for Save Point' }).click();
  await page.waitForFunction(() => window.deferred.length > 0);
  await page.evaluate(() => window.callbacks['fleets/demo/vehicles/bike-01/markers'].error({ code:'permission-denied' }));
  await page.evaluate(() => { window.deferred.forEach(resolve=>resolve()); });
  assert.equal(await page.locator('#marker-photo').getAttribute('src'), null);
  assert.equal(await page.locator('#marker-count').textContent(), '0');
  assert.deepEqual(page.errors, []); await page.close();
});

test('markers remain visible when their trip has fewer than two points', async () => {
  const page = await pageFor('markers');
  const otherTrip = '550e8400-e29b-41d4-a716-446655440009';
  await page.evaluate((trip) => {
    const entry = window.callbacks['fleets/demo/vehicles/bike-01/markers'];
    const marker = entry.result.docs[0];
    entry.result = { ...entry.result, docs: [...entry.result.docs,
      { id: '550e8400-e29b-41d4-a716-446655440010', data: () => ({ ...marker.data(), tripId: trip }) }], size: 4 };
    entry.cb(entry.result);
  }, otherTrip);
  await page.waitForFunction(() => document.querySelector('#marker-count').textContent === '4');
  assert.equal(await page.locator(`.trip-button[data-key="${otherTrip}"]`).count(), 0);
  assert.equal(await page.locator('#marker-count').textContent(), '4');
  assert.equal(await page.locator('.navride-marker').count(), 4);
  assert.equal(await page.locator('#fit-route').isEnabled(), true);
  assert.deepEqual(page.errors, []); await page.close();
});

test('a one-point trip and its point stay hidden without breaking the map', async () => {
  const page = await pageFor();
  await page.evaluate(() => {
    const entry = window.callbacks['fleets/demo/vehicles/bike-01/track_points'];
    entry.result = { ...entry.result, docs: entry.result.docs.slice(0, 1), size: 1 };
    entry.cb(entry.result);
  });
  await page.waitForFunction(() => document.querySelector('#trip-count').textContent === '0');
  assert.equal(await page.locator('#point-count').textContent(), '0');
  assert.equal(await page.locator('#points-list li').count(), 0);
  assert.deepEqual(page.errors, []); await page.close();
});

test('admin cleans a verified ended short trip while preserving its markers', async () => {
  const page = await pageFor('admin-short');
  await page.waitForFunction(() => window.writes.some((write) => write.delete?.includes('/trips/')));
  const deleted = await page.evaluate(() => window.writes.filter((write) => write.delete).map((write) => write.delete));
  assert.equal(deleted.length, 2);
  assert.ok(deleted.some((path) => path.endsWith('/track_points/p1')));
  assert.ok(deleted.some((path) => path.includes('/trips/')));
  assert.equal(await page.locator('#trip-count').textContent(), '0');
  assert.equal(await page.locator('#point-count').textContent(), '0');
  assert.equal(await page.locator('#marker-count').textContent(), '3');
  assert.deepEqual(page.errors, []); await page.close();
});

test('offline same-context reload preserves route, switching dates clears stale points', async () => {
  const page = await pageFor(); await page.evaluate(() => { window.offlineVehicle = true; });
  await page.locator('#load-button').click(); await page.locator('#dashboard-error').waitFor({ state: 'visible' });
  assert.equal(await page.locator('#point-count').textContent(), '2');
  assert.match(await page.locator('#connection-state').textContent(), /Offline/);
  await page.locator('#route-date').fill('2026-01-01'); await page.locator('#load-button').click();
  assert.equal(await page.locator('#point-count').textContent(), '0'); assert.deepEqual(page.errors, []); await page.close();
});

test('different trips have matching map, marker and legend colors that survive filtering and live updates', async () => {
  const page = await pageFor();
  await page.evaluate(() => {
    // Observe actual Leaflet calls, rather than only checking legend CSS.
    if (!window.L) throw new Error('Leaflet unavailable for route color test');
    window.routeDraws = []; window.markerDraws = [];
    const polyline = L.polyline, marker = L.circleMarker;
    L.polyline = (coordinates, options) => { window.routeDraws.push({ coordinates, ...options }); return polyline(coordinates, options); };
    L.circleMarker = (coordinates, options) => { window.markerDraws.push({ coordinates, ...options }); return marker(coordinates, options); };
    const tripId = '550e8400-e29b-41d4-a716-446655440003';
    const entry = window.callbacks['fleets/demo/vehicles/bike-01/track_points'];
    const extra = entry.result.docs.map((point, index) => ({ id: 'extra-' + index,
      data: () => ({ ...point.data(), tripId, capturedAt: { toDate: () => new Date(Date.now() - (5 - index) * 60000) } }) }));
    entry.result = { ...entry.result, docs: [...entry.result.docs, ...extra], size: 4 };
    entry.cb(entry.result);
  });
  await page.waitForFunction(() => document.querySelectorAll('.trip-button').length === 3);
  const colors = await page.locator('.trip-swatch:visible').evaluateAll((nodes) => nodes.map((node) => node.style.backgroundColor));
  assert.equal(new Set(colors).size, 2);
  const mapColors = await page.evaluate(() => window.routeDraws.slice(-2).map((draw) => draw.color));
  assert.equal(new Set(mapColors).size, 2);
  const toRgb = async (color) => page.evaluate((value) => {
    const node = document.createElement('span'); node.style.color = value; document.body.append(node);
    const result = getComputedStyle(node).color; node.remove(); return result;
  }, color);
  assert.deepEqual(new Set(await Promise.all(mapColors.map(toRgb))), new Set(colors));
  assert.deepEqual(await page.evaluate(() => window.markerDraws.slice(-4).map((draw) => draw.fillColor)),
    [mapColors[0], mapColors[0], mapColors[1], mapColors[1]]);
  await page.locator('.trip-button').last().click();
  assert.equal(await page.locator('#point-count').textContent(), '2');
  const filteredColor = await page.evaluate(() => window.routeDraws.at(-1).color);
  await page.evaluate(() => { const entry = window.callbacks['fleets/demo/vehicles/bike-01/track_points']; entry.cb(entry.result); });
  assert.equal(await page.evaluate(() => window.routeDraws.at(-1).color), filteredColor);
  assert.deepEqual(await page.locator('.trip-swatch:visible').evaluateAll((nodes) => nodes.map((node) => node.style.backgroundColor)), colors);
  const drawCount = await page.evaluate(() => window.routeDraws.length);
  await page.evaluate(() => { const entry = window.callbacks['fleets/demo/vehicles/bike-01/status/current']; entry.cb(entry.result); });
  assert.equal(await page.evaluate(() => window.routeDraws.length), drawCount, 'status-only updates must not redraw routes');
  await page.getByRole('button', { name: /^All trips/ }).click();
  assert.equal(await page.locator('#point-count').textContent(), '4');
  assert.deepEqual(page.errors, []);
  if (process.env.ARTIFACT_DIR) await page.screenshot({ path: `${process.env.ARTIFACT_DIR}/trip-colors.png`, fullPage: true });
  await page.close();
});

test('trip spanning midnight loads its original metadata', async () => {
  const page = await pageFor('midnight');
  await page.waitForFunction(() => !document.querySelector('#trip-list').textContent.includes('First point'));
  assert.equal(await page.locator('.trip-button').count(), 2);
  assert.match(await page.locator('.trip-button').last().textContent(), /In progress/);
  assert.equal(await page.locator('#metadata-limit').isVisible(), false); assert.deepEqual(page.errors, []); await page.close();
});

test('logout during an in-flight route load cannot leave the next session stuck', async () => {
  const page = await pageFor();
  await page.evaluate(() => { window.deferVehicle = true; document.querySelector('#filters').requestSubmit(); });
  await page.waitForFunction(() => window.deferred.length > 0); await page.locator('#sign-out').click();
  await page.evaluate(() => { window.deferVehicle = false; window.deferred.forEach((resolve) => resolve()); });
  await page.locator('#email').fill('driver@example.test'); await page.locator('#password').fill('synthetic-value');
  await page.locator('#login-button').click(); await page.waitForFunction(() => document.querySelector('#point-count').textContent === '2');
  assert.equal(await page.locator('#load-button').isDisabled(), false); assert.deepEqual(page.errors, []); await page.close();
});

test('admin archive is confirmed, reversible and does not delete history; unverified admin is denied', async () => {
  const page = await pageFor('admin'); await page.locator('#admin-panel summary').click();
  await page.locator('#admin-vehicles .admin-row').waitFor();
  await page.getByRole('button', { name: 'Archive Bike 01', exact: true }).click();
  assert.equal(await page.locator('#confirm-dialog').isVisible(), true);
  assert.equal(await page.evaluate(() => document.activeElement.textContent), 'Cancel');
  await page.keyboard.press('Escape'); assert.equal(await page.evaluate(() => window.writes.length), 0);
  await page.getByRole('button', { name: 'Archive Bike 01', exact: true }).click(); await page.locator('#confirm-ok').click();
  await page.waitForFunction(() => window.writes.length === 2);
  assert.equal(await page.evaluate(() => window.writes[0].data.archived), true);
  assert.equal(await page.evaluate(() => window.writes[1].data.latitude), null);
  // Escape must not reuse the previous dialog's confirmed return value.
  await page.getByRole('button', { name: 'Restore Bike 01', exact: true }).click(); await page.keyboard.press('Escape');
  assert.equal(await page.evaluate(() => window.writes.length), 2);
  await page.getByRole('button', { name: 'Restore Bike 01', exact: true }).click(); await page.locator('#confirm-ok').click();
  await page.waitForFunction(() => window.writes.length === 4);
  assert.equal(await page.evaluate(() => window.writes[2].data.archived), false);
  assert.equal(await page.evaluate(() => window.writes.some((write) => write.delete)), false);
  assert.deepEqual(page.errors, []); await page.close();
  const unverified = await pageFor('unverified');
  await unverified.locator('#verify-notice').waitFor({ state: 'visible' });
  assert.equal(await unverified.locator('#admin-panel').isVisible(), false);
  assert.equal(await unverified.locator('#verify-notice').isVisible(), true);
  await unverified.locator('#verify-email').click(); assert.equal(await unverified.evaluate(() => window.verifyEmail), true);
  assert.deepEqual(unverified.errors, []);
  await unverified.close();
});

test('admin can add a driver and vehicle with safe text rendering', async () => {
  const page = await pageFor('admin'); await page.locator('#admin-panel summary').click();
  await page.locator('#driver-uid').fill('driver-a'); await page.locator('#driver-name').fill('<img src=x onerror=alert(1)>');
  await page.locator('#driver-form button').click(); await page.waitForFunction(() => window.writes.length > 0);
  assert.equal(await page.locator('#admin-drivers img').count(), 0);
  await page.locator('#edit-fleet').fill('new-fleet'); await page.locator('#edit-vehicle').fill('new-bike');
  await page.locator('#edit-label').fill('New bike'); await page.locator('#edit-driver').fill('driver-a');
  await page.locator('#vehicle-form button[type=submit]').click();
  await page.waitForFunction(() => window.writes.some((write) => write.path === 'fleets/new-fleet/vehicles/new-bike'));
  assert.equal(await page.evaluate(() => window.writes.at(-1).data.driverUid), 'driver-a');
  assert.deepEqual(page.errors, []); await page.close();
});

test('marker panel aligns with the map card in empty and populated layouts', async () => {
  for (const scenario of ['driver', 'markers']) {
    const page = await pageFor(scenario);
    for (const width of [320, 375, 768, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate((value) => { document.documentElement.dataset.theme = value; }, theme);
        const measure = await page.evaluate(() => {
          const box = (selector) => document.querySelector(selector).getBoundingClientRect();
          const card = box('.map-card'), heading = box('#markers-title'), title = box('#map-title');
          const legend = box('.marker-heading > span');
          return { left: heading.left - card.left, aligned: Math.abs(heading.left - title.left),
            right: card.right - legend.right, overflow: document.documentElement.scrollWidth > innerWidth,
            rowsInside: [...document.querySelectorAll('.marker-row')].every((row) => {
              const bounds = row.getBoundingClientRect();
              return bounds.left >= heading.left && bounds.right <= card.right - 12;
            }) };
        });
        if (process.env.ARTIFACT_DIR && width === 1440 && theme === 'light') {
          await page.locator('.map-card').screenshot({ path: `${process.env.ARTIFACT_DIR}/markers-${scenario}.png` });
        }
        assert.ok(measure.left >= 12, `${scenario} ${width}: heading needs an inset, got ${measure.left}`);
        assert.ok(measure.aligned <= 1, `${scenario} ${width}: marker and map titles must align`);
        assert.ok(measure.right >= 12, `${scenario} ${width}: legend must not touch the border`);
        assert.equal(measure.rowsInside, true);
        assert.equal(measure.overflow, false);
      }
    }
    assert.deepEqual(page.errors, []);
    await page.close();
  }
});

test('responsive layouts, mobile identity and WCAG automated checks for both roles and themes', async () => {
  for (const role of ['login', 'driver', 'admin']) {
    const page = await pageFor(role);
    if (role === 'admin') { await page.locator('#admin-panel summary').click(); await page.locator('#admin-vehicles .admin-row').waitFor(); }
    for (const width of [320, 375, 768, 1024, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `${role} ${width}`);
    }
    if (role !== 'login') {
      await page.setViewportSize({ width: 375, height: 1000 });
      assert.equal(await page.locator('#account-email').isVisible(), true);
      if (role === 'driver') assert.ok((await page.locator('.map-card').boundingBox()).y < 1000);
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await page.evaluate(() => { document.documentElement.style.fontSize = ''; });
    await page.addScriptTag({ content: axe.source });
    for (const theme of ['dark', 'light']) {
      await page.evaluate((value) => { document.documentElement.dataset.theme = value; }, theme);
      await page.waitForTimeout(300); // Wait for the intentional CSS theme transition before measuring contrast.
      const results = await page.evaluate(async () => axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'] } }));
      assert.deepEqual(results.violations.map((item) => ({ id: item.id, targets: item.nodes.map((node) => node.target) })), [], `${role} ${theme}`);
    }
    if (process.env.ARTIFACT_DIR) await page.screenshot({ path: `${process.env.ARTIFACT_DIR}/${role}.png`, fullPage: true });
    assert.deepEqual(page.errors, []); await page.close();
  }
});
