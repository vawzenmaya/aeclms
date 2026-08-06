// lib/features/documents/data/documents_repository.dart

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class LoanDocument {
  final String id;
  final String loanId;
  final String docType;
  final String storagePath;
  final DateTime uploadedAt;

  LoanDocument({
    required this.id,
    required this.loanId,
    required this.docType,
    required this.storagePath,
    required this.uploadedAt,
  });

  factory LoanDocument.fromMap(Map<String, dynamic> map) => LoanDocument(
        id: map['id'] as String,
        loanId: map['loan_id'] as String,
        docType: map['doc_type'] as String,
        storagePath: map['storage_path'] as String,
        uploadedAt: DateTime.parse(map['uploaded_at'] as String),
      );

  String get fileName => storagePath.split('/').last;
}

class DocumentsRepository {
  DocumentsRepository(this._client);
  final SupabaseClient _client;
  static const _bucket = 'loan-documents';

  Future<List<LoanDocument>> fetchDocuments(String loanId) async {
    final rows = await _client
        .from('loan_documents')
        .select()
        .eq('loan_id', loanId)
        .order('uploaded_at', ascending: false);
    return (rows as List).map((r) => LoanDocument.fromMap(r)).toList();
  }

  Future<void> upload({
    required String loanId,
    required String docType,
    required String fileName,
    required Uint8List bytes,
    required String uploadedBy,
  }) async {
    final path = '$loanId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await _client.storage.from(_bucket).uploadBinary(path, bytes);
    await _client.from('loan_documents').insert({
      'loan_id': loanId,
      'doc_type': docType,
      'storage_path': path,
      'uploaded_by': uploadedBy,
    });
  }

  /// Private bucket -> need a short-lived signed URL to view/download.
  Future<String> getSignedUrl(String storagePath, {int expiresInSeconds = 3600}) async {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, expiresInSeconds);
  }

  Future<void> delete(LoanDocument doc) async {
    // 1. Remove the actual file from the Supabase Storage bucket
    await _client.storage.from(_bucket).remove([doc.storagePath]);
    
    // 2. Remove the metadata row from the loan_documents table
    // We use .select('id') to force Supabase to return the deleted row.
    final response = await _client
        .from('loan_documents')
        .delete()
        .eq('id', doc.id)
        .select('id');
        
    // 3. If the response is empty, RLS silently blocked the table deletion
    if (response.isEmpty) {
      throw Exception(
        'Could not remove document record. It may be locked by security policies '
        'if the application has already been submitted.'
      );
    }
  }
}