import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/shared/widgets/toast.dart';

/// Ids deleted in this session. Lists filter these out immediately so a
/// swiped row never flickers back before the database stream catches up.
final pendingDeletionsProvider = NotifierProvider<PendingDeletions, Set<int>>(PendingDeletions.new);

class PendingDeletions extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void add(int id) => state = {...state, id};
  void remove(int id) => state = {...state}..remove(id);
}

/// Deletes a transaction and offers "Undo" for a few seconds.
Future<void> deleteTxnWithUndo(
  BuildContext context,
  WidgetRef ref,
  Txn txn, {
  bool aboveNavBar = true,
}) async {
  // Capture long-lived objects: the calling widget may be gone by the time
  // "Undo" is tapped.
  final repo = ref.read(txnRepositoryProvider);
  final pending = ref.read(pendingDeletionsProvider.notifier);
  pending.add(txn.id);
  Haptics.medium();
  final deletion = repo.delete(txn.id);
  AppToast.show(
    context,
    'Transaction deleted',
    icon: Icons.delete_outline_rounded,
    actionLabel: 'Undo',
    aboveNavBar: aboveNavBar,
    onAction: () async {
      await deletion;
      await repo.restore(txn);
      pending.remove(txn.id);
    },
  );
  await deletion;
}

/// Copies a transaction to today.
Future<int> duplicateTxn(WidgetRef ref, Txn txn) {
  final now = DateTime.now();
  return ref
      .read(txnRepositoryProvider)
      .add(
        kind: txn.kind,
        amount: txn.amount,
        accountId: txn.accountId,
        toAccountId: txn.toAccountId,
        categoryId: txn.categoryId,
        note: txn.note,
        date: now,
      );
}
