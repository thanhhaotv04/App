import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js';
import { initializeAppCheck, ReCaptchaEnterpriseProvider } from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app-check.js';
import {
  browserSessionPersistence,
  getAuth,
  inMemoryPersistence,
  onAuthStateChanged,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
  sendPasswordResetEmail,
  sendEmailVerification,
  reload,
} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js';
import {
  collection,
  collectionGroup,
  doc,
  documentId,
  getDocFromServer,
  getDocsFromServer,
  getFirestore,
  limit,
  onSnapshot,
  orderBy,
  query,
  startAfter,
  Timestamp,
  where,
  writeBatch,
} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js';
import { appCheckSiteKey, firebaseConfig } from './config.js';
import { localDateKey, routeSegments, tripHistory, tripStyles, validId } from './route-utils.mjs';
import { syncList } from './ui-utils.mjs';
import { createAdmin } from './fleet-admin.js';
import { markerTypes, markerSvg, parseMarker, photoSource } from './marker-utils.mjs';

const $ = (id) => document.getElementById(id);
const app = initializeApp(firebaseConfig);
initializeAppCheck(app, {
  provider: new ReCaptchaEnterpriseProvider(appCheckSiteKey),
  isTokenAutoRefreshEnabled: true,
});
const auth = getAuth(app);
const db = getFirestore(app);
const timeFormat = new Intl.DateTimeFormat('en-GB', {
  day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
});

let map;
let routeLayer;
let markerLayer;
let landmarks = [];
let markersFromCache = false;
let stopMarkers = () => {};
let photoToken = 0;
let points = [];
let trips = [];
let selectedTripId = '';
let styles = new Map();
let stopStatus = () => {};
let stopPoints = () => {};
let stopTrips = () => {};
let loadToken = 0;
let fitNextRoute = false;
let statusData = null;
let statusFromCache = false;
let pointsFromCache = false;
let tripsFromCache = false;
let isAdmin = false;
let session = 0;
let stopAccess = () => {};
let stopMembership = () => {};
let stopVehicles = () => {};
let stopVehicle = () => {};
let contextKey = '';
const streamFailures = new Set();
let extraTrips = new Map();
let extraStops = new Map();
let verifiedPointCounts = new Map();
let checkedShortTrips = new Set();
let tripsReady = false;
let pointsReady = false;
let vehicleToken = 0;
const adminEmail = 'thanhhao.admin@gmail.com';
const admin = createAdmin({ auth, db, onChanged: () => void refreshVehicles(), onView: async (fleet, vehicle) => {
  $('fleet-id').value = fleet;
  await refreshVehicles(vehicle);
  $('dashboard-title').focus({ preventScroll: true });
} });

function showError(id, message) {
  const element = $(id);
  element.textContent = message;
  element.hidden = !message;
}

function setConnection(label, tone = '') {
  $('connection-state').textContent = label;
  $('connection-state').dataset.tone = tone;
}

function stopRoute() {
  stopMarkers(); stopMarkers = () => {};
  stopStatus();
  stopPoints();
  stopTrips();
  stopStatus = () => {};
  stopPoints = () => {};
  stopTrips = () => {};
  stopVehicle(); stopVehicle = () => {};
  extraStops.forEach((stop) => stop()); extraStops.clear();
}

function resetRoute() {
  stopRoute();
  points = [];
  landmarks = [];
  markersFromCache = false;
  closeMarkerPhoto();
  markerLayer?.clearLayers();
  $('markers-list').replaceChildren();
  $('marker-count').textContent = '0';
  $('markers-empty').hidden = false;
  $('markers-limit').hidden = true;
  trips = [];
  verifiedPointCounts.clear();
  checkedShortTrips.clear();
  tripsReady = false;
  pointsReady = false;
  selectedTripId = '';
  styles.clear();
  statusData = null;
  statusFromCache = false;
  pointsFromCache = false;
  tripsFromCache = false;
  streamFailures.clear();
  extraTrips.clear();
  contextKey = '';
  routeLayer?.clearLayers();
  $('points-list').replaceChildren();
  $('point-count').textContent = '0';
  $('trip-count').textContent = '0';
  $('trip-list').replaceChildren();
  $('trip-state').textContent = '—';
  $('last-update').textContent = '—';
  $('vehicle-label').textContent = '—';
  $('fit-route').disabled = true;
  $('map-empty').hidden = false;
  $('points-empty').hidden = false;
  $('points-empty').textContent = 'No points loaded yet.';
  $('points-limit').hidden = true;
  $('trips-limit').hidden = true;
  $('trips-empty').hidden = false;
  $('metadata-limit').hidden = true;
  $('retry-route').hidden = true;
}

