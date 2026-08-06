// lib/features/documents/presentation/documents_section.dart

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/custom_loader.dart';
import '../data/documents_repository.dart';

const _docTypes = {
  'id_copy': 'ID Copy',
  'valid_contract': 'Valid Contract',
  'payslip': 'Most Recent Payslip',
  'other': 'Other Document',
};

class DocumentsSection extends StatefulWidget {
  const DocumentsSection({
    super.key,
    required this.repository,
    required this.loanId,
    required this.uploadedBy,
    required this.canUpload,
  });

  final DocumentsRepository repository;
  final String loanId;
  final String uploadedBy;
  final bool canUpload;

  @override
  State<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends State<DocumentsSection> {
  List<LoanDocument> _docs = [];
  bool _loading = true;
  bool _uploading = false;
  String? _deletingId; // Tracks which document is currently being deleted
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs = await widget.repository.fetchDocuments(widget.loanId);
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load documents.';
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    // 1. Filter out already uploaded document types (except 'other')
    final uploadedTypes = _docs.map((d) => d.docType).toSet();
    final availableTypes = _docTypes.entries
        .where((e) => e.key == 'other' || !uploadedTypes.contains(e.key))
        .toList();

    if (availableTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All required documents have been uploaded.')),
      );
      return;
    }

    // 2. Show premium selection dialog
    final docType = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DocumentTypeSelector(availableTypes: availableTypes),
    );
    
    if (docType == null) return;

    // 3. Pick the file
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    
    if (file.bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }

    // 4. Upload
    setState(() {
      _uploading = true;
      _error = null;
    });
    
    try {
      await widget.repository.upload(
        loanId: widget.loanId,
        docType: docType,
        fileName: file.name,
        bytes: file.bytes!,
        uploadedBy: widget.uploadedBy,
      );
      await _load();
    } catch (e) {
      setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openDocument(LoanDocument doc) async {
    try {
      final url = await widget.repository.getSignedUrl(doc.storagePath);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        setState(() => _error = 'Could not open this document.');
      }
    } catch (e) {
      setState(() => _error = 'Error opening document: $e');
    }
  }

  Future<void> _deleteDocument(LoanDocument doc) async {
    final scheme = Theme.of(context).colorScheme;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD9534F)),
            ),
            const SizedBox(width: 12),
            const Text('Delete File?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${doc.fileName}"? You will need to upload it again if it is required.',
          style: const TextStyle(height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9534F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _deletingId = doc.id;
        _error = null;
      });
      
      try {
        await widget.repository.delete(doc);
        await _load();
      } catch (e) {
        setState(() => _error = 'Error deleting file: $e');
      } finally {
        if (mounted) setState(() => _deletingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: Colors.transparent, // Inherits styling from the parent container
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Attached Files', 
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (widget.canUpload)
                FilledButton.tonalIcon(
                  onPressed: _uploading ? null : _pickAndUpload,
                  icon: _uploading
                      ? CustomLoader(size: 16, color: scheme.primary)
                      : const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Upload', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD9534F).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFD9534F), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFD9534F), fontSize: 13))),
                ],
              ),
            ),
            
          const SizedBox(height: 20),
          
          // Content Area
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CustomLoader(size: 40, color: scheme.primary)),
            )
          else if (_docs.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withOpacity(0.5), style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.upload_file_rounded, size: 48, color: scheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(
                    'No documents uploaded yet.',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _docs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final d = _docs[index];
                final isDeleting = _deletingId == d.id;
                final isPdf = d.fileName.toLowerCase().endsWith('.pdf');
                
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      // File Icon
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isPdf ? const Color(0xFFD9534F).withOpacity(0.1) : scheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                          color: isPdf ? const Color(0xFFD9534F) : scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // File Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _docTypes[d.docType] ?? d.docType,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              d.fileName,
                              style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      
                      // Actions (View & Delete)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: isDeleting ? null : () => _openDocument(d),
                            icon: const Icon(Icons.visibility_outlined),
                            color: scheme.primary,
                            tooltip: 'View Document',
                          ),
                          if (widget.canUpload)
                            IconButton(
                              onPressed: isDeleting ? null : () => _deleteDocument(d),
                              icon: isDeleting 
                                  ? const CustomLoader(size: 18, color: Color(0xFFD9534F))
                                  : const Icon(Icons.delete_outline_rounded),
                              color: const Color(0xFFD9534F),
                              tooltip: 'Delete Document',
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// Custom Bottom Sheet for selecting document type
class _DocumentTypeSelector extends StatelessWidget {
  final List<MapEntry<String, String>> availableTypes;

  const _DocumentTypeSelector({required this.availableTypes});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('Select Document Type', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('What kind of file are you uploading?', style: TextStyle(color: scheme.onSurface.withOpacity(0.6))),
            const SizedBox(height: 24),
            
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: availableTypes.length,
              itemBuilder: (context, index) {
                final docType = availableTypes[index];
                
                IconData getIconForType(String key) {
                  switch (key) {
                    case 'id_copy': return Icons.badge_outlined;
                    case 'valid_contract': return Icons.gavel_rounded;
                    case 'payslip': return Icons.receipt_long_rounded;
                    default: return Icons.description_outlined;
                  }
                }

                return InkWell(
                  onTap: () => Navigator.pop(context, docType.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(0.4), shape: BoxShape.circle),
                          child: Icon(getIconForType(docType.key), color: scheme.onSurface),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Text(docType.value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                        Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withOpacity(0.3)),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}