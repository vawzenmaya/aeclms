// lib/features/documents/presentation/documents_section.dart

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/documents_repository.dart';

const _docTypes = {
  'application_form': 'Application Form',
  'id_copy': 'ID Copy',
  'payslip': 'Payslip',
  'other': 'Other',
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final docs = await widget.repository.fetchDocuments(widget.loanId);
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _loading = false;
    });
  }

  Future<void> _pickAndUpload() async {
    final docType = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('What kind of document?'),
        children: _docTypes.entries
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, e.key),
                  child: Text(e.value),
                ))
            .toList(),
      ),
    );
    if (docType == null) return;

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
    final url = await widget.repository.getSignedUrl(doc.storagePath);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Documents', style: Theme.of(context).textTheme.titleMedium),
                if (widget.canUpload)
                  TextButton.icon(
                    onPressed: _uploading ? null : _pickAndUpload,
                    icon: _uploading
                        ? const SizedBox(
                            height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Add'),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFD9534F))),
              ),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_docs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No documents uploaded yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
              )
            else
              ..._docs.map((d) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(_docTypes[d.docType] ?? d.docType),
                    subtitle: Text(d.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => _openDocument(d),
                  )),
          ],
        ),
      ),
    );
  }
}