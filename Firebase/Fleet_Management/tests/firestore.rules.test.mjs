import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, collectionGroup, deleteDoc, doc, documentId, getDoc, getDocs, limit, orderBy, query, where, serverTimestamp, setDoc, writeBatch } from 'firebase/firestore';
import { createMockUserToken } from '@firebase/util';

let env;
const statusPath = ['fleets', 'fleet-a', 'vehicles', 'bike-a', 'status', 'current'];
const trackPath = ['fleets', 'fleet-a', 'vehicles', 'bike-a', 'track_points'];
const tripPath = ['fleets', 'fleet-a', 'vehicles', 'bike-a', 'trips'];
const markerPath = ['fleets', 'fleet-a', 'vehicles', 'bike-a', 'markers'];
const pointId = '550e8400-e29b-41d4-a716-446655440000';
const tripId = '550e8400-e29b-41d4-a716-446655440001';
const markerId = '550e8400-e29b-41d4-a716-446655440002';
const adminDb = () => env.authenticatedContext('admin', { email: 'thanhhao.admin@gmail.com', email_verified: true }).firestore();
const bounded = (db, ...path) => query(collection(db, ...path), limit(path.at(-1) === 'trips' ? 100 : 1000));

function trip(db, overrides = {}) {
  return setDoc(doc(db, ...tripPath, tripId), {
    driverUid: 'driver-a',
    startedAt: new Date(),
    endedAt: null,
    updatedAt: serverTimestamp(),
    ...overrides,
  });
}

function trackPoint(db, overrides = {}, id = pointId) {
  return setDoc(doc(db, ...trackPath, id), {
    latitude: 10.776,
    longitude: 106.701,
    accuracyMeters: 12,
    speedKmh: 35,
    tripId,
    capturedAt: new Date(),
    uploadedAt: serverTimestamp(),
    ...overrides,
  });
}

function status(db, overrides = {}) {
  return setDoc(doc(db, ...statusPath), {
    latitude: 10.776,
    longitude: 106.701,
    speedKmh: 35,
    tripActive: true,
    capturedAt: new Date(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });
}

function marker(db, overrides = {}) {
  return setDoc(doc(db, ...markerPath, markerId), {
    driverUid: 'driver-a', kind: 'save_point', source: 'phone', tripId,
    latitude: 10.776, longitude: 106.701, accuracyMeters: 12,
    capturedAt: new Date(), hasPhoto: false, uploadedAt: serverTimestamp(),
    ...overrides,
  });
}

function markerPhoto(db, overrides = {}) {
  return setDoc(doc(db, ...markerPath, markerId, 'photos', 'image'), {
    driverUid: 'driver-a', contentType: 'image/jpeg', data: '/9j/2Q==',
    uploadedAt: serverTimestamp(), ...overrides,
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-navride-fleet',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'fleets', 'fleet-a', 'members', 'admin'), { role: 'admin' });
    await setDoc(doc(db, 'system', 'access'), { adminUid: 'admin' });
    await setDoc(doc(db, 'fleets', 'fleet-a', 'members', 'driver-a'), { role: 'driver' });
    await setDoc(doc(db, 'fleets', 'fleet-a', 'vehicles', 'bike-a'), {
      label: 'Bike A',
      driverUid: 'driver-a',
    });
  });
});

after(async () => env?.cleanup());

test('assigned driver and admin can read marker, other account cannot', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  const other = env.authenticatedContext('driver-b').firestore();
  await assertSucceeds(trip(driver));
  await assertSucceeds(marker(driver));
  await assertSucceeds(getDoc(doc(driver, ...markerPath, markerId)));
  await assertSucceeds(getDoc(doc(adminDb(), ...markerPath, markerId)));
  await assertFails(getDoc(doc(other, ...markerPath, markerId)));
  await assertFails(marker(other));
  await assertFails(marker(driver, { kind: 'danger' }));
  await assertSucceeds(deleteDoc(doc(driver, ...markerPath, markerId)));
});