function updateStatus() {
  if (streamFailures.size || !navigator.onLine || statusFromCache || pointsFromCache || tripsFromCache || markersFromCache) {
    setConnection('Offline · last loaded data', 'warning');
    return;
  }
  if (!contextKey) return;
  if (!statusData) {
    $('trip-state').textContent = 'No trip yet';
    $('last-update').textContent = '—';
    setConnection('No current trip');
    return;
  }
  const updatedAt = statusData.updatedAt?.toDate?.();
  const capturedAt = statusData.capturedAt?.toDate?.();
  const ageMs = capturedAt ? Date.now() - capturedAt.getTime() : Infinity;
  $('trip-state').textContent = statusData.tripActive ? 'Active' : 'Trip ended';
  const displayedAt = statusData.tripActive ? capturedAt : updatedAt;
  $('last-update').textContent = displayedAt ? timeFormat.format(displayedAt) : '—';
  if (statusData.tripActive && ageMs >= -5 * 60_000 && ageMs < 2 * 60_000) setConnection('Live trip', 'live');
  else if (statusData.tripActive) setConnection('Update overdue', 'warning');
  else setConnection('Trip ended');
}

function createMap() {
  if (map || !window.L) return;
  // Avoid pending CSS zoom callbacks touching removed map panes during logout.
  map = L.map('map', { preferCanvas: true, zoomAnimation: false, fadeAnimation: false }).setView([10.776, 106.701], 12);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  }).addTo(map);
  routeLayer = L.featureGroup().addTo(map);
  markerLayer = L.featureGroup().addTo(map);
  const instance = map;
  setTimeout(() => { if (map === instance) instance.invalidateSize(); }, 0);
  renderPoints();
  if (points.length || landmarks.length) fitRoute();
}

function fitRoute() {
  const all = [...points.filter((point) => styles.has(point.tripId || 'legacy')), ...landmarks];
  const visible = selectedTripId ? all.filter((point) => (point.tripId || 'legacy') === selectedTripId) : all;
  if (!map || visible.length === 0) return;
  if (visible.length === 1) map.setView([visible[0].latitude, visible[0].longitude], 15, { animate: false });
  else map.fitBounds(L.latLngBounds(visible.map((point) => [point.latitude, point.longitude])),
    { padding: [35, 35], maxZoom: 16, animate: false });
}

function renderTrips() {
  const history = tripHistory([...new Map([...extraTrips, ...trips.map((trip) => [trip.id, trip])]).values()],
    points, verifiedPointCounts);
  const nextStyles = tripStyles(history);
  let redraw = JSON.stringify([...styles]) !== JSON.stringify([...nextStyles]);
  styles = nextStyles;
  if (selectedTripId && !history.some((trip) => trip.id === selectedTripId)) {
    selectedTripId = '';
    redraw = true;
  }
  $('trip-count').textContent = String(history.length);
  $('trips-limit').hidden = trips.length < 100;
  $('trips-empty').hidden = history.length > 0;
  const displayedPoints = points.filter((point) => styles.has(point.tripId || 'legacy')).length;
  const rows = history.length ? [{ key: '', label: 'All trips',
    detail: `${history.length} ${history.length === 1 ? 'trip' : 'trips'} · ${displayedPoints} points` }] : [];
  history.forEach((trip, index) => {
    const start = `${trip.hasRecord ? '' : 'First point · '}${timeFormat.format(trip.startedAt)}`;
    const end = trip.endedAt ? timeFormat.format(trip.endedAt)
      : trip.hasRecord ? (index === 0 && statusData?.tripActive
        && contextKey.endsWith(localDateKey(new Date())) ? 'In progress' : 'End not recorded') : 'Recorded points only';
    rows.push({ key: trip.id, label: `Trip ${styles.get(trip.id).number} · ${start}`,
      detail: `${end} · ${trip.pointCount} ${trip.pointCount === 1 ? 'point' : 'points'}` });
  });
  $('metadata-limit').hidden = !history.some((trip) => !trip.hasRecord);
  syncList($('trip-list'), rows, () => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'trip-button';
    const swatch = document.createElement('span');
    swatch.className = 'trip-swatch';
    swatch.setAttribute('aria-hidden', 'true');
    const title = document.createElement('strong');
    const subtitle = document.createElement('small');
    button.append(swatch, title, subtitle);
    button.addEventListener('click', () => {
      selectedTripId = button.dataset.key;
      fitNextRoute = true;
      renderTrips();
      renderPoints();
    });
    return button;
  }, (button, row) => {
    button.setAttribute('aria-pressed', String(selectedTripId === row.key));
    const style = styles.get(row.key);
    const swatch = button.querySelector('.trip-swatch');
    swatch.hidden = !style;
    if (style) swatch.style.backgroundColor = style.color;
    button.querySelector('strong').textContent = row.label;
    button.querySelector('small').textContent = row.detail;
  }, $('trips-title'));
  if (redraw) renderPoints();
}

