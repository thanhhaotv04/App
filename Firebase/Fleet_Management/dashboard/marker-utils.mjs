// SVG cố định, không ghép chuỗi dữ liệu người dùng vào HTML.
export const markerTypes = Object.freeze({
  save_point: { label: 'Save Point', svg: '<ellipse cx="16" cy="28" rx="13" ry="4" fill="#16b978"/><path d="M16 1a11 11 0 0 0-11 11c0 8 11 18 11 18s11-10 11-18A11 11 0 0 0 16 1Z" fill="#e73125"/><circle cx="16" cy="12" r="4" fill="white"/>' },
  food: { label: 'Food', svg: '<circle cx="16" cy="16" r="7" fill="none" stroke="currentColor" stroke-width="2"/><path d="M4 4v9m4-9v9M2 4v6q0 4 4 4v14M28 4v24M25 4v10h3" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>' },
  danger: { label: 'Danger', svg: '<path d="M16 3 30 28H2Z" fill="#f5b82e" stroke="#422e09" stroke-width="2" stroke-linejoin="round"/><path d="M16 11v8" stroke="#241b09" stroke-width="3" stroke-linecap="round"/><circle cx="16" cy="23" r="1.8" fill="#241b09"/>' },
});

export function markerSvg(kind) {
  const type = Object.hasOwn(markerTypes, kind) ? markerTypes[kind] : null;
  return type ? `<svg viewBox="0 0 32 32" width="32" height="32" aria-hidden="true">${type.svg}</svg>` : '';
}

export function parseMarker(snapshot) {
  const data = snapshot.data();
  const capturedAt = data.capturedAt?.toDate?.();
  if (!Object.hasOwn(markerTypes, data.kind) || !Number.isFinite(data.latitude) || Math.abs(data.latitude) > 90
      || !Number.isFinite(data.longitude) || Math.abs(data.longitude) > 180
      || !Number.isFinite(data.accuracyMeters) || data.accuracyMeters < 0 || data.accuracyMeters > 50
      || !(capturedAt instanceof Date) || !Number.isFinite(capturedAt.getTime())
      || !/^[0-9a-f-]{36}$/.test(data.tripId || '')) return null;
  return { id: snapshot.id, kind: data.kind, latitude: data.latitude, longitude: data.longitude,
    accuracyMeters: data.accuracyMeters, tripId: data.tripId, capturedAt, hasPhoto: data.hasPhoto === true,
    note: typeof data.note === 'string' ? data.note.slice(0, 500) : '' };
}

export function photoSource(data) {
  if (data?.contentType !== 'image/jpeg' || typeof data.data !== 'string' || data.data.length > 204800
      || !/^\/9j\/[A-Za-z0-9+/]*={0,2}$/.test(data.data)) return null;
  return `data:image/jpeg;base64,${data.data}`;
}
