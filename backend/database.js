import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';

export const normalizeName = (value) => typeof value === 'string' ? value.normalize('NFC').trim() : '';
export const nameKey = (value) => normalizeName(value).toLocaleLowerCase('vi');

export function openDatabase(directory) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  fs.chmodSync(directory, 0o700);
  const file = path.join(directory, 'money-manager.sqlite');
  const db = new DatabaseSync(file);
  fs.chmodSync(file, 0o600);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, name_key TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS money (account_id TEXT PRIMARY KEY REFERENCES accounts(id), data TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions (hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS recovery (hash TEXT PRIMARY KEY, account_id TEXT UNIQUE NOT NULL REFERENCES accounts(id), expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);`);
  const transaction = (fn) => {
    db.exec('BEGIN IMMEDIATE');
    try { const value = fn(); db.exec('COMMIT'); return value; }
    catch (error) { db.exec('ROLLBACK'); throw error; }
  };
  // Import once, in one transaction. Never replace corrupt JSON with empty data.
  transaction(() => {
    if (db.prepare("SELECT 1 FROM metadata WHERE key='legacy-import'").get()) return;
    const read = (name, fallback) => {
      try { return JSON.parse(fs.readFileSync(path.join(directory, name), 'utf8')); }
      catch (error) { if (error.code === 'ENOENT') return fallback; throw error; }
    };
    const accounts = read('accounts.json', []);
    const money = read('money-manager.json', {});
    if (!Array.isArray(accounts) || !money || Array.isArray(money) || typeof money !== 'object') throw new Error('Invalid legacy database; original files preserved.');
    for (const account of accounts) {
      if (typeof account.id !== 'string' || !normalizeName(account.name) || !/^[a-f0-9]{32}:[a-f0-9]{64}$/.test(account.passwordHash)) throw new Error('Invalid legacy account; original files preserved.');
      db.prepare('INSERT INTO accounts VALUES (?, ?, ?, ?)').run(account.id, account.name, nameKey(account.name), account.passwordHash);
    }
    for (const [id, data] of Object.entries(money)) {
      if (!data || !Array.isArray(data.transactions) || !Array.isArray(data.recurring)) throw new Error('Invalid legacy money data; original files preserved.');
      db.prepare('INSERT INTO money VALUES (?, ?)').run(id, JSON.stringify(data));
    }
    db.prepare("INSERT INTO metadata VALUES ('legacy-import', 'complete')").run();
  });
  return { db, transaction };
}
