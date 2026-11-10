import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../services/gemini_service.dart';
import 'state_views.dart';

enum _Source { camera, gallery, pdf }

/// Universal document input: capture with the camera, pick an image or pick
/// a PDF. The file is read into memory for Gemini and never uploaded or
/// stored, so personal financial documents do not persist anywhere.
/// Returns null if the user cancels or the file is unusable.
Future<AiDocument?> pickDocument(
  BuildContext context, {
  String title = 'Add a document',
}) async {
  final source = await showModalBottomSheet<_Source>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.xxs),
            Text(
              'Read on your device by Gemini. Nothing is uploaded or stored.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                _SourceTile(
                  Icons.photo_camera_outlined,
                  'Camera',
                  () => Navigator.pop(context, _Source.camera),
                ),
                const SizedBox(width: Space.sm),
                _SourceTile(
                  Icons.photo_library_outlined,
                  'Photo',
                  () => Navigator.pop(context, _Source.gallery),
                ),
                const SizedBox(width: Space.sm),
                _SourceTile(
                  Icons.picture_as_pdf_outlined,
                  'PDF',
                  () => Navigator.pop(context, _Source.pdf),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  try {
    final AiDocument? doc = switch (source) {
      _Source.pdf => await _pickPdf(),
      _ => await _pickImage(
        source == _Source.camera ? ImageSource.camera : ImageSource.gallery,
      ),
    };
    if (doc == null) return null;
    if (doc.bytes.lengthInBytes > GeminiService.maxDocumentBytes) {
      if (context.mounted) {
        showMessage(context, 'Documents must be smaller than 7 MB.');
      }
      return null;
    }
    if (!AiDocument.supportedMimeTypes.contains(doc.mimeType)) {
      if (context.mounted) {
        showMessage(context, 'Choose a JPEG, PNG, WebP, HEIC image or a PDF.');
      }
      return null;
    }
    return doc;
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        source == _Source.camera
            ? 'Could not open the camera. Allow camera access for FLOWMINT in Settings.'
            : 'Could not open that file. Check app permissions and try again.',
      );
    }
    return null;
  }
}

Future<AiDocument?> _pickImage(ImageSource source) async {
  // The system camera provides capture, retake and confirm.
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2200,
    imageQuality: 85,
  );
  if (file == null) return null;
  final name = file.name.toLowerCase();
  final mime =
      file.mimeType ??
      (name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
          ? 'image/webp'
          : name.endsWith('.heic') || name.endsWith('.heif')
          ? 'image/heic'
          : 'image/jpeg');
  return AiDocument(await file.readAsBytes(), mime, name: file.name);
}

Future<AiDocument?> _pickPdf() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  // Validate the PDF signature, not just the extension.
  final isPdf =
      bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
  if (!isPdf) throw const FormatException('Not a PDF');
  return AiDocument(bytes, 'application/pdf', name: file.name);
}

class _SourceTile extends StatelessWidget {
  const _SourceTile(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Column(
              children: [
                Icon(icon, color: AppColors.brand, size: 26),
                const SizedBox(height: Space.xs),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact preview of a selected document with replace / remove actions.
class DocumentChip extends StatelessWidget {
  const DocumentChip({
    super.key,
    required this.document,
    this.onReplace,
    this.onRemove,
  });

  final AiDocument document;
  final VoidCallback? onReplace;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kb = (document.bytes.lengthInBytes / 1024).round();
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: document.isPdf
                ? Container(
                    width: 44,
                    height: 44,
                    color: AppColors.danger.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: AppColors.danger,
                    ),
                  )
                : Image.memory(
                    document.bytes,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.name ?? (document.isPdf ? 'Document.pdf' : 'Photo'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall,
                ),
                Text(
                  '${document.isPdf ? 'PDF' : 'Image'} · ${kb < 1024 ? '$kb KB' : '${(kb / 1024).toStringAsFixed(1)} MB'}',
                  style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (onReplace != null)
            IconButton(
              tooltip: 'Replace',
              onPressed: onReplace,
              icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}
