import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// Raised when a product could not be put on or taken off a customer.
class CustomerProductException implements Exception {
  const CustomerProductException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The hand-picked product on a customer — the `customer_collections` row
/// the chat list's 🛍 chip and the Products filter both read.
///
/// One row per (owner, phone): assigning replaces whatever was there, and
/// removing clears it. Afterwards the chip may still show a product — with
/// the collection gone it falls back to the one mapped from the ad the chat
/// came in on, which is what the web app does too.
class CustomerProductsRepository {
  const CustomerProductsRepository();

  Future<void> assign({
    required String chatOwnerId,
    required String normalisedPhone,
    required String productId,
    required String productTitle,
  }) async {
    if (normalisedPhone.isEmpty) {
      throw const CustomerProductException('This chat has no phone number.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await db.from(Db.customerCollections).upsert(
        <String, dynamic>{
          'user_id': chatOwnerId,
          'phone': normalisedPhone,
          'product_id': productId,
          'product_title': productTitle,
          'assigned_at': now,
          'updated_at': now,
        },
        onConflict: 'user_id,phone',
      );
    } on PostgrestException catch (error) {
      throw CustomerProductException(
        'Could not assign the product: ${error.message}',
      );
    }
  }

  Future<void> remove({
    required String chatOwnerId,
    required String normalisedPhone,
  }) async {
    if (normalisedPhone.isEmpty) {
      throw const CustomerProductException('This chat has no phone number.');
    }
    try {
      await db
          .from(Db.customerCollections)
          .delete()
          .eq('user_id', chatOwnerId)
          .eq('phone', normalisedPhone);
    } on PostgrestException catch (error) {
      throw CustomerProductException(
        'Could not remove the product: ${error.message}',
      );
    }
  }
}
