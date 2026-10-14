// Chạy bằng Firebase CLI đã đăng nhập; không cần service-account key.
// Mặc định chỉ kiểm tra. --apply tạo/cấu hình admin; --send-setup-email gửi email đặt mật khẩu.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { getProjectDefaultAccount, setActiveAccount } = require('firebase-tools/lib/auth');
const { requireAuth } = require('firebase-tools/lib/requireAuth');
const { Client, getAccessToken } = require('firebase-tools/lib/apiv2');
const project = 'navride-96851';
const email = 'thanhhao.admin@gmail.com';
const root = path.resolve(__dirname, '..');
const apply = process.argv.includes('--apply');
const sendEmail = process.argv.includes('--send-setup-email');
let phase = 'authenticate';

async function main() {
  const account = getProjectDefaultAccount(root);
  if (!account) throw new Error('Sign in to Firebase CLI first.');
  const options = { project, projectRoot: root, nonInteractive: true };
  setActiveAccount(options, account);
  await requireAuth(options);
  const api = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'v1' });
  // Firebase CLI mutates request options. Never reuse headers/body across requests,
  // especially between trusted OAuth calls and the public email endpoint.
  const hidden = () => ({ skipLog: { body: true, resBody: true, queryParams: true } });
  const config = fs.readFileSync(path.join(root, 'dashboard/config.js'), 'utf8');
  const apiKey = config.match(/apiKey:\s*['"]([^'"]+)/)?.[1];
  if (!apiKey || !config.includes(project)) throw new Error('Unexpected Firebase project config.');
  const response = await api.post(`/projects/${project}/accounts:lookup`, { email: [email] }, hidden());
  let user = response.body.users?.find((item) => item.email === email);
  if (!user && apply) {
    phase = 'create-account';
    const created = await api.post('/accounts:signUp', {
      targetProjectId: project, email, password: crypto.randomBytes(32).toString('base64url'),
      displayName: 'NavRide Administrator', emailVerified: false,
    }, { ...hidden(), resolveOnHTTPError: true });
    if (created.status >= 400) {
      const code = created.body?.error?.message;
      throw Object.assign(new Error('Create account failed'), { status: created.status,
        context: { body: { error: { message: code } } } });
    }
    user = { localId: created.body.localId, emailVerified: false };
  }
  if (!user) {
    console.log('Admin account does not exist. Use --apply to create it with a random, undisclosed password.');
    return;
  }
  if (user.disabled) throw new Error('The intended admin account is disabled. Review it in Firebase Console.');
  phase = 'configure-admin';
  const documentPath = `/projects/${project}/databases/(default)/documents/system/access`;
  async function cloudRequest(method, data) {
    const response = await fetch(`https://firestore.googleapis.com/v1${documentPath}${method === 'PATCH' ? '?currentDocument.exists=false' : ''}`, {
      method, headers: { Authorization: `Bearer ${await getAccessToken()}`, 'Content-Type': 'application/json' },
      body: data ? JSON.stringify(data) : undefined,
    });
    const body = await response.json();
    return { status: response.status, body };
  }
  const current = await cloudRequest('GET');
  if (current.status !== 200 && current.status !== 404) throw new Error('Cannot verify protected admin configuration.');
  const currentUid = current.body.fields?.adminUid?.stringValue;
  if (currentUid && currentUid !== user.localId) throw new Error('A different admin UID is configured. Review before replacing it.');
  if (apply && !currentUid) {
    const written = await cloudRequest('PATCH', { fields: { adminUid: { stringValue: user.localId } } });
    if (written.status >= 400) throw Object.assign(new Error('Configure failed'), { status: written.status,
      context: { body: { error: { message: written.body?.error?.status } } } });
  }
  if (sendEmail) {
    phase = 'send-email';
    if (!apply && !currentUid) throw new Error('Configure the administrator before sending the setup email.');
    const mail = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'v1', auth: false });
    const sent = await mail.post('/accounts:sendOobCode', { requestType: 'PASSWORD_RESET', email }, {
      ...hidden(), queryParams: { key: apiKey }, resolveOnHTTPError: true,
    });
    if (sent.status >= 400) throw Object.assign(new Error('Send email failed'), { status: sent.status,
      context: { body: { error: { message: sent.body?.error?.message } } } });
  }
  console.log(JSON.stringify({ accountExists: true, adminConfigured: !!currentUid || apply,
    emailVerified: !!user.emailVerified, setupEmailSent: sendEmail }));
}
main().catch((error) => {
  const status = error.status || error.context?.response?.statusCode || error.context?.response?.status;
  const code = error.context?.body?.error?.message;
  console.error(JSON.stringify({ error: 'Admin setup failed', phase, status,
    code: typeof code === 'string' ? code.replace(/https?:\/\/\S+/g, '[endpoint]')
      .replace(/AIza[A-Za-z0-9_-]+/g, '[api-key]').slice(0, 180) : undefined }));
  process.exitCode = 1;
});