function renderPoints() {
  const visible = points.filter((point) => styles.has(point.tripId || 'legacy') &&
    (!selectedTripId || (point.tripId || 'legacy') === selectedTripId));
  const visibleMarkers = selectedTripId ? landmarks.filter((item) => item.tripId === selectedTripId) : landmarks;
  routeLayer?.clearLayers();
  $('point-count').textContent = String(visible.length);
  $('fit-route').disabled = visible.length + visibleMarkers.length === 0 || !map;
  $('map-empty').hidden = visible.length + visibleMarkers.length > 0 && !!map;
  $('map-empty').textContent = map
    ? (selectedTripId ? 'No GPS points for this trip.' : 'No route points for this date.')
    : 'Map is unavailable. The point list still works.';
  $('points-empty').hidden = visible.length > 0;
  $('points-empty').textContent = selectedTripId
    ? 'No GPS points recorded for this trip.'
    : 'No route points for this date. A trip needs a genuine GPS fix before the first point appears.';
  $('points-limit').hidden = points.length < 1000;

  if (map) {
    for (const segment of routeSegments(visible)) {
      const style = styles.get(segment.tripId);
      L.polyline(segment.coordinates, { color: style.color, dashArray: style.dashArray,
        weight: 5, opacity: .9 }).addTo(routeLayer);
    }
  }
  const markers = new Map();
  visible.forEach((point, index) => {
    const style = styles.get(point.tripId || 'legacy');
    if (map) {
      const marker = L.circleMarker([point.latitude, point.longitude], {
        radius: index === visible.length - 1 ? 9 : 6,
        color: '#ffffff', weight: 2, fillColor: style.color, fillOpacity: 1,
      }).addTo(routeLayer);
      const popup = document.createElement('div');
      popup.textContent = `Trip ${style.number} · Point ${index + 1} · ${timeFormat.format(point.capturedAt)}`;
      marker.bindPopup(popup);
      markers.set(point.id, marker);
    }
  });
  syncList($('points-list'), visible.map((point, index) => ({ ...point, index, key: point.id })).reverse(), () => {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'point-button';
    const number = document.createElement('span');
    number.className = 'point-number';
    const copy = document.createElement('span');
    copy.className = 'point-text';
    const title = document.createElement('strong');
    const detail = document.createElement('small');
    copy.append(title, detail);
    button.append(number, copy);
    item.append(button);
    return item;
  }, (item, point) => {
    const button = item.querySelector('button');
    const style = styles.get(point.tripId || 'legacy');
    button.setAttribute('aria-label', `Trip ${style.number}, Point ${point.index + 1}, ${timeFormat.format(point.capturedAt)}`);
    item.querySelector('.point-number').textContent = String(point.index + 1);
    item.querySelector('.point-number').style.borderColor = style.color;
    item.querySelector('strong').textContent = timeFormat.format(point.capturedAt);
    item.querySelector('small').textContent = `Trip ${style.number} · ${point.speedKmh ?? '—'} km/h · GPS ±${Math.round(point.accuracyMeters)} m`;
    button.onclick = () => {
      if (!map) return;
      map.setView([point.latitude, point.longitude], Math.max(map.getZoom(), 15), { animate: false });
      markers.get(point.id)?.openPopup();
    };
  }, $('points-title'));
  renderMarkers(visibleMarkers);
  if (fitNextRoute && visible.length + visibleMarkers.length > 0) {
    fitNextRoute = false;
    fitRoute();
  }
}

function closeMarkerPhoto() {
  photoToken++;
  $('marker-photo-dialog').close();
  $('marker-photo').removeAttribute('src');
  $('marker-photo').hidden = true;
  $('marker-photo-status').textContent = '';
}

async function openMarkerPhoto(marker) {
  const token = ++photoToken;
  const routeToken = loadToken;
  const uid = auth.currentUser?.uid;
  const [fleet, vehicle] = contextKey.split('/');
  $('marker-photo').removeAttribute('src');
  $('marker-photo').hidden = true;
  $('marker-photo-title').textContent = `${markerTypes[marker.kind].label} · ${timeFormat.format(marker.capturedAt)}`;
  $('marker-photo-status').textContent = 'Loading photo…';
  $('marker-photo-dialog').showModal();
  try {
    const snapshot = await getDocFromServer(doc(db, 'fleets', fleet, 'vehicles', vehicle, 'markers', marker.id, 'photos', 'image'));
    if (token !== photoToken || routeToken !== loadToken || auth.currentUser?.uid !== uid) return;
    const src = snapshot.exists() ? photoSource(snapshot.data()) : null;
    if (!src) {
      $('marker-photo-status').textContent = 'Photo not available yet. It may still be syncing from the phone.';
      return;
    }
    const img = $('marker-photo');
    img.onerror = () => { img.removeAttribute('src'); img.hidden = true; $('marker-photo-status').textContent = 'Could not display this photo.'; };
    img.src = src; img.hidden = false;
    $('marker-photo-status').textContent = '';
  } catch (error) {
    if (token !== photoToken || routeToken !== loadToken || auth.currentUser?.uid !== uid) return;
    if (denied(error)) { closeMarkerPhoto(); routeFailure(error, routeToken, 'photo'); }
    else $('marker-photo-status').textContent = 'Photo unavailable offline. Close and try again when connected.';
  }
}

