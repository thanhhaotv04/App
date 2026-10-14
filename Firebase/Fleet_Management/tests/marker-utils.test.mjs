import { test } from 'node:test';
import assert from 'node:assert/strict';
import { markerSvg, parseMarker, photoSource } from '../dashboard/marker-utils.mjs';

test('only three fixed marker symbols and sound coordinates enter the map', () => {
  for (const kind of ['save_point', 'food', 'danger']) assert.match(markerSvg(kind), /<svg/);
  assert.equal(markerSvg('<img src=x onerror=alert(1)>'), '');
  const row = (data) => ({ id: 'id', data: () => ({ kind: 'food', latitude: 10, longitude: 106,
    accuracyMeters: 8, tripId: '550e8400-e29b-41d4-a716-446655440001',
    capturedAt: { toDate: () => new Date() }, ...data }) });
  assert.equal(parseMarker(row({ latitude: 91 })), null);
  assert.equal(parseMarker(row({ kind: 'unknown' })), null);
  assert.equal(parseMarker(row({})).kind, 'food');
});

test('photo viewer accepts only bounded base64 JPEG', () => {
  assert.equal(photoSource({ contentType: 'image/png', data: '/9j/2Q==' }), null);
  assert.equal(photoSource({ contentType: 'image/jpeg', data: 'javascript:alert(1)' }), null);
  assert.equal(photoSource({ contentType: 'image/jpeg', data: '/9j/2Q==' }), 'data:image/jpeg;base64,/9j/2Q==');
});
