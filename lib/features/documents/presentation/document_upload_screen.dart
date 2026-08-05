// lib/features/documents/presentation/document_upload_screen.dart
//
// Sits between "application saved" and "loan tracking". The applicant lands
// here right after saving the form, uploads at least one supporting
// document, then explicitly submits from here — only then do they move on
// to the loan detail/tracking screen.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/custom_loader.dart';
import '../../auth/data/auth_service.dart';
import '../../loans/data/loan_repository.dart';
import '../../loans/presentation/loan_detail_screen.dart';
import '../data/documents_repository.dart';
import 'documents_section.dart';

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({
    super.key,
    required this.loanRepository,
    required this.profile,
    required this.loanId,
    required this.hasGuarantor,
  });

  final LoanRepository loanRepository;
  final Profile profile;
  final String loanId;
  final bool hasGuarantor;

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  late final DocumentsRepository _documentsRepo = DocumentsRepository(Supabase.instance.client);
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final docs = await _documentsRepo.fetchDocuments(widget.loanId);
    if (docs.isEmpty) {
      setState(() => _error = 'Please upload at least one supporting document before submitting.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.loanRepository.submit(widget.loanId, hasGuarantor: widget.hasGuarantor);
      if (!mounted) return;
      _goToDetail();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goToDetail() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoanDetailScreen(
          repository: widget.loanRepository,
          profile: widget.profile,
          loanId: widget.loanId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Documents', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _submitting ? null : _goToDetail,
            child: const Text('Finish later'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your application has been saved. Upload at least one supporting '
                            'document (ID, payslip, etc.) below, then submit for review.',
                            style: TextStyle(color: scheme.primary, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: DocumentsSection(
                      repository: _documentsRepo,
                      loanId: widget.loanId,
                      uploadedBy: widget.profile.id,
                      canUpload: true,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -5)),
                ],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFD9534F))),
                    ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const CustomLoader(size: 20, color: Colors.white)
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(_submitting ? '' : 'Submit Application'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}