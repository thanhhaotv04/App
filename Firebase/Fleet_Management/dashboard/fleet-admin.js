import {
  collection, collectionGroup, deleteDoc, doc, documentId, getDocFromServer,
  getDocsFromServer, limit, orderBy, query, serverTimestamp, startAfter, writeBatch,
} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js';
import { validId } from './route-utils.mjs';
import { confirmAction, syncList } from './ui-utils.mjs';

const $ = (id) => document.getElementById(id);
const validUid = (value) => /^[A-Za-z0-9_-]{1,128}$/.test(value);
const inactive = () => ({ latitude: null, longitude: null, speedKmh: null,
  capturedAt: null, tripActive: false, updatedAt: serverTimestamp() });

export function createAdmin({ auth, db, onChanged, onView }) {
  let enabled = false;
  let generation = 0;
  let busy = false;
  let cursor;
  let vehicles = [];
  let members = [];
  let editing = null;
  const message = (id, text = '') => { $(id).textContent = text; $(id).hidden = !text; };
  const vehicleBase = (row) => ['fleets', row.fleet, 'vehicles', row.id];

  async function action(work) {
    if (!enabled || busy) return;
    busy = true;
    const token = generation;
    $('admin-panel').setAttribute('aria-busy', 'true');
    $('admin-panel').querySelectorAll('button').forEach((button) => { button.disabled = true; });
    message('admin-error'); message('admin-message');
    try { await work(() => enabled && token === generation); }
    catch (error) {
      if (enabled && token === generation) message('admin-error', error.code === 'permission-denied'
        ? 'Admin access was denied. Refresh your session.'
        : error.userMessage || 'Could not save or load data. Check your connection and try again.');
    } finally {
      busy = false;
      $('admin-panel').setAttribute('aria-busy', 'false');
      $('admin-panel').querySelectorAll('button').forEach((button) => { button.disabled = false; });
    }
  }
  function invalid(text) { throw Object.assign(new Error(text), { userMessage: text }); }
  async function ensureFleet(batch, id) {
    const ref = doc(db, 'fleets', id);
    if (!(await getDocFromServer(ref)).exists()) batch.set(ref, { name: id, updatedAt: serverTimestamp() });
  }
  function clearForm() {
    editing = null;
    $('vehicle-form-title').textContent = 'Add vehicle';
    $('edit-fleet').readOnly = false; $('edit-vehicle').readOnly = false;
    $('edit-vehicle').value = ''; $('edit-label').value = ''; $('edit-driver').value = '';
  }
  function edit(row) {
    editing = row;
    $('edit-fleet').value = row.fleet; $('edit-vehicle').value = row.id;
    $('edit-fleet').readOnly = true; $('edit-vehicle').readOnly = true;
    $('edit-label').value = row.label || row.id; $('edit-driver').value = row.driverUid || '';
    $('vehicle-form-title').textContent = `Edit ${row.id}${row.archived ? ' · Archived' : ''}`;
    $('edit-label').focus();
  }
  function renderVehicles() {
    syncList($('admin-vehicles'), vehicles.map((row) => ({ ...row, key: row.path })), (row) => {
      const node = document.createElement('div'); node.className = 'admin-row'; node.setAttribute('role', 'listitem');
      const copy = document.createElement('div'); copy.className = 'admin-row-copy'; const title = document.createElement('strong');
      const detail = document.createElement('small'); copy.append(title, detail); node.append(copy);
      for (const label of ['View route', 'Edit', 'Archive']) {
        const button = document.createElement('button'); button.type = 'button'; button.className = 'secondary-button';
        button.textContent = label; node.append(button);
      }
      return node;
    }, (node, row) => {
      node.querySelector('strong').textContent = `${row.label || row.id}${row.archived ? ' · Archived' : ''}`;
      node.querySelector('small').textContent = `${row.fleet} / ${row.id} · Driver: ${row.driverUid || 'Unassigned'}`;
      const [view, change, archive] = node.querySelectorAll('button');
      view.onclick = () => onView(row.fleet, row.id); change.onclick = () => edit(row);
      archive.textContent = row.archived ? 'Restore' : 'Archive';
      archive.setAttribute('aria-label', `${archive.textContent} ${row.label || row.id}`);
      archive.onclick = () => void action(async (current) => {
        const restoring = !!row.archived;
        if (!await confirmAction(`${restoring ? 'Restore' : 'Archive'} vehicle?`, restoring
          ? 'The assigned driver will regain access. Trip history is kept.'
          : 'Cloud sharing and driver access will stop. Trip history is kept. Local ESP32 navigation is unchanged.',
        restoring ? 'Restore' : 'Archive') || !current()) return;
        const batch = writeBatch(db); const base = vehicleBase(row);
        // Read the latest assignment before changing state; never overwrite an unseen reassignment.
        const latest = await getDocFromServer(doc(db, ...base));
        if (!current()) return;
        if (!latest.exists() || !!latest.data().archived !== !!row.archived) invalid('This vehicle changed. Refresh the list and try again.');
        batch.update(doc(db, ...base), { archived: !restoring, updatedAt: serverTimestamp() });
        batch.set(doc(db, ...base, 'status', 'current'), inactive());
        await batch.commit();
        if (!current()) return;
        clearForm(); await refresh(false, current); onChanged();
        message('admin-message', restoring ? 'Vehicle restored.' : 'Vehicle archived. History is kept.');
      });
    });
  }
  async function refresh(more = false, current = () => enabled) {
    const constraints = [orderBy(documentId()), ...(more && cursor ? [startAfter(cursor)] : []), limit(200)];
    const snapshot = await getDocsFromServer(query(collectionGroup(db, 'vehicles'), ...constraints));
    if (!current()) return;
    const rows = snapshot.docs.filter((item) => /^fleets\/[^/]+\/vehicles\/[^/]+$/.test(item.ref.path))
      .map((item) => ({ ...item.data(), id: item.id, fleet: item.ref.path.split('/')[1], path: item.ref.path }));
    vehicles = more ? [...vehicles, ...rows] : rows;
    cursor = snapshot.docs.at(-1); $('more-vehicles').hidden = snapshot.size < 200;
    renderVehicles();
    if (!vehicles.length) message('admin-message', 'No vehicles yet. Add a driver and a vehicle to begin.');
  }
  async function loadMembers(current) {
    const fleet = $('member-fleet').value.trim(); if (!validId(fleet)) invalid('Enter a valid Fleet ID.');
    const snapshot = await getDocsFromServer(query(collection(db, 'fleets', fleet, 'members'), limit(200)));
    if (!current()) return;
    members = snapshot.docs.map((item) => ({ ...item.data(), id: item.id, fleet, key: item.id }));
    syncList($('admin-drivers'), members, () => {
      const row = document.createElement('div'); row.className = 'admin-row'; row.setAttribute('role', 'listitem');
      const text = document.createElement('div'); text.className = 'admin-row-copy'; row.append(text);
      const button = document.createElement('button'); button.type = 'button'; button.className = 'secondary-button'; row.append(button);
      return row;
    }, (node, row) => {
      node.firstChild.textContent = `${row.displayName || 'Driver'} · ${row.id}`;
      const button = node.querySelector('button'); button.textContent = 'Remove access';
      button.setAttribute('aria-label', `Remove access for ${row.displayName || row.id}`);
      button.onclick = () => void action(async (stillCurrent) => {
        if (!await confirmAction('Remove driver access?', 'This driver will lose all cloud access in this fleet. Vehicles and trip history are kept.', 'Remove access') || !stillCurrent()) return;
        await deleteDoc(doc(db, 'fleets', row.fleet, 'members', row.id));
        if (!stillCurrent()) return;
        await loadMembers(stillCurrent); onChanged(); message('admin-message', 'Driver access removed.');
      });
    }, $('member-fleet'));
    if (snapshot.size >= 200) message('admin-message', 'Showing the first 200 members. Use Firebase Console for larger membership lists.');
    else if (!members.length) message('admin-message', 'No drivers in this fleet.');
  }
  $('vehicle-form').addEventListener('submit', (event) => {
    event.preventDefault(); void action(async (current) => {
      const fleet = $('edit-fleet').value.trim(); const id = $('edit-vehicle').value.trim();
      const label = $('edit-label').value.trim(); const driverUid = $('edit-driver').value.trim() || null;
      if (!validId(fleet) || !validId(id) || !label || label.length > 80 || (driverUid && !validUid(driverUid))) invalid('Check the vehicle fields.');
      const base = ['fleets', fleet, 'vehicles', id]; const ref = doc(db, ...base);
      const latest = await getDocFromServer(ref);
      if (!current()) return;
      if (!editing && latest.exists()) invalid('This Vehicle ID already exists. Edit it from the list instead.');
      if (editing && (!latest.exists() || latest.data().driverUid !== editing.driverUid
        || !!latest.data().archived !== !!editing.archived || latest.data().label !== editing.label)) invalid('This vehicle changed. Refresh before editing.');
      const archived = !!latest.data()?.archived;
      if (driverUid && !archived) {
        const member = await getDocFromServer(doc(db, 'fleets', fleet, 'members', driverUid));
        if (!member.exists() || member.data().role !== 'driver') invalid('Add this driver to the fleet before assigning a vehicle.');
      }
      const reassigned = latest.exists() && latest.data().driverUid !== driverUid;
      if (reassigned && !await confirmAction('Change vehicle assignment?', 'The new driver can read this vehicle’s history. The previous driver loses access and cloud sharing stops.', 'Change driver')) return;
      if (!current()) return;
      const batch = writeBatch(db); await ensureFleet(batch, fleet); if (!current()) return;
      const data = { label, driverUid, archived, updatedAt: serverTimestamp() };
      if (editing) batch.update(ref, data); else batch.set(ref, data);
      if (reassigned) batch.set(doc(db, ...base, 'status', 'current'), inactive());
      await batch.commit(); if (!current()) return;
      clearForm(); await refresh(false, current); onChanged(); message('admin-message', 'Vehicle saved.');
    });
  });
  $('driver-form').addEventListener('submit', (event) => {
    event.preventDefault(); void action(async (current) => {
      const fleet = $('driver-fleet').value.trim(); const uid = $('driver-uid').value.trim();
      const displayName = $('driver-name').value.trim();
      if (!validId(fleet) || !validUid(uid) || displayName.length > 80) invalid('Check the driver fields.');
      if (uid === auth.currentUser?.uid) invalid('The administrator does not need a driver membership.');
      const batch = writeBatch(db); await ensureFleet(batch, fleet); if (!current()) return;
      batch.set(doc(db, 'fleets', fleet, 'members', uid), { role: 'driver', displayName, updatedAt: serverTimestamp() });
      await batch.commit(); if (!current()) return;
      $('member-fleet').value = fleet; await loadMembers(current); message('admin-message', 'Driver access saved.');
    });
  });
  $('new-vehicle').addEventListener('click', clearForm);
  $('refresh-admin').addEventListener('click', () => void action((current) => refresh(false, current)));
  $('more-vehicles').addEventListener('click', () => void action((current) => refresh(true, current)));
  $('member-filter').addEventListener('submit', (event) => { event.preventDefault(); void action(loadMembers); });
  $('admin-panel').addEventListener('toggle', () => {
    if ($('admin-panel').open && enabled && !vehicles.length) void action((current) => refresh(false, current));
  });
  return {
    setEnabled(value) {
      if (enabled === value) return;
      enabled = value; generation++;
      $('admin-panel').hidden = !value;
      if (!value) {
        $('admin-panel').open = false; vehicles = []; members = []; cursor = null; clearForm();
        $('admin-vehicles').replaceChildren(); $('admin-drivers').replaceChildren();
        $('driver-uid').value = ''; $('driver-name').value = '';
        message('admin-message'); message('admin-error');
        if ($('confirm-dialog').open) $('confirm-dialog').close('cancel');
      }
    },
  };
}