function renderMarkers(visible) {
  markerLayer?.clearLayers();
  $('marker-count').textContent = String(visible.length);
  $('markers-empty').hidden = visible.length > 0;
  $('markers-limit').hidden = landmarks.length < 200;
  const mapMarkers = new Map();
  for (const item of visible) {
    if (!map) break;
    const type = markerTypes[item.kind];
    const marker = L.marker([item.latitude, item.longitude], {
      icon: L.divIcon({ html: markerSvg(item.kind), className: 'navride-marker', iconSize: [44, 44], iconAnchor: [22, 22] }),
      title: type.label, alt: type.label, keyboard: true,
    }).addTo(markerLayer);
    const popup = document.createElement('div');
    const label = document.createElement('p');
    label.textContent = `${type.label} · ${timeFormat.format(item.capturedAt)}`;
    popup.append(label);
    if (item.note) {
      const note = document.createElement('p');
      note.textContent = item.note;
      popup.append(note);
    }
    if (item.hasPhoto) {
      const button = document.createElement('button'); button.className = 'secondary-button'; button.textContent = 'View photo';
      button.onclick = () => void openMarkerPhoto(item); popup.append(button);
    }
    marker.bindPopup(popup); mapMarkers.set(item.id, marker);
  }
  syncList($('markers-list'), visible.map((item) => ({ ...item, key: item.id })).reverse(), () => {
    const li = document.createElement('li'); li.className = 'marker-row';
    const locate = document.createElement('button'); locate.type = 'button';
    const icon = document.createElement('span'); icon.className = 'marker-symbol';
    const copy = document.createElement('span'); copy.append(document.createElement('strong'), document.createElement('small'));
    locate.append(icon, copy);
    const photo = document.createElement('button'); photo.type = 'button'; photo.className = 'secondary-button'; photo.textContent = 'Photo';
    li.append(locate, photo); return li;
  }, (li, item) => {
    const label = markerTypes[item.kind].label;
    li.querySelector('.marker-symbol').innerHTML = markerSvg(item.kind);
    li.querySelector('strong').textContent = label;
    li.querySelector('small').textContent = `${timeFormat.format(item.capturedAt)} · GPS ±${Math.round(item.accuracyMeters)} m`;
    const [locate, photo] = li.querySelectorAll('button');
    locate.setAttribute('aria-label', `${label}, ${timeFormat.format(item.capturedAt)}, show on map`);
    locate.onclick = () => {
      if (!map) return;
      map.setView([item.latitude, item.longitude], Math.max(map.getZoom(), 15), { animate: false });
      mapMarkers.get(item.id)?.openPopup();
    };
    photo.hidden = !item.hasPhoto; photo.setAttribute('aria-label', `View photo for ${label}`);
    photo.onclick = () => void openMarkerPhoto(item);
  }, $('markers-title'));
}

$('marker-photo-dialog').addEventListener('close', closeMarkerPhoto);

function parseTrip(snapshot) {
  const data = snapshot.data();
  const startedAt = data.startedAt?.toDate?.();
  if (!(startedAt instanceof Date) || !Number.isFinite(startedAt.getTime())) return null;
  const candidate = data.endedAt?.toDate?.();
  const endedAt = candidate instanceof Date && Number.isFinite(candidate.getTime()) && candidate >= startedAt ? candidate : null;
  return { id: snapshot.id, startedAt, endedAt };
}

function parsePoint(snapshot) {
  const data = snapshot.data();
  const capturedAt = data.capturedAt?.toDate?.();
  if (!Number.isFinite(data.latitude) || !Number.isFinite(data.longitude) ||
      Math.abs(data.latitude) > 90 || Math.abs(data.longitude) > 180 ||
      !Number.isFinite(data.accuracyMeters) || data.accuracyMeters < 0 || !(capturedAt instanceof Date) ||
      !Number.isFinite(capturedAt.getTime())) return null;
  return { id: snapshot.id, ...data, capturedAt };
}

function denied(error) {
  return ['permission-denied', 'unauthenticated'].includes(error?.code) || error?.message === 'not-found';
}

function routeFailure(error, token, source = 'vehicle') {
  if (token !== loadToken) return;
  if (denied(error)) {
    loadToken++;
    resetRoute();
    map?.setView([10.776, 106.701], 12);
    setConnection('Access unavailable', 'error');
    showError('dashboard-error', 'This vehicle is unavailable or your account no longer has access.');
  } else {
    streamFailures.add(source);
    updateStatus();
    $('retry-route').hidden = false;
    showError('dashboard-error', 'Connection interrupted. Last loaded data is shown. Retry when online.');
  }
  $('load-button').disabled = false;
  $('load-button').textContent = 'Show route';
}

function healthy(source) {
  streamFailures.delete(source);
  if (!streamFailures.size) {
    showError('dashboard-error', '');
    $('retry-route').hidden = true;
  }
  updateStatus();
}

function watchExtraTrips(base, token) {
  const needed = new Set([...points, ...landmarks].map((point) => point.tripId).filter((id) =>
    /^[0-9a-f-]{36}$/.test(id || '') && !trips.some((trip) => trip.id === id)));
  for (const [id, stop] of extraStops) {
    if (!needed.has(id)) { stop(); extraStops.delete(id); extraTrips.delete(id); streamFailures.delete(`trip:${id}`); }
  }
  for (const id of [...needed].slice(0, 100)) {
    if (extraStops.has(id)) continue;
    extraStops.set(id, onSnapshot(doc(db, ...base, 'trips', id), (snapshot) => {
      if (token !== loadToken) return;
      const trip = snapshot.exists() ? parseTrip(snapshot) : null;
      if (trip) extraTrips.set(id, trip); else extraTrips.delete(id);
      renderTrips(); checkShortTrips(base, token); healthy(`trip:${id}`);
    }, (error) => routeFailure(error, token, `trip:${id}`)));
  }
}

function checkShortTrips(base, token) {
  if (!tripsReady || !pointsReady || tripsFromCache || pointsFromCache || !navigator.onLine) return;
  const loadedCounts = new Map();
  for (const point of points) loadedCounts.set(point.tripId, (loadedCounts.get(point.tripId) || 0) + 1);
  const allTrips = new Map([...extraTrips, ...trips.map((trip) => [trip.id, trip])]);
  for (const trip of allTrips.values()) {
    if ((loadedCounts.get(trip.id) || 0) >= 2 ||
        verifiedPointCounts.has(trip.id) || checkedShortTrips.has(trip.id)) continue;
    checkedShortTrips.add(trip.id);
    void (async () => {
      try {
        const userId = auth.currentUser?.uid;
        const ref = doc(db, ...base, 'trips', trip.id);
        const latest = await getDocFromServer(ref);
        if (token !== loadToken || auth.currentUser?.uid !== userId ||
            !latest.exists() || !parseTrip(latest)) return;
        const matches = await getDocsFromServer(query(collection(db, ...base, 'track_points'),
          where('tripId', '==', trip.id), limit(2)));
        if (token !== loadToken || auth.currentUser?.uid !== userId) return;
        verifiedPointCounts.set(trip.id, matches.size);
        renderTrips();
      } catch {
        // Keep the trip hidden while the server count cannot be confirmed.
      }
    })();
  }
}

async function sweepShortTrips(accessToken) {
  const userId = auth.currentUser?.uid;
  const active = () => session === accessToken && isAdmin && auth.currentUser?.uid === userId;
  let vehicleCursor;
  try {
    do {
      const vehiclePage = await getDocsFromServer(query(collectionGroup(db, 'vehicles'),
        orderBy(documentId()), ...(vehicleCursor ? [startAfter(vehicleCursor)] : []), limit(200)));
      if (!active()) return;
      for (const vehicle of vehiclePage.docs) {
        if (!/^fleets\/[A-Za-z0-9_-]+\/vehicles\/[A-Za-z0-9_-]+$/.test(vehicle.ref.path)) continue;
        const base = vehicle.ref.path.split('/');
        let tripCursor;
        do {
          const tripPage = await getDocsFromServer(query(collection(db, ...base, 'trips'),
            orderBy(documentId()), ...(tripCursor ? [startAfter(tripCursor)] : []), limit(100)));
          if (!active()) return;
          for (const trip of tripPage.docs) {
            if (!parseTrip(trip)?.endedAt) continue;
            const latest = await getDocFromServer(trip.ref);
            if (!active()) return;
            if (!latest.exists() || !parseTrip(latest)?.endedAt) continue;
            const matches = await getDocsFromServer(query(collection(db, ...base, 'track_points'),
              where('tripId', '==', trip.id), limit(2)));
            if (!active()) return;
            if (matches.size >= 2) continue;
            const batch = writeBatch(db);
            for (const point of matches.docs) batch.delete(point.ref);
            batch.delete(trip.ref);
            await batch.commit();
          }
          tripCursor = tripPage.docs.at(-1);
          if (tripPage.size < 100) break;
        } while (active());
      }
      vehicleCursor = vehiclePage.docs.at(-1);
      if (vehiclePage.size < 200) break;
    } while (active());
  } catch {
    if (active()) showError('dashboard-error', 'Could not finish short-trip cleanup. Sign in again when online.');
  }
}

