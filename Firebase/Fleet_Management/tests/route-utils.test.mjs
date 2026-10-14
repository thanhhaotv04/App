import { test } from 'node:test';
import assert from 'node:assert/strict';
import { localDateKey, routeSegments, tripHistory, tripStyles, validId } from '../dashboard/route-utils.mjs';

test('fleet IDs cannot escape a Firestore document path', () => {
  assert.equal(validId('bike-01'), true);
  assert.equal(validId('../other'), false);
  assert.equal(validId(''), false);
  assert.equal(validId('a'.repeat(65)), false);
});

test('trip history omits trips with fewer than two GPS points', () => {
  const early = new Date('2026-10-09T08:00:00Z');
  const later = new Date('2026-10-09T12:00:00Z');
  assert.deepEqual(tripHistory([
    { id: 'a', startedAt: early, endedAt: later },
    { id: 'b', startedAt: later, endedAt: null },
    { id: 'c', startedAt: early, endedAt: later },
  ], [
    { tripId: 'a', capturedAt: early },
    { tripId: 'legacy-id', capturedAt: later },
    { tripId: 'c', capturedAt: early },
    { tripId: 'c', capturedAt: later },
  ]).map(({ id, pointCount }) => [id, pointCount]), [
    ['c', 2],
  ]);
});

test('verified point count keeps a trip spanning the selected date boundary', () => {
  const start = new Date('2026-10-09T23:59:00Z');
  const trip = { id: 'overnight', startedAt: start, endedAt: new Date('2026-10-10T00:10:00Z') };
  assert.equal(tripHistory([trip], [{ tripId: trip.id, capturedAt: start }]).length, 0);
  assert.equal(tripHistory([trip], [{ tripId: trip.id, capturedAt: start }],
    new Map([[trip.id, 2]])).length, 1);
});

test('local date uses the selected day and trips never join together', () => {
  assert.equal(localDateKey(new Date(2026, 9, 9)), '2026-10-09');
  assert.deepEqual(routeSegments([
    { tripId: 'a', latitude: 10, longitude: 106 },
    { tripId: 'a', latitude: 11, longitude: 107 },
    { tripId: 'b', latitude: 12, longitude: 108 },
  ]), [{ tripId: 'a', coordinates: [[10, 106], [11, 107]] }]);
});

test('trip colors and numbers are distinct, chronological and independent of input order', () => {
  const history = Array.from({ length: 100 }, (_, index) => ({ id: `trip-${index}`, startedAt: new Date(index * 60000) }));
  const styles = tripStyles(history);
  assert.equal(new Set([...styles.values()].map((style) => style.color)).size, 100);
  assert.deepEqual(tripStyles([...history].reverse()), styles);
  assert.deepEqual(tripStyles([...history, { id: 'new-trip', startedAt: new Date(100 * 60000) }]).get('trip-1'), styles.get('trip-1'));
  assert.equal(styles.get('trip-1').number, 2);
  assert.notEqual(styles.get('trip-8').dashArray, styles.get('trip-0').dashArray);
});

test('legacy routes use the same trip identity as their legend', () => {
  assert.deepEqual(routeSegments([
    { latitude: 10, longitude: 106 }, { tripId: '', latitude: 11, longitude: 107 },
  ]), [{ tripId: 'legacy', coordinates: [[10, 106], [11, 107]] }]);
});