test('marker edit is owner-only and changes only kind, note and server time', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await trip(driver); await marker(driver);
  const edit = (db, extra = {}) => setDoc(doc(db, ...markerPath, markerId), {
    kind: 'food', note: 'Lunch stop', updatedAt: serverTimestamp(), ...extra,
  }, { merge: true });
  await assertSucceeds(edit(driver));
  await assertFails(edit(driver, { latitude: 11 }));
  await assertFails(edit(driver, { driverUid: 'driver-b' }));
  await assertFails(edit(driver, { hasPhoto: true }));
  await assertFails(edit(driver, { kind: 'invalid' }));
  await assertFails(edit(driver, { note: 'a'.repeat(501) }));
  await assertFails(edit(driver, { updatedAt: new Date(0) }));
  await assertFails(edit(env.authenticatedContext('driver-b').firestore()));
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'fleets', 'fleet-a', 'members', 'driver-b'), { role: 'driver' });
    await setDoc(doc(db, 'fleets', 'fleet-a', 'vehicles', 'bike-a'), { driverUid: 'driver-b' });
  });
  const next = env.authenticatedContext('driver-b').firestore();
  await assertFails(edit(next));
  await assertFails(deleteDoc(doc(next, ...markerPath, markerId)));
});

test('marker and private photo must be deleted atomically by their owner', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await trip(driver); await marker(driver, { hasPhoto: true }); await markerPhoto(driver);
  await assertFails(deleteDoc(doc(driver, ...markerPath, markerId)));
  await assertFails(deleteDoc(doc(driver, ...markerPath, markerId, 'photos', 'image')));
  const remove = (db) => {
    const batch = writeBatch(db);
    batch.delete(doc(db, ...markerPath, markerId, 'photos', 'image'));
    batch.delete(doc(db, ...markerPath, markerId));
    return batch.commit();
  };
  await assertFails(remove(env.authenticatedContext('driver-b').firestore()));
  await assertSucceeds(remove(driver));
  assert.equal((await getDoc(doc(driver, ...markerPath, markerId))).exists(), false);
  assert.equal((await getDoc(doc(driver, ...markerPath, markerId, 'photos', 'image'))).exists(), false);
  await marker(driver);
  await assertSucceeds(remove(driver)); // no photo also supports the same atomic deletion
});