async function refreshVehicles(preferred = '') {
  const fleet = $('fleet-id').value.trim();
  const user = auth.currentUser;
  if (!user || !validId(fleet)) {
    showError('dashboard-error', 'Enter a valid Fleet ID.'); return;
  }
  const token = ++vehicleToken;
  const routeFleet = contextKey.split('/')[0];
  stopVehicles(); stopMembership();
  if (routeFleet && routeFleet !== fleet) { loadToken++; resetRoute(); }
  const select = $('vehicle-id');
  const previous = preferred || select.value;
  select.replaceChildren(new Option('Loading vehicles…', ''));
  select.disabled = true; $('load-button').disabled = true;
  if (!isAdmin) {
    stopMembership = onSnapshot(doc(db, 'fleets', fleet, 'members', user.uid), (snapshot) => {
      if (token !== vehicleToken) return;
      if (!snapshot.exists() || snapshot.data().role !== 'driver') {
        stopVehicles(); select.replaceChildren(new Option('No fleet access', ''));
        select.disabled = true; $('load-button').disabled = true;
        routeFailure({ code: 'permission-denied' }, loadToken);
        $('load-button').disabled = true;
      }
    }, (error) => { if (token === vehicleToken) routeFailure(error, loadToken); });
  }
  const constraints = isAdmin ? [limit(200)] : [where('driverUid', '==', user.uid), limit(200)];
  stopVehicles = onSnapshot(query(collection(db, 'fleets', fleet, 'vehicles'), ...constraints),
    (snapshot) => {
      if (token !== vehicleToken || auth.currentUser?.uid !== user.uid) return;
      const rows = snapshot.docs.filter((item) => isAdmin || !item.data().archived);
      const current = select.value || previous;
      select.replaceChildren(...rows.map((item) => new Option(
        `${item.data().label || item.id}${item.data().archived ? ' · Archived' : ''}`, item.id)));
      $('vehicle-limit').hidden = snapshot.size < 200;
      if (!rows.length) select.append(new Option('No assigned vehicles', ''));
      select.disabled = !rows.length; $('load-button').disabled = !rows.length;
      if (rows.some((item) => item.id === current)) select.value = current;
      const next = select.value;
      if (!next) {
        loadToken++; resetRoute(); setConnection('No vehicles assigned');
        showError('dashboard-error', isAdmin ? 'No vehicles in this fleet. Open Fleet management to add one.'
          : 'No active vehicle is assigned to your account in this fleet. Ask your administrator.');
      } else if (contextKey.split('/').slice(0, 2).join('/') !== `${fleet}/${next}` || preferred) {
        preferred = ''; void loadVehicle();
      }
    }, (error) => {
      if (token !== vehicleToken) return;
      select.disabled = true; $('load-button').disabled = true;
      routeFailure(error, loadToken);
      $('load-button').disabled = true;
    });
}

