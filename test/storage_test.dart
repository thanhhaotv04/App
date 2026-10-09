import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_reminder/src/models.dart';
import 'package:task_reminder/src/storage.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'password changes replace the verifier and clear the old session token',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AuthCache.register('Alice', 'password-123');
      final prefs = await SharedPreferences.getInstance();
      final verifierKey = prefs.getKeys().singleWhere(
        (key) => key.startsWith('task-reminder-auth-verifier-v2:'),
      );
      expect(prefs.getString(verifierKey), startsWith('3:'));
      await AuthCache.saveToken(
        'old-token',
        baseUrl: 'https://a.example',
        userName: 'Alice',
      );
      await AuthCache.updatePassword('Alice', 'new-password-456');
      expect(await AuthCache.load(), ('Alice', 'new-password-456'));
      expect(
        await AuthCache.readToken(
          baseUrl: 'https://a.example',
          userName: 'Alice',
        ),
        isEmpty,
      );
      await AuthCache.clear();
      expect(await AuthCache.signIn('Alice', 'password-123'), isNotNull);
      expect(await AuthCache.signIn('Alice', 'new-password-456'), isNull);
    },
  );

  test('removing and undoing a schedule preserves its stable ID', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TaskStore.load(userName: 'Alice');
    final now = DateTime.now();
    final original = TaskAssignment(
      id: 'a',
      taskId: 'seed-1',
      date: now,
      createdAt: now,
      updatedAt: now,
    );
    await store.addAssignment(original);
    await store.markDone('a');
    expect(store.assignments().single.done, isTrue);
    await store.unmarkDone('a');
    await store.removeAssignment('a');
    expect(store.assignments(), isEmpty);
    expect(store.allAssignments().single.isDeleted, isTrue);
    await store.restoreAssignment(original);
    expect(store.assignments().single.id, original.id);
    expect(store.assignments().single.done, isFalse);
  });

  test(
    'rejects wrong passwords after logout and restores the right account',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AuthCache.register('Alice', 'password-123'), isNull);
      await AuthCache.clear();
      expect(await AuthCache.load(), isNull);
      expect(await AuthCache.signIn('Alice', 'wrong-password'), isNotNull);
      expect(await AuthCache.load(), isNull);
      expect(await AuthCache.register('ALICE', 'another-password'), isNotNull);
      expect(await AuthCache.signIn('alice', 'password-123'), isNull);
      expect(await AuthCache.load(), ('alice', 'password-123'));
    },
  );

  test('legacy short password can sign back in after safe migration', () async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'old',
      AuthCache.passwordKey: '1234',
    });
    await AuthCache.load();
    await AuthCache.clear();
    expect(await AuthCache.signIn('old', '1234'), isNull);
    expect(await AuthCache.register('new', '1234'), isNotNull);
  });

  test(
    'tokens are bound to the account and backend; logout keeps the binding',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AuthCache.saveToken(
        'secret',
        baseUrl: 'https://a.example',
        userName: 'Alice',
      );
      expect(
        await AuthCache.readToken(
          baseUrl: 'https://b.example',
          userName: 'Alice',
        ),
        isEmpty,
      );
      expect(
        await AuthCache.readToken(
          baseUrl: 'https://a.example',
          userName: 'Bob',
        ),
        isEmpty,
      );
      expect(
        await AuthCache.readToken(
          baseUrl: 'https://a.example',
          userName: 'alice',
        ),
        'secret',
      );
      await AuthCache.clear();
      expect(
        await AuthCache.readToken(
          baseUrl: 'https://a.example',
          userName: 'Alice',
        ),
        isEmpty,
      );
      expect(await AuthCache.linkedBackend('Alice'), 'https://a.example');
    },
  );

  test('corrupt local data is preserved and never silently replaced', () async {
    SharedPreferences.setMockInitialValues({
      TaskStore.tasksKeyFor('Alice'): '{broken',
    });
    final store = await TaskStore.load(userName: 'Alice');
    expect(store.tasks, throwsFormatException);
    expect(
      (await SharedPreferences.getInstance()).getString(
        TaskStore.tasksKeyFor('Alice'),
      ),
      '{broken',
    );
  });

  test(
    'unowned legacy data is not adopted by a newly created account',
    () async {
      SharedPreferences.setMockInitialValues({TaskStore.tasksKey: '[]'});
      await AuthCache.load();
      await AuthCache.register('Alice', 'password-123');
      await TaskStore.load(userName: 'Alice');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(TaskStore.tasksKeyFor('Alice')), isFalse);
      expect(prefs.getString(TaskStore.tasksKey), '[]');
    },
  );

  test(
    'public backends require HTTPS and origins cannot carry credentials',
    () {
      expect(
        () => BackendConfig.validateUrl('http://public.example'),
        throwsFormatException,
      );
      expect(
        () => BackendConfig.validateUrl('https://user:pass@example.com'),
        throwsFormatException,
      );
      expect(
        () => BackendConfig.validateUrl('https://example.com/path'),
        throwsFormatException,
      );
      expect(
        () => BackendConfig.validateUrl('http://192.168.1.5:3002'),
        throwsFormatException,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        expect(
          () => BackendConfig.validateUrl('http://127.0.0.1:3002'),
          throwsFormatException,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(BackendConfig.validateUrl('http://127.0.0.1:3002').port, 3002);
        expect(BackendConfig.validateUrl('http://[::1]:3002').port, 3002);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(
        BackendConfig.validateUrl('https://public.example').scheme,
        'https',
      );
    },
  );

  test('keeps backend URL empty until the user chooses to sync', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await BackendConfig.loadUrl(), isEmpty);
  });

  test(
    'queues the original backend token for retry before local sign-out',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AuthCache.saveToken(
        'server-session',
        baseUrl: 'https://old.example',
        userName: 'Alice',
      );
      await BackendConfig.saveUrl('https://new.example');

      await AuthCache.queueCurrentTokenForRevocation('Alice');
      await AuthCache.clear();

      final pending = await AuthCache.pendingRevocations();
      expect(pending.single['baseUrl'], 'https://old.example');
      expect(pending.single['token'], 'server-session');
      await AuthCache.completeRevocation('server-session');
      expect(await AuthCache.pendingRevocations(), isEmpty);
    },
  );

  test('deduplicates repeated task titles in the work library', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TaskStore.load();
    final now = DateTime.utc(2026, 8, 14);

    await store.saveTasks([]);
    await store.addTask(
      TaskItem(
        id: '1',
        title: '  Học Flutter ',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await store.addTask(
      TaskItem(id: '2', title: 'học   flutter', createdAt: now, updatedAt: now),
    );

    expect(store.tasks(), hasLength(1));
  });

  test('snoozes an assignment to a future reminder time', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TaskStore.load();
    final now = DateTime.now();

    await store.saveAssignments([
      TaskAssignment(
        id: 'assign-1',
        taskId: 'task-1',
        date: dateOnly(now),
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    await store.snoozeAssignment('assign-1', const Duration(minutes: 15));

    final assignment = store.assignments().single;
    expect(assignment.done, isFalse);
    expect(assignment.updatedAt.isAfter(now), isTrue);
    expect(assignment.reminderHour, inInclusiveRange(0, 23));
    expect(assignment.reminderMinute, inInclusiveRange(0, 59));
  });

  test('migrates a plaintext password out of SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'Legacy User',
      AuthCache.passwordKey: 'legacy-password',
    });

    expect(await AuthCache.load(), ('Legacy User', 'legacy-password'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AuthCache.passwordKey), isFalse);
  });

  test(
    'cleans legacy plaintext copies even after an interrupted migration',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AuthCache.register('Alice', 'secure-password');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AuthCache.passwordKey, 'stale-plaintext-password');
      await prefs.setString(
        'task-reminder-auth-password-fallback',
        'fallback-password',
      );
      await prefs.setString(
        'task-reminder-auth-token-fallback',
        'fallback-token',
      );
      expect(await AuthCache.load(), ('Alice', 'secure-password'));
      for (final key in [
        AuthCache.passwordKey,
        'task-reminder-auth-password-fallback',
        'task-reminder-auth-token-fallback',
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      await AuthCache.clear();
      await prefs.setString(AuthCache.passwordKey, 'orphan-password');
      expect(await AuthCache.load(), isNull);
      expect(prefs.containsKey(AuthCache.passwordKey), isFalse);
    },
  );

  test(
    'revocation queue retains recent sessions when its limit is reached',
    () async {
      SharedPreferences.setMockInitialValues({});
      for (var index = 0; index < 12; index++) {
        await AuthCache.saveToken(
          'token-$index',
          baseUrl: 'https://tasks.example',
          userName: 'Alice',
        );
        await AuthCache.queueCurrentTokenForRevocation('Alice');
      }
      final pending = await AuthCache.pendingRevocations();
      expect(pending, hasLength(10));
      expect(pending.first['token'], 'token-2');
      expect(pending.last['token'], 'token-11');
    },
  );

  test('isolates local tasks by account', () async {
    SharedPreferences.setMockInitialValues({});
    final alice = await TaskStore.load(userName: 'Alice');
    final bob = await TaskStore.load(userName: 'Bob');
    final now = DateTime.utc(2026, 9, 22);

    await alice.saveTasks([
      TaskItem(
        id: 'alice-task',
        title: 'Alice only',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    await bob.saveTasks([
      TaskItem(
        id: 'bob-task',
        title: 'Bob only',
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    expect(alice.tasks().single.title, 'Alice only');
    expect(bob.tasks().single.title, 'Bob only');
  });

  test(
    'keeps deletion tombstones for sync without showing deleted tasks',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await TaskStore.load(userName: 'Alice');
      final now = DateTime.utc(2026, 9, 22);
      await store.saveTasks([
        TaskItem(
          id: 'task-1',
          title: 'Delete me',
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await store.removeTask('task-1');

      expect(store.tasks(), isEmpty);
      expect(store.allTasks().single.isDeleted, isTrue);
    },
  );
}
