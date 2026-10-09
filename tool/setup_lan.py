"""Provision a persistent signing identity and LAN CA outside the repository."""
import hashlib
import os
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
config = Path.home() / '.config' / 'money-manager'
config.mkdir(mode=0o700, parents=True, exist_ok=True)
os.chmod(config, 0o700)
os.umask(0o077)
settings = config / 'release.env'
if settings.exists():
    raise SystemExit('Already configured. Existing signing keys were retained: ' + str(config))
if (config / 'release.p12').exists() or (config / 'lan-ca.key').exists():
    raise SystemExit('Partial configuration exists; refusing to replace keys.')

def run(*args, env=None):
    subprocess.run(args, check=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

address = subprocess.check_output(['hostname', '-I'], text=True).split()[0]
host = subprocess.check_output(['hostname', '-s'], text=True).strip()
password = secrets.token_urlsafe(36)
env = {**os.environ, 'MM_STORE_PASSWORD': password}
run('keytool', '-genkeypair', '-keystore', str(config / 'release.p12'),
    '-storetype', 'PKCS12', '-storepass:env', 'MM_STORE_PASSWORD',
    '-keypass:env', 'MM_STORE_PASSWORD', '-alias', 'money-manager-lan',
    '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
    '-dname', 'CN=Money Manager LAN, O=Thanh Hao, C=VN', env=env)
run('keytool', '-exportcert', '-keystore', str(config / 'release.p12'),
    '-storepass:env', 'MM_STORE_PASSWORD', '-alias', 'money-manager-lan',
    '-file', str(config / 'android-signing.der'), env=env)
signer = hashlib.sha256((config / 'android-signing.der').read_bytes()).hexdigest()
run('openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes',
    '-keyout', str(config / 'lan-ca.key'), '-out', str(config / 'lan-ca.pem'),
    '-days', '3650', '-subj', '/CN=Money Manager LAN CA/O=Thanh Hao/C=VN',
    '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0',
    '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
run('openssl', 'req', '-newkey', 'rsa:3072', '-nodes',
    '-keyout', str(config / 'server.key'), '-out', str(config / 'server.csr'),
    '-subj', '/CN=Money Manager LAN/O=Thanh Hao/C=VN')
extensions = config / 'server.ext'
extensions.write_text('basicConstraints=critical,CA:FALSE\n'
                      'keyUsage=critical,digitalSignature,keyEncipherment\n'
                      'extendedKeyUsage=serverAuth\n'
                      f'subjectAltName=IP:{address},IP:127.0.0.1,DNS:localhost,DNS:{host},DNS:{host}.local\n')
run('openssl', 'x509', '-req', '-in', str(config / 'server.csr'),
    '-CA', str(config / 'lan-ca.pem'), '-CAkey', str(config / 'lan-ca.key'),
    '-CAcreateserial', '-days', '825', '-sha256', '-extfile', str(extensions),
    '-out', str(config / 'server.pem'))
(config / 'server-chain.pem').write_bytes((config / 'server.pem').read_bytes() + (config / 'lan-ca.pem').read_bytes())
values = {
    'MM_KEYSTORE': str(config / 'release.p12'), 'MM_STORE_PASSWORD': password,
    'MM_KEY_PASSWORD': password, 'MM_KEY_ALIAS': 'money-manager-lan',
    'MM_SIGNER_SHA256': signer, 'MM_APPLICATION_ID': 'com.thanhhao.money_manager.lan',
    'PUBLIC_BACKEND_URL': f'https://{address}:3002',
    'TLS_CERT': str(config / 'server-chain.pem'), 'TLS_KEY': str(config / 'server.key'),
    'CURL_CA_BUNDLE': str(config / 'lan-ca.pem'),
}
settings.write_text(''.join(f'{key}={shlex.quote(value)}\n' for key, value in values.items()))
backend = {key: values[key] for key in ['TLS_CERT', 'TLS_KEY']}
backend.update(PORT='3002', LAN_INSTALL_PORT='3003', ALLOWED_ORIGINS=f'https://{address}:3002')
(config / 'backend.env').write_text(''.join(f'{key}={shlex.quote(value)}\n' for key, value in backend.items()))
asset = root / 'assets' / 'certificates' / 'lan-ca.pem'
asset.parent.mkdir(parents=True, exist_ok=True)
asset.write_bytes((config / 'lan-ca.pem').read_bytes())
os.chmod(asset, 0o644)
backup = Path.home() / '.local' / 'share' / 'money-manager' / 'signing-backup'
backup.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
shutil.copytree(config, backup)
os.chmod(backup, 0o700)
print('Signing/TLS configuration:', config)
print('Protected backup:', backup)
print('Android signer SHA-256:', signer)
print('HTTPS backend:', values['PUBLIC_BACKEND_URL'])
print('First-install page:', f'http://{address}:3003')