async function loadVehicle() {
  const fleetId = $('fleet-id').value.trim();
  const vehicleId = $('vehicle-id').value.trim();
  const dateText = $('route-date').value;
  if (!validId(fleetId) || !validId(vehicleId) || !/^\d{4}-\d{2}-\d{2}$/.test(dateText)) {
    showError('dashboard-error', 'Enter a valid fleet, vehicle and date.');
    return;
  }
  const start = new Date(`${dateText}T00:00:00`);
  if (!Number.isFinite(start.getTime()) || localDateKey(start) !== dateText) {
    showError('dashboard-error', 'Choose a valid date.');
    return;
  }
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  const token = ++loadToken;
  const nextKey = `${fleetId}/${vehicleId}/${dateText}`;
  stopRoute();
  if (contextKey !== nextKey) resetRoute();
  showError('dashboard-error', '');
  $('load-button').disabled = true;
  $('load-button').textContent = 'Loading…';
  setConnection('Loading…');
  try {
    const base = ['fleets', fleetId, 'vehicles', vehicleId];
    const vehicle = await getDocFromServer(doc(db, ...base));
    if (token !== loadToken || !auth.currentUser) return;
    if (!vehicle.exists() || (!isAdmin && (vehicle.data().archived || vehicle.data().driverUid !== auth.currentUser.uid))) throw new Error('not-found');
    resetRoute(); contextKey = nextKey;
    $('vehicle-label').textContent = vehicle.data().label || vehicleId;
    $('points-empty').textContent = 'Loading route points…';
    fitNextRoute = true;
    stopVehicle = onSnapshot(doc(db, ...base), (snapshot) => {
      if (token !== loadToken) return;
      if (!snapshot.exists() || (!isAdmin && (snapshot.data().archived || snapshot.data().driverUid !== auth.currentUser?.uid))) {
        routeFailure({ code: 'permission-denied' }, token); return;
      }
      $('vehicle-label').textContent = `${snapshot.data().label || vehicleId}${snapshot.data().archived ? ' · Archived' : ''}`;
    }, (error) => routeFailure(error, token));
    stopStatus = onSnapshot(doc(db, ...base, 'status', 'current'),
      { includeMetadataChanges: true }, (snapshot) => {
        if (token !== loadToken) return;
        statusData = snapshot.exists() ? snapshot.data() : null;
        statusFromCache = snapshot.metadata.fromCache;
        healthy('status'); renderTrips();
      }, (error) => routeFailure(error, token, 'status'));
    const tripQuery = query(collection(db, ...base, 'trips'),
      where('startedAt', '>=', Timestamp.fromDate(start)),
      where('startedAt', '<', Timestamp.fromDate(end)),
      orderBy('startedAt', 'desc'), limit(100));
    stopTrips = onSnapshot(tripQuery, { includeMetadataChanges: true }, (snapshot) => {
      if (token !== loadToken) return;
      trips = snapshot.docs.map(parseTrip).filter(Boolean);
      tripsFromCache = snapshot.metadata.fromCache;
      tripsReady = true;
      watchExtraTrips(base, token);
      renderTrips();
      checkShortTrips(base, token);
      healthy('trips');
    }, (error) => routeFailure(error, token, 'trips'));
    const history = query(collection(db, ...base, 'track_points'),
      where('capturedAt', '>=', Timestamp.fromDate(start)),
      where('capturedAt', '<', Timestamp.fromDate(end)),
      orderBy('capturedAt', 'asc'), limit(1000));
    stopPoints = onSnapshot(history, { includeMetadataChanges: true }, (snapshot) => {
      if (token !== loadToken) return;
      points = snapshot.docs.map(parsePoint).filter(Boolean);
      pointsFromCache = snapshot.metadata.fromCache;
      pointsReady = true;
      watchExtraTrips(base, token);
      renderTrips();
      renderPoints();
      checkShortTrips(base, token);
      healthy('points');
    }, (error) => routeFailure(error, token, 'points'));
    const markerQuery = query(collection(db, ...base, 'markers'),
      where('capturedAt', '>=', Timestamp.fromDate(start)), where('capturedAt', '<', Timestamp.fromDate(end)),
      orderBy('capturedAt', 'asc'), limit(200));
    stopMarkers = onSnapshot(markerQuery, { includeMetadataChanges: true }, (snapshot) => {
      if (token !== loadToken) return;
      landmarks = snapshot.docs.map(parseMarker).filter(Boolean);
      markersFromCache = snapshot.metadata.fromCache;
      watchExtraTrips(base, token); renderTrips(); renderPoints(); healthy('markers');
    }, (error) => routeFailure(error, token, 'markers'));
  } catch (error) {
    routeFailure(error, token);
  } finally {
    if (token === loadToken) {
      $('load-button').disabled = false;
      $('load-button').textContent = 'Show route';
    }
  }
}

