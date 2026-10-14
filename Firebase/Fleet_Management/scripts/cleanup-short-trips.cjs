// One-time operator cleanup. Dry run by default; never touches markers/photos.
const path = require('node:path');
const { getProjectDefaultAccount, setActiveAccount } = require('firebase-tools/lib/auth');
const { requireAuth } = require('firebase-tools/lib/requireAuth');
const { Client } = require('firebase-tools/lib/apiv2');

const project = 'navride-96851';
const root = path.resolve(__dirname, '..');
const [fleet, vehicle, mode] = process.argv.slice(2);
const safeId = (id) => /^[A-Za-z0-9_-]{1,64}$/.test(id || '');
if (!safeId(fleet) || !safeId(vehicle) || (mode && mode !== '--apply')) {
  console.error('Usage: node scripts/cleanup-short-trips.cjs FLEET VEHICLE [--apply]');
  process.exit(2);
}

async function main() {
  const options = { project, projectRoot: root, nonInteractive: true };
  const account = getProjectDefaultAccount(root);
  if (!account) throw new Error('Sign in to Firebase CLI first.');
  setActiveAccount(options, account);
  await requireAuth(options);
  const api = new Client({ urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1' });
  const parent = `/projects/${project}/databases/(default)/documents/fleets/${fleet}/vehicles/${vehicle}`;
  const pointQuery = async (id) => {
    const response = await api.post(`${parent}:runQuery`, { structuredQuery: {
      from: [{ collectionId: 'track_points' }],
      where: { fieldFilter: { field: { fieldPath: 'tripId' }, op: 'EQUAL', value: { stringValue: id } } },
      limit: 2,
    } }, { skipLog: { resBody: true } });
    return (response.body || []).map((item) => item.document).filter(Boolean);
  };
  let pageToken;
  let inspected = 0;
  let eligible = 0;
  let removed = 0;
  do {
    const suffix = `?pageSize=100${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const response = await api.get(`${parent}/trips${suffix}`, { skipLog: { resBody: true } });
    for (const trip of response.body.documents || []) {
      inspected++;
      if (!trip.fields?.endedAt?.timestampValue) continue;
      const id = trip.name.split('/').at(-1);
      if (!/^[0-9a-f-]{36}$/.test(id)) continue;
      let points = await pointQuery(id);
      if (points.length >= 2) continue;
      eligible++;
      if (mode !== '--apply') continue;
      // Re-read immediately before committing, with update-time preconditions.
      const latest = (await api.get(`/${trip.name}`, { skipLog: { resBody: true } })).body;
      if (!latest.fields?.endedAt?.timestampValue) continue;
      points = await pointQuery(id);
      if (points.length >= 2) continue;
      const writes = [...points, latest].map((document) => ({
        delete: document.name,
        currentDocument: { updateTime: document.updateTime },
      }));
      await api.post(`/projects/${project}/databases/(default)/documents:commit`, { writes },
        { skipLog: { resBody: true } });
      removed++;
    }
    pageToken = response.body.nextPageToken;
  } while (pageToken);
  console.log(JSON.stringify({ project, fleet, vehicle, inspected, eligible, removed,
    mode: mode === '--apply' ? 'applied' : 'dry-run', preserved: 'markers and photos' }));
}
main().catch((error) => {
  console.error(JSON.stringify({ error: 'Cleanup failed; no further trips processed', status: error.status || error.code || 'unknown' }));
  process.exitCode = 1;
});
