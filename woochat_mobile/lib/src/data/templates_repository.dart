import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// Raised when a template could not be created or a parameter saved.
class TemplateException implements Exception {
  const TemplateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A reusable `{{n}}` placeholder name from the existing `template_parameters`
/// table — the "saved parameters" the web app offers while composing.
class SavedParameter {
  const SavedParameter({required this.id, required this.name});

  final String id;
  final String name;
}

/// What the Create Template sheet collects. Mirrors the web app's dialog
/// field for field.
class TemplateDraft {
  const TemplateDraft({
    required this.name,
    required this.language,
    required this.category,
    required this.bodyText,
    required this.headerFormat,
    required this.parameters,
  });

  /// Lowercase letters, digits and underscores — Meta's own rule.
  final String name;

  /// A Meta language code such as `en_US`.
  final String language;

  /// `MARKETING`, `UTILITY` or `AUTHENTICATION`.
  final String category;
  final String bodyText;

  /// `NONE`, `IMAGE`, `VIDEO` or `DOCUMENT`.
  final String headerFormat;

  /// The parameter names in `{{1}}`, `{{2}}`… order.
  final List<String> parameters;

  static final RegExp namePattern = RegExp(r'^[a-z0-9_]+$');
}

/// An approved WhatsApp message template.
class MessageTemplate {
  const MessageTemplate({
    required this.id,
    required this.name,
    this.language,
    this.body,
  });

  final String id;
  final String name;
  final String? language;
  final String? body;

  factory MessageTemplate.fromMap(Map<String, dynamic> map) => MessageTemplate(
        id: map['id'].toString(),
        name: (map['name'] as String?)?.trim() ?? '',
        language: map['language'] as String?,
        body: map['body_text'] as String? ?? map['body'] as String?,
      );
}

/// Reads the existing `whatsapp_templates` table.
///
/// Only APPROVED templates can be sent, so only those are listed — the same
/// filter the web app uses.
class TemplatesRepository {
  const TemplatesRepository();

  Future<List<MessageTemplate>> fetchApproved() async {
    final rows = await db
        .from(Db.whatsappTemplates)
        .select()
        .eq('status', 'APPROVED')
        .order('created_at', ascending: false) as List<dynamic>;

    return rows
        .whereType<Map<String, dynamic>>()
        .map(MessageTemplate.fromMap)
        .where((template) => template.name.isNotEmpty)
        .toList();
  }

  /// The team's saved parameter names, oldest first.
  Future<List<SavedParameter>> fetchSavedParameters() async {
    try {
      final rows = await db
          .from(Db.templateParameters)
          .select('id, name')
          .order('created_at', ascending: true) as List<dynamic>;
      return rows
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => SavedParameter(
              id: row['id'].toString(),
              name: (row['name'] as String? ?? '').trim(),
            ),
          )
          .where((parameter) => parameter.name.isNotEmpty)
          .toList();
    } on PostgrestException {
      // The sheet still works without the saved list — parameters can be
      // typed fresh.
      return const <SavedParameter>[];
    }
  }

  /// Saves a parameter name for reuse across templates.
  Future<SavedParameter> saveParameter({
    required String name,
    required String createdBy,
  }) async {
    try {
      final row = await db
          .from(Db.templateParameters)
          .insert(<String, dynamic>{'name': name.trim(), 'created_by': createdBy})
          .select('id, name')
          .single();
      return SavedParameter(
        id: row['id'].toString(),
        name: row['name'] as String,
      );
    } on PostgrestException catch (error) {
      throw TemplateException('Could not save the parameter: ${error.message}');
    }
  }

  /// Submits a new template through the existing `whatsapp-template` edge
  /// function, which sends it to Meta for every active WhatsApp account in
  /// the admin panel — the same path the web app's "Create for My Users"
  /// button takes.
  Future<void> createTemplate(TemplateDraft draft) async {
    try {
      final response = await db.functions.invoke(
        Db.whatsappTemplateFn,
        body: <String, dynamic>{
          'action': 'create',
          'name': draft.name,
          'language': draft.language,
          'category': draft.category,
          'bodyText': draft.bodyText,
          'headerFormat': draft.headerFormat,
          'parameters': draft.parameters,
        },
      );
      if (response.status >= 400) {
        throw TemplateException(
          _reasonFor(response.data) ??
              'whatsapp-template returned HTTP ${response.status}.',
        );
      }
    } on FunctionException catch (error) {
      throw TemplateException(
        _reasonFor(error.details) ??
            'whatsapp-template rejected the template (${error.reasonPhrase}).',
      );
    }
  }

  static String? _reasonFor(Object? data) {
    if (data is! Map) return null;
    final error = data['error'] ?? data['message'];
    return error is String && error.isNotEmpty ? error : null;
  }
}
