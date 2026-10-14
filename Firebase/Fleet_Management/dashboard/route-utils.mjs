export const validId = (value) => /^[A-Za-z0-9_-]{1,64}$/.test(value);

export function localDateKey(date) {
  const two = (value) => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

export function routeSegments(points) {
  const trips = new Map();
  for (const point of points) {
    const id = point.tripId || 'legacy';
    if (!trips.has(id)) trips.set(id, []);
    trips.get(id).push([point.latitude, point.longitude]);
  }
  return [...trips].filter(([, coordinates]) => coordinates.length > 1)
    .map(([tripId, coordinates]) => ({ tripId, coordinates }));
}

// Cùng bảng màu cho bản đồ và chú giải; không tính lại theo chuyến được lọc.
export function tripStyles(history) {
  const palette = ['#0072b2', '#d55e00', '#009e73', '#a64d99',
    '#867000', '#555bc4', '#a64450', '#4f6b38'];
  return new Map([...history].sort((a, b) => a.startedAt - b.startedAt || a.id.localeCompare(b.id))
    .map((trip, index) => [trip.id, {
      number: index + 1,
      color: palette[index] || `hsl(${(index * 137.508) % 360}, 65%, 38%)`,
      dashArray: ['', '10 5', '3 5', '12 4 3 4'][Math.floor(index / palette.length) % 4],
    }]));
}

export function tripHistory(trips, points, verifiedCounts = new Map()) {
  const byId = new Map(trips.map((trip) => [trip.id, { ...trip, hasRecord: true, pointCount: 0 }]));
  for (const point of points) {
    const id = point.tripId || 'legacy';
    if (!byId.has(id)) {
      byId.set(id, { id, startedAt: point.capturedAt, endedAt: null,
        hasRecord: false, pointCount: 0 });
    }
    byId.get(id).pointCount++;
  }
  for (const [id, count] of verifiedCounts) {
    if (byId.has(id)) byId.get(id).pointCount = Math.max(byId.get(id).pointCount, count);
  }
  return [...byId.values()].filter((trip) => trip.pointCount >= 2)
    .sort((a, b) => b.startedAt - a.startedAt);
}