test('REST marker history is bounded and cannot be read by another driver', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await trip(driver); await marker(driver);
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-navride-fleet/databases/(default)/documents/${markerPath.join('/')}?pageSize=200&orderBy=capturedAt%20desc`;
  const read = (uid) => fetch(url, { headers: { Authorization: `Bearer ${createMockUserToken({ sub: uid }, 'demo-navride-fleet')}` } });
  const result = await read('driver-a');
  assert.equal(result.status, 200, await result.text());
  assert.equal((await read('driver-b')).status, 403);
});

test('marker kind, GPS accuracy, ownership, trip and query limit are checked', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await assertFails(marker(driver));
  await assertSucceeds(trip(driver));
  await assertFails(marker(driver, { kind: 'tracker' }));
  await assertFails(marker(driver, { source: 'server' }));
  await assertFails(marker(driver, { accuracyMeters: 60 }));
  await assertFails(marker(driver, { driverUid: 'driver-b' }));
  await assertFails(marker(driver, { tripId: pointId }));
  await assertSucceeds(marker(driver, { kind: 'danger' }));
  await assertSucceeds(getDocs(query(collection(driver, ...markerPath), limit(200))));
  await assertFails(getDocs(query(collection(driver, ...markerPath), limit(201))));
});

test('photo requires own photo marker, bounded JPEG; no list or cross-account read', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  const other = env.authenticatedContext('driver-b').firestore();
  await assertSucceeds(trip(driver));
  await assertSucceeds(marker(driver, { hasPhoto: true }));
  await assertFails(markerPhoto(driver, { contentType: 'image/png' }));
  await assertFails(markerPhoto(driver, { data: 'javascript:alert(1)' }));
  await assertFails(markerPhoto(driver, { data: '/9j/' + 'A'.repeat(204801) }));
  await assertSucceeds(markerPhoto(driver));
  await assertSucceeds(getDoc(doc(driver, ...markerPath, markerId, 'photos', 'image')));
  await assertSucceeds(getDoc(doc(adminDb(), ...markerPath, markerId, 'photos', 'image')));
  await assertFails(getDoc(doc(other, ...markerPath, markerId, 'photos', 'image')));
  await assertFails(getDocs(query(collection(driver, ...markerPath, markerId, 'photos'), limit(1))));
  await assertFails(deleteDoc(doc(driver, ...markerPath, markerId, 'photos', 'image')));
});

test('only the assigned driver can publish current position', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  const other = env.authenticatedContext('driver-b').firestore();
  const anonymous = env.unauthenticatedContext().firestore();
  await assertSucceeds(status(driver));
  await assertFails(status(other));
  await assertFails(status(anonymous));
  assert.equal(
    (await assertSucceeds(getDoc(doc(driver, ...statusPath)))).data().speedKmh,
    35,
  );
  await assertFails(getDoc(doc(other, ...statusPath)));
  await assertSucceeds(getDoc(doc(adminDb(), ...statusPath)));
});

test('a driver cannot self-promote, change the vehicle or delete its status', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await assertFails(setDoc(doc(driver, 'fleets', 'fleet-a', 'members', 'driver-a'), { role: 'admin' }));
  await assertFails(setDoc(doc(driver, 'fleets', 'fleet-a', 'vehicles', 'bike-a'), {
    label: 'Stolen', driverUid: 'driver-a',
  }));
  await assertSucceeds(status(driver));
  await assertFails(deleteDoc(doc(driver, ...statusPath)));
});

test('revoking fleet membership also revokes an existing vehicle assignment', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await env.withSecurityRulesDisabled((context) =>
    deleteDoc(doc(context.firestore(), 'fleets', 'fleet-a', 'members', 'driver-a')),
  );
  await assertFails(status(driver));
  await assertFails(getDoc(doc(driver, 'fleets', 'fleet-a', 'vehicles', 'bike-a')));
});

test('the single global admin sees every fleet but cannot forge driver telemetry', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'fleets', 'fleet-b', 'members', 'admin-b'), { role: 'admin' });
    await setDoc(doc(db, 'fleets', 'fleet-b', 'members', 'driver-b'), { role: 'driver' });
    await setDoc(doc(db, 'fleets', 'fleet-b', 'vehicles', 'bike-b'), {
      label: 'Bike B', driverUid: 'driver-b',
    });
  });
  const admin = adminDb();
  await assertSucceeds(getDoc(doc(admin, 'fleets', 'fleet-b', 'vehicles', 'bike-b')));
  const legacyAdmin = env.authenticatedContext('admin-b').firestore();
  await assertFails(getDoc(doc(legacyAdmin, 'fleets', 'fleet-b', 'vehicles', 'bike-b')));
  await assertFails(status(admin));
});

test('rejects invalid or forged telemetry', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await assertFails(status(driver, { latitude: 100 }));
  await assertFails(status(driver, { speedKmh: -1 }));
  await assertFails(status(driver, { updatedAt: new Date('2000-01-01') }));
  await assertFails(status(driver, { capturedAt: new Date(Date.now() + 60 * 60_000) }));
  await assertFails(status(driver, { pairingPin: '123456' }));
  await assertFails(status(driver, { tripActive: false }));
  await assertSucceeds(status(driver, {
    latitude: null, longitude: null, speedKmh: null, tripActive: false, capturedAt: null,
  }));
});

test('only assigned drivers create route points, and only fleet members read them', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  const admin = adminDb();
  const other = env.authenticatedContext('driver-b').firestore();
  const anonymous = env.unauthenticatedContext().firestore();
  await assertFails(trackPoint(other));
  await assertFails(trackPoint(anonymous));
  await assertSucceeds(trip(driver));
  await assertSucceeds(trackPoint(driver));
  await assertSucceeds(getDoc(doc(driver, ...trackPath, pointId)));
  await assertSucceeds(getDocs(bounded(driver, ...trackPath)));
  await assertSucceeds(getDocs(bounded(admin, ...trackPath)));
  await assertFails(getDocs(bounded(other, ...trackPath)));
  await assertFails(getDoc(doc(anonymous, ...trackPath, pointId)));
  await assertFails(trackPoint(driver, { latitude: 10.78 }));
  await assertFails(deleteDoc(doc(driver, ...trackPath, pointId)));
});

test('rejects malformed route points but accepts delayed offline uploads', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  await assertSucceeds(trip(driver));
  await assertFails(trackPoint(driver, { latitude: 91 }));
  await assertFails(trackPoint(driver, { accuracyMeters: 51 }));
  await assertSucceeds(trackPoint(driver, { capturedAt: new Date('2026-01-01') },
    '550e8400-e29b-41d4-a716-446655440002'));
  await assertFails(trackPoint(driver, { capturedAt: new Date(Date.now() + 60 * 60_000) }));
  await assertFails(trackPoint(driver, { uploadedAt: new Date() }));
  await assertFails(trackPoint(driver, { privateNote: 'should not be stored' }));
  await assertSucceeds(trackPoint(driver, { speedKmh: null }));
});

test('only assigned drivers can create and finish an immutable trip', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  const admin = adminDb();
  const other = env.authenticatedContext('driver-b').firestore();
  await assertFails(trip(other));
  await assertFails(trip(driver, { driverUid: 'admin' }));
  await assertSucceeds(trip(driver));
  await assertSucceeds(getDocs(bounded(driver, ...tripPath)));
  await assertSucceeds(getDocs(bounded(admin, ...tripPath)));
  await assertFails(getDocs(bounded(other, ...tripPath)));
  await assertFails(deleteDoc(doc(driver, ...tripPath, tripId)));
  await assertFails(setDoc(doc(driver, ...tripPath, tripId), {
    endedAt: new Date('2000-01-01'), updatedAt: serverTimestamp(),
  }, { merge: true }));
  await assertSucceeds(setDoc(doc(driver, ...tripPath, tripId), {
    endedAt: new Date(), updatedAt: serverTimestamp(),
  }, { merge: true }));
  await assertFails(setDoc(doc(driver, ...tripPath, tripId), {
    endedAt: new Date(), updatedAt: serverTimestamp(),
  }, { merge: true }));
});

test('email spoofing, unverified email, legacy role and self-promotion cannot grant admin', async () => {
  const spoof = env.authenticatedContext('attacker', { email: 'thanhhao.admin@gmail.com', email_verified: true }).firestore();
  const unverified = env.authenticatedContext('admin', { email: 'thanhhao.admin@gmail.com', email_verified: false }).firestore();
  const wrongEmail = env.authenticatedContext('admin', { email: 'other@example.com', email_verified: true }).firestore();
  for (const db of [spoof, unverified, wrongEmail, env.unauthenticatedContext().firestore()]) {
    await assertFails(getDocs(query(collectionGroup(db, 'vehicles'), limit(200))));
    await assertFails(setDoc(doc(db, 'system', 'access'), { adminUid: 'attacker' }));
  }
  await assertFails(setDoc(doc(adminDb(), 'system', 'access'), { adminUid: 'attacker' }));
  await assertFails(setDoc(doc(adminDb(), 'fleets', 'fleet-a', 'members', 'attacker'), {
    role: 'admin', displayName: 'Fake', updatedAt: serverTimestamp(),
  }));
});

test('bounded queries expose only assigned vehicles to a driver and all vehicles to admin', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'fleets', 'fleet-a', 'vehicles', 'bike-b'), { driverUid: 'driver-b' });
    await setDoc(doc(context.firestore(), 'fleets', 'fleet-b', 'vehicles', 'bike-c'), { driverUid: null });
  });
  const db = env.authenticatedContext('driver-a').firestore();
  const ref = collection(db, 'fleets', 'fleet-a', 'vehicles');
  await assertFails(getDocs(query(ref, limit(200))));
  const own = await assertSucceeds(getDocs(query(ref, where('driverUid', '==', 'driver-a'), limit(200))));
  assert.deepEqual(own.docs.map((item) => item.id), ['bike-a']);
  await assertFails(getDocs(query(ref, where('driverUid', '==', 'driver-a'))));
  await assertFails(getDocs(collection(adminDb(), ...trackPath)));
  await assertFails(getDocs(query(collection(adminDb(), ...trackPath), limit(1001))));
  const global = await assertSucceeds(getDocs(query(collectionGroup(adminDb(), 'vehicles'), orderBy(documentId()), limit(200))));
  assert.equal(global.size, 3);
});

test('reassignment preserves vehicle history but cannot mutate or append to the previous driver trip', async () => {
  const old = env.authenticatedContext('driver-a').firestore();
  await trip(old); await trackPoint(old);
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'fleets', 'fleet-a', 'members', 'driver-b'), { role: 'driver' });
    await setDoc(doc(db, 'fleets', 'fleet-a', 'vehicles', 'bike-a'), { label: 'Bike A', driverUid: 'driver-b' });
  });
  const next = env.authenticatedContext('driver-b').firestore();
  await assertSucceeds(getDoc(doc(next, ...tripPath, tripId)));
  await assertFails(getDoc(doc(old, ...tripPath, tripId)));
  await assertFails(setDoc(doc(next, ...tripPath, tripId), { endedAt: new Date(), updatedAt: serverTimestamp() }, { merge: true }));
  await assertFails(trackPoint(next, {}, '550e8400-e29b-41d4-a716-446655440003'));
  await assertFails(trackPoint(old, {}, '550e8400-e29b-41d4-a716-446655440003'));
});

test('admin can add drivers, archive and restore vehicles but never delete history', async () => {
  const admin = adminDb(); const driver = env.authenticatedContext('driver-a').firestore();
  await trip(driver); await trackPoint(driver);
  const vehicle = doc(admin, 'fleets', 'fleet-a', 'vehicles', 'bike-a');
  await assertSucceeds(setDoc(vehicle, { label: 'Bike A', driverUid: 'driver-a', archived: true, updatedAt: serverTimestamp() }));
  await assertFails(status(driver)); await assertFails(getDoc(doc(driver, ...tripPath, tripId)));
  await assertSucceeds(getDoc(doc(admin, ...trackPath, pointId)));
  await assertFails(deleteDoc(vehicle)); await assertFails(deleteDoc(doc(admin, ...trackPath, pointId)));
  await assertSucceeds(setDoc(vehicle, { label: 'Bike A', driverUid: 'driver-a', archived: false, updatedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(driver, ...trackPath, pointId)));
  await assertSucceeds(status(admin, { latitude: null, longitude: null, speedKmh: null, tripActive: false, capturedAt: null }));
  await assertSucceeds(setDoc(doc(admin, 'fleets', 'fleet-a', 'members', 'driver-b'), {
    role: 'driver', displayName: 'Driver B', updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(admin, 'fleets', 'fleet-a', 'vehicles', 'new'), {
    label: 'New', driverUid: 'non-member', archived: false, updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(admin, 'fleets', 'fleet-a', 'vehicles', 'new'), {
    label: 'New', driverUid: 'driver-b', archived: false, updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(deleteDoc(doc(admin, 'fleets', 'fleet-a', 'members', 'driver-a')));
  await assertFails(status(driver));
  // Even after revocation, archiving must retain the old assignment/history.
  await assertSucceeds(setDoc(vehicle, { label: 'Bike A', driverUid: 'driver-a', archived: true, updatedAt: serverTimestamp() }));
});

test('admin can clean an ended short trip without deleting its marker or photo', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  const admin = adminDb();
  await trip(driver); await trackPoint(driver);
  await marker(driver, { hasPhoto: true }); await markerPhoto(driver);
  await assertFails(deleteDoc(doc(admin, ...tripPath, tripId)));
  await assertFails(deleteDoc(doc(admin, ...trackPath, pointId)));
  await assertSucceeds(setDoc(doc(driver, ...tripPath, tripId), {
    endedAt: new Date(), updatedAt: serverTimestamp(),
  }, { merge: true }));
  await assertFails(deleteDoc(doc(driver, ...tripPath, tripId)));
  await assertFails(deleteDoc(doc(driver, ...trackPath, pointId)));
  const batch = writeBatch(admin);
  batch.delete(doc(admin, ...trackPath, pointId));
  batch.delete(doc(admin, ...tripPath, tripId));
  await assertSucceeds(batch.commit());
  assert.equal((await getDoc(doc(admin, ...tripPath, tripId))).exists(), false);
  assert.equal((await getDoc(doc(admin, ...trackPath, pointId))).exists(), false);
  assert.equal((await getDoc(doc(admin, ...markerPath, markerId))).exists(), true);
  assert.equal((await getDoc(doc(admin, ...markerPath, markerId, 'photos', 'image'))).exists(), true);
});

test('offline atomic trip + point upload is compatible with ownership validation', async () => {
  const driver = env.authenticatedContext('driver-a').firestore();
  const batch = writeBatch(driver);
  batch.set(doc(driver, ...tripPath, tripId), { driverUid: 'driver-a', startedAt: new Date('2026-01-01'), endedAt: null, updatedAt: serverTimestamp() });
  batch.set(doc(driver, ...trackPath, pointId), { latitude: 10, longitude: 106, accuracyMeters: 10,
    speedKmh: null, tripId, capturedAt: new Date('2026-01-01'), uploadedAt: serverTimestamp() });
  await assertSucceeds(batch.commit());
});

test('Android outbox REST protocol respects rules, immutable points and idempotent ACK reads', async () => {
  const projectId = 'demo-navride-fleet';
  const documents = `projects/${projectId}/databases/(default)/documents`;
  const base = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/${documents}`;
  const token = createMockUserToken({ sub: 'driver-a' }, projectId);
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const tripDocument = [...tripPath, tripId].join('/');
  const pointDocument = [...trackPath, pointId].join('/');
  const commit = async (path, fields, { end = false, transform = 'updatedAt' } = {}) => {
    const write = {
      update: { name: `${documents}/${path}`, fields },
      currentDocument: { exists: end },
      updateTransforms: [{ fieldPath: transform, setToServerValue: 'REQUEST_TIME' }],
      ...(end ? { updateMask: { fieldPaths: ['endedAt'] } } : {}),
    };
    return fetch(`${base}:commit`, { method: 'POST', headers, body: JSON.stringify({ writes: [write] }) });
  };
  const stamp = { timestampValue: '2026-01-01T00:00:00.000Z' };
  assert.equal((await fetch(`${base}/${pointDocument}`, { headers })).status, 404);
  const start = await commit(tripDocument, {
    driverUid: { stringValue: 'driver-a' }, startedAt: stamp, endedAt: { nullValue: null },
  });
  assert.equal(start.status, 200, await start.text());
  const fields = {
    latitude: { doubleValue: 0 }, longitude: { doubleValue: 0 },
    accuracyMeters: { doubleValue: 10 }, speedKmh: { integerValue: '42' },
    tripId: { stringValue: tripId }, capturedAt: stamp,
  };
  const point = await commit(pointDocument, fields, { transform: 'uploadedAt' });
  assert.equal(point.status, 200, await point.text());
  // Lost ACK: GET verifies the existing point; replay must never mutate it.
  const ack = await fetch(`${base}/${pointDocument}`, { headers });
  assert.equal(ack.status, 200);
  const saved = (await ack.json()).fields;
  assert.equal(Number(saved.speedKmh.integerValue), 42);
  assert.ok(saved.uploadedAt.timestampValue);
  assert.notEqual((await commit(pointDocument, fields, { transform: 'uploadedAt' })).status, 200);
  const end = await commit(tripDocument, {
    endedAt: { timestampValue: '2026-01-01T00:02:00.000Z' },
  }, { end: true });
  assert.equal(end.status, 200, await end.text());
  const ended = (await (await fetch(`${base}/${tripDocument}`, { headers })).json()).fields;
  assert.equal(ended.driverUid.stringValue, 'driver-a');
  assert.ok(ended.endedAt.timestampValue);
  const otherHeaders = { ...headers, Authorization: `Bearer ${createMockUserToken({ sub: 'driver-b' }, projectId)}` };
  assert.equal((await fetch(`${base}/${pointDocument}`, { headers: otherHeaders })).status, 403);
});
