// Server-owner operation. Verify the account owner's identity before issuing a code.
import { randomBytes, createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDatabase, nameKey } from './database.js';
const name = process.argv[2];
if (!name) throw new Error('Usage: node recovery-code.js <username>');
const { db, transaction } = openDatabase(process.env.DATA_DIR || path.join(path.dirname(fileURLToPath(import.meta.url)), 'server-data'));
try {
  const account = db.prepare('SELECT id FROM accounts WHERE name_key=?').get(nameKey(name));
  if (!account) throw new Error('Account not found.');
  const code = randomBytes(32).toString('hex');
  transaction(() => {
    db.prepare('DELETE FROM recovery WHERE account_id=?').run(account.id);
    db.prepare('INSERT INTO recovery VALUES (?, ?, ?)').run(createHash('sha256').update(code).digest('hex'), account.id, Date.now() + 15 * 60000);
  });
  console.log(`Single-use recovery code (expires in 15 minutes): ${code}`);
} finally { db.close(); }
