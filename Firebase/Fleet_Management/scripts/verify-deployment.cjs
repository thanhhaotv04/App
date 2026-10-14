// Chỉ đọc deployment và cấu hình bảo mật; không đọc/hiển thị GPS hay đăng nhập tài xế.
const fs = require('node:fs');
const path = require('node:path');
const { getProjectDefaultAccount, setActiveAccount } = require('firebase-tools/lib/auth');
const { requireAuth } = require('firebase-tools/lib/requireAuth');
const rules = require('firebase-tools/lib/gcp/rules');
const { Client } = require('firebase-tools/lib/apiv2');
const root = path.resolve(__dirname, '..');
const project = 'navride-96851';

async function main() {
  const results = {};
  for (const host of [`${project}.web.app`, `${project}.firebaseapp.com`]) {
    const response = await fetch(`https://${host}/`, { cache: 'no-store' });
    results[host] = {
      status: response.status,
      htmlMatchesLocal: await response.text() === fs.readFileSync(path.join(root, 'dashboard/index.html'), 'utf8'),
      headers: Object.fromEntries(['content-security-policy', 'strict-transport-security',
        'x-frame-options', 'x-content-type-options', 'permissions-policy', 'cache-control']
        .map((name) => [name, response.headers.get(name)])),
    };
  }
  results.assetsMatchLocal = {};
  for (const name of ['app.js', 'config.js', 'fleet-admin.js', 'ui-utils.mjs', 'styles.css', 'login-ui.js', 'route-utils.mjs']) {
    const response = await fetch(`https://${project}.web.app/${name}`, { cache: 'no-store' });
    results.assetsMatchLocal[name] = response.status === 200 && await response.text() ===
      fs.readFileSync(path.join(root, 'dashboard', name), 'utf8');
  }
  const denied = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/fleets/demo/vehicles/bike-01`);
  results.unauthenticatedVehicleRead = denied.status;
  const options = { project, projectRoot: root, nonInteractive: true };
  const account = getProjectDefaultAccount(root);
  if (!account) throw new Error('CLI login required to verify deployed rules.');
  setActiveAccount(options, account); await requireAuth(options);
  const releases = await rules.listAllReleases(project);
  const name = await rules.getLatestRulesetName(project, 'cloud.firestore', releases);
  const files = await rules.getRulesetContent(name);
  results.rulesMatchLocal = files.some((file) => file.content.trim() ===
    fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8').trim());
  const api = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'admin/v2' });
  const config = await api.get(`/projects/${project}/config`, { skipLog: { resBody: true } });
  results.emailEnumerationProtection = !!config.body.emailPrivacyConfig?.enableImprovedEmailPrivacy;
  const policy = config.body.passwordPolicyConfig;
  results.passwordPolicy = {
    state: policy?.passwordPolicyEnforcementState || 'Not configured',
    minLength: policy?.passwordPolicyVersions?.[0]?.customStrengthOptions?.minPasswordLength || null,
    forceUpgradeOnSignin: !!policy?.forceUpgradeOnSignin,
  };
  const check = new Client({ urlPrefix: 'https://firebaseappcheck.googleapis.com', apiVersion: 'v1beta' });
  const android = await check.get('/projects/navride-96851/apps/1:596937794277:android:5bee28a6845f61011baa0c/playIntegrityConfig', { skipLog: { resBody: true } });
  const web = await check.get('/projects/navride-96851/apps/1:596937794277:web:51d8c93ee3e83e391baa0c/recaptchaEnterpriseConfig', { skipLog: { resBody: true } });
  const services = await check.get(`/projects/${project}/services`, { skipLog: { resBody: true } });
  results.appCheck = {
    androidOffPlayAllowed: !!android.body.appIntegrity?.allowUnrecognizedVersion,
    webKeyConfigured: !!web.body.siteKey,
    services: Object.fromEntries((services.body.services || []).map((service) =>
      [service.name.split('/').pop(), service.enforcementMode || 'OFF'])),
  };
  console.log(JSON.stringify(results, null, 2));
  const passed = results.rulesMatchLocal && results.unauthenticatedVehicleRead === 403 &&
    Object.values(results.assetsMatchLocal).every(Boolean) &&
    [`${project}.web.app`, `${project}.firebaseapp.com`].every((host) => results[host].htmlMatchesLocal && results[host].status === 200);
  if (!passed) process.exitCode = 1;
}
main().catch((error) => {
  console.error(JSON.stringify({ error: 'Read-only deployment verification failed', status: error.status || error.code || 'network-error' }));
  process.exitCode = 1;
});