$('route-date').value = localDateKey(new Date());
$('filters').addEventListener('submit', (event) => { event.preventDefault(); void loadVehicle(); });
$('fleet-id').addEventListener('change', () => void refreshVehicles());
$('retry-route').addEventListener('click', () => void refreshVehicles($('vehicle-id').value));
window.addEventListener('online', updateStatus);
window.addEventListener('offline', updateStatus);
$('fit-route').addEventListener('click', fitRoute);
$('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  $('login-button').disabled = true;
  $('login-button').textContent = 'Signing in…';
  $('login-form').setAttribute('aria-busy', 'true');
  showError('login-error', '');
  try {
    await signInWithEmailAndPassword(auth, $('email').value.trim(), $('password').value);
  } catch (error) {
    showError('login-error', error.code === 'auth/network-request-failed'
      ? 'Connect to the internet and try again.' : error.code === 'auth/too-many-requests'
        ? 'Too many attempts. Wait a few minutes before trying again.'
        : 'Could not sign in. Check your email and password.');
  } finally {
    $('password').value = '';
    $('login-button').disabled = false;
    $('login-button').textContent = 'Sign in';
    $('login-form').setAttribute('aria-busy', 'false');
  }
});
$('sign-out').addEventListener('click', async () => {
  $('sign-out').disabled = true;
  try { await signOut(auth); }
  catch { showError('dashboard-error', 'Could not sign out. Try again.'); }
  finally { $('sign-out').disabled = false; }
});
$('reset-password').addEventListener('click', async () => {
  if (!$('email').reportValidity()) return;
  $('reset-password').disabled = true;
  try {
    await sendPasswordResetEmail(auth, $('email').value.trim());
    showError('login-error', 'If this account exists, a password reset email has been sent. Check your inbox and spam folder.');
  } catch (error) {
    showError('login-error', error.code === 'auth/network-request-failed' ? 'Check your internet connection and try again.'
      : error.code === 'auth/too-many-requests' ? 'Too many attempts. Wait a few minutes before trying again.'
      : 'If this account exists, check your inbox for a password reset email.');
  } finally { $('reset-password').disabled = false; }
});
$('verify-email').addEventListener('click', async () => {
  const user = auth.currentUser; if (!user) return;
  $('verify-email').disabled = true;
  try { await sendEmailVerification(user); showError('dashboard-error', 'Verification email sent. Check your inbox and spam folder.'); }
  catch { showError('dashboard-error', 'Could not send verification email. Wait a few minutes and retry.'); }
  finally { $('verify-email').disabled = false; }
});
$('check-verification').addEventListener('click', async () => {
  const user = auth.currentUser; if (!user) return;
  $('check-verification').disabled = true;
  try {
    await reload(user); await user.getIdToken(true);
    if (auth.currentUser?.uid === user.uid) await initializeAccess(user);
  } catch { showError('dashboard-error', 'Could not refresh verification. Check your connection.'); }
  finally { $('check-verification').disabled = false; }
});

async function initializeAccess(user) {
  const token = ++session;
  let cleanupStarted = false;
  loadToken++; vehicleToken++; resetRoute();
  stopAccess(); stopVehicles(); stopMembership();
  admin.setEnabled(false); isAdmin = false;
  setConnection('Checking access…');
  stopAccess = onSnapshot(doc(db, 'system', 'access'), (snapshot) => {
    if (token !== session || auth.currentUser?.uid !== user.uid) return;
    const intendedAdmin = snapshot.data()?.adminUid === user.uid && user.email === adminEmail;
    const nextAdmin = intendedAdmin && user.emailVerified;
    $('verify-notice').hidden = !intendedAdmin || user.emailVerified;
    if (isAdmin !== nextAdmin) { loadToken++; resetRoute(); }
    isAdmin = nextAdmin; admin.setEnabled(isAdmin);
    if (isAdmin && !cleanupStarted && !snapshot.metadata?.fromCache && navigator.onLine) {
      cleanupStarted = true;
      void sweepShortTrips(token);
    }
    $('account-role').textContent = isAdmin ? 'Administrator' : intendedAdmin ? 'Verify email to manage fleet' : 'Driver';
    $('account-role').hidden = false;
    void refreshVehicles();
  }, (error) => {
    if (token !== session) return;
    isAdmin = false; admin.setEnabled(false); stopVehicles(); stopMembership();
    routeFailure(error, loadToken);
    $('load-button').disabled = true;
  });
}

try {
  await setPersistence(auth, browserSessionPersistence);
} catch {
  await setPersistence(auth, inMemoryPersistence);
}
window.navrideAuthReady = true;
window.dispatchEvent(new Event('navride-auth-ready'));
onAuthStateChanged(auth, (user) => {
  session++; vehicleToken++;
  stopAccess(); stopVehicles(); stopMembership();
  isAdmin = false; admin.setEnabled(false);
  loadToken++;
  resetRoute();
  $('login-view').hidden = !!user;
  $('dashboard-view').hidden = !user;
  $('sign-out').hidden = !user;
  $('account-email').textContent = user?.email || '';
  $('account-email').hidden = !user;
  $('account-role').hidden = true;
  $('verify-notice').hidden = true;
  showError('dashboard-error', '');
  $('load-button').disabled = false; $('load-button').textContent = 'Show route';
  if (user) {
    if (window.L) createMap();
    else window.addEventListener('load', () => {
      if (auth.currentUser) createMap();
    }, { once: true });
    map?.invalidateSize();
    $('dashboard-title').focus({ preventScroll: true });
    void initializeAccess(user);
  } else {
    map?.remove();
    map = undefined;
    routeLayer = undefined;
    markerLayer = undefined;
    $('vehicle-id').replaceChildren(new Option('Select a vehicle', ''));
    $('login-title').focus({ preventScroll: true });
  }
});
setInterval(() => {
  if (!$('dashboard-view').hidden) updateStatus();
}, 30_000);
