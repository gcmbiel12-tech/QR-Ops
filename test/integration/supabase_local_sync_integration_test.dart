import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_ops/data/supabase_qr_auth_gateway.dart';

void main() {
  final url = Platform.environment['QR_OPS_LOCAL_SUPABASE_URL'];
  final key = Platform.environment['QR_OPS_LOCAL_SUPABASE_KEY'];
  final configured = url != null && url.isNotEmpty && key != null && key.isNotEmpty;

  test(
    'real local Supabase auth, RPC idempotency, tombstones and RLS isolation',
    () async {
      final clientA = SupabaseClient(
        url!,
        key!,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      final clientB = SupabaseClient(
        url,
        key,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      addTearDown(() async {
        await clientA.dispose();
        await clientB.dispose();
      });

      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final emailA = 'qr-ops-sync-a-$suffix@example.invalid';
      final emailB = 'qr-ops-sync-b-$suffix@example.invalid';
      final passwordA = 'QrOps-Test-$suffix-Aa9!';
      final passwordB = 'QrOps-Test-$suffix-Bb8!';

      final authA = SupabaseQrAuthGateway(clientA);
      final authB = SupabaseQrAuthGateway(clientB);
      await authA.signUp(email: emailA, password: passwordA);
      await authB.signUp(email: emailB, password: passwordB);
      await authA.signIn(email: emailA, password: passwordA);
      await authB.signIn(email: emailB, password: passwordB);
      expect(authA.currentUser?.email, emailA);
      expect(authB.currentUser?.email, emailB);

      final sessionBeforeRefresh = clientA.auth.currentSession;
      final refreshed = await clientA.auth.refreshSession();
      expect(sessionBeforeRefresh, isNotNull);
      expect(refreshed.session, isNotNull);
      await authA.sendPasswordReset(email: emailA);

      final recordId = ('a1000000-0000-4000-8000-$suffix').substring(0, 36);
      final keyCreate = 'api-create-$suffix';
      final create = {
        'idempotency_key': keyCreate,
        'record_id': recordId,
        'type': 'upsert',
        'base_revision': null,
        'record': {
          'id': recordId,
          'operation_type': 'create',
          'symbology': 'qr',
          'content_type': 'text',
          'content': 'api integration',
          'name': '',
          'description': '',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      };
      final first = await clientA.rpc(
        'apply_qr_sync_batch',
        params: {'p_mutations': [create]},
      ) as List;
      expect(first.single['status'], 'applied');

      final duplicate = await clientA.rpc(
        'apply_qr_sync_batch',
        params: {'p_mutations': [create]},
      ) as List;
      expect(duplicate.single['status'], 'already_applied');
      final ownedRows = await clientA
          .from('qr_records')
          .select('id, revision')
          .eq('id', recordId);
      expect(ownedRows, hasLength(1));

      final visibleToB = await clientB
          .from('qr_records')
          .select('id')
          .eq('id', recordId);
      expect(visibleToB, isEmpty);

      await expectLater(
        clientB.from('qr_records').insert({
          'id': ('b2000000-0000-4000-8000-$suffix').substring(0, 36),
          'author_id': authA.currentUser!.id,
          'operation_type': 'create',
          'symbology': 'qr',
          'content_type': 'text',
          'content': 'spoofed owner',
        }),
        throwsA(isA<PostgrestException>()),
      );

      final delete = await clientA.rpc(
        'apply_qr_sync_batch',
        params: {
          'p_mutations': [
            {
              'idempotency_key': 'api-delete-$suffix',
              'record_id': recordId,
              'type': 'delete',
              'base_revision': 1,
            },
          ],
        },
      ) as List;
      expect(delete.single['status'], 'applied');

      final staleUpsert = await clientA.rpc(
        'apply_qr_sync_batch',
        params: {
          'p_mutations': [
            {
              'idempotency_key': 'api-stale-upsert-$suffix',
              'record_id': recordId,
              'type': 'upsert',
              'base_revision': null,
              'record': {
                'id': recordId,
                'operation_type': 'create',
                'symbology': 'qr',
                'content_type': 'text',
                'content': 'must not resurrect',
                'name': '',
                'description': '',
              },
            },
          ],
        },
      ) as List;
      expect(staleUpsert.single['status'], 'conflict');
      final staleRetry = await clientA.rpc(
        'apply_qr_sync_batch',
        params: {
          'p_mutations': [
            {
              'idempotency_key': 'api-stale-upsert-$suffix',
              'record_id': recordId,
              'type': 'upsert',
              'base_revision': null,
              'record': {
                'id': recordId,
                'operation_type': 'create',
                'symbology': 'qr',
                'content_type': 'text',
                'content': 'must not resurrect',
                'name': '',
                'description': '',
              },
            },
          ],
        },
      ) as List;
      expect(staleRetry.single['status'], 'conflict');
      expect(
        await clientA.from('qr_records').select('id').eq('id', recordId),
        isEmpty,
      );

      await authA.signOut();
      await authB.signOut();
      expect(authA.currentUser, isNull);
      expect(authB.currentUser, isNull);
    },
    skip: configured ? false : 'Set QR_OPS_LOCAL_SUPABASE_URL and QR_OPS_LOCAL_SUPABASE_KEY for local integration testing.',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
