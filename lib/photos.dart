import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'photo_journal.dart';

const _muted = Color(0xFFA0B4AA);
const _surface = Color(0xFF1B2725);

class PhotosPage extends StatefulWidget {
  final PhotoJournal? journal;
  const PhotosPage({super.key, this.journal});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  PhotoJournal? journal;
  DateTime selected = DateTime(DateTime.now().year, DateTime.now().month);
  List<String> months = [];
  String? compareBefore, compareAfter;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final opened = widget.journal ?? await PhotoJournal.open();
      final found = await opened.months();
      if (!mounted) return;
      setState(() {
        journal = opened;
        months = found;
        syncComparison();
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Không mở được ảnh đã lưu.');
    }
  }

  void syncComparison() {
    if (months.length < 2) {
      compareBefore = null;
      compareAfter = null;
      return;
    }
    if (!months.contains(compareAfter)) compareAfter = months.first;
    if (!months.contains(compareBefore) || compareBefore == compareAfter) {
      compareBefore = months.firstWhere((m) => m != compareAfter);
    }
  }

  String get selectedMonth => PhotoJournal.monthKey(selected);
  String label(String month) =>
      'Tháng ${month.substring(5)}/${month.substring(0, 4)}';

  bool get hasCurrent => months.contains(selectedMonth);

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  void moveMonth(int offset) {
    setState(() => selected = DateTime(selected.year, selected.month + offset));
  }

  Future<void> capture(ImageSource source) async {
    if (journal == null || busy) return;
    final month = selectedMonth;
    setState(() => busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PhotoJournal.pendingMonthKey, month);
      final picked = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 90,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (picked == null) return;
      if (!mounted) return;
      if (months.contains(month)) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Thay ảnh tháng này?'),
            content: Text(
              'Ảnh đã lưu cho ${label(month)} sẽ được thay bằng ảnh mới.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Giữ ảnh cũ'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Thay ảnh'),
              ),
            ],
          ),
        );
        if (replace != true) return;
      }
      final target = journal!.fileFor(month);
      await journal!.save(month, picked.path);
      await FileImage(target).evict();
      final found = await journal!.months();
      if (!mounted) return;
      setState(() {
        months = found;
        error = null;
        syncComparison();
      });
      message('Đã lưu ảnh ${label(month)}');
    } catch (_) {
      message('Chưa lưu được ảnh. Hãy thử lại.');
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PhotoJournal.pendingMonthKey);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteCurrent() async {
    if (journal == null || !hasCurrent) return;
    final month = selectedMonth;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa ảnh tháng này?'),
        content: Text('Ảnh ${label(month)} sẽ bị xóa khỏi ứng dụng.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa ảnh'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FileImage(journal!.fileFor(month)).evict();
      await journal!.remove(month);
      final found = await journal!.months();
      if (!mounted) return;
      setState(() {
        months = found;
        syncComparison();
      });
      message('Đã xóa ảnh ${label(month)}');
    } catch (_) {
      message('Chưa xóa được ảnh. Hãy thử lại.');
    }
  }

  Future<void> exportCurrent() async {
    if (journal == null || !hasCurrent) return;
    try {
      final bytes = await journal!.fileFor(selectedMonth).readAsBytes();
      final png = PhotoJournal.isPng(bytes);
      final extension = png ? 'png' : 'jpg';
      final result = await FilePicker.saveFile(
        dialogTitle: 'Lưu ảnh ra máy',
        fileName: 'track-ta-$selectedMonth.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        mimeType: png ? 'image/png' : 'image/jpeg',
        bytes: bytes,
      );
      if (result != null) message('Đã lưu ảnh ra máy');
    } catch (_) {
      message('Chưa xuất được ảnh. Hãy thử chọn thư mục khác.');
    }
  }

  void openImage(String month) {
    if (journal == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.file(
                journal!.fileFor(month),
                width: double.infinity,
                height: MediaQuery.sizeOf(context).height * .8,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: 'Đóng ảnh',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget photoFrame(String? month, {double aspectRatio = 3 / 4}) => AspectRatio(
    aspectRatio: aspectRatio,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: month == null || !months.contains(month)
          ? Container(
              color: _surface,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: _muted, size: 42),
                  SizedBox(height: 10),
                  Text('Chưa có ảnh', style: TextStyle(color: _muted)),
                ],
              ),
            )
          : GestureDetector(
              onTap: () => openImage(month),
              child: Image.file(
                journal!.fileFor(month),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('Không đọc được ảnh')),
              ),
            ),
    ),
  );

  Widget monthDropdown(String value, ValueChanged<String?> changed) =>
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: [
          for (final month in months)
            DropdownMenuItem(value: month, child: Text(label(month))),
        ],
        onChanged: changed,
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final canNext = DateTime(
      selected.year,
      selected.month + 1,
    ).isBefore(DateTime(now.year, now.month + 1));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Text(
          'Ảnh theo tháng',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        const Text(
          'Chụp cùng góc đứng và ánh sáng mỗi tháng để dễ nhìn lại thay đổi.',
          style: TextStyle(color: _muted, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (journal == null && error == null)
          const Center(child: CircularProgressIndicator())
        else if (error != null)
          Text(error!, style: const TextStyle(color: Colors.redAccent))
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Tháng trước',
                onPressed: selected.year <= 2000 && selected.month == 1
                    ? null
                    : () => moveMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  label(selectedMonth),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                onPressed: canNext ? () => moveMonth(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: photoFrame(hasCurrent ? selectedMonth : null),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : () => capture(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Chụp ảnh'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => capture(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh'),
                ),
              ),
            ],
          ),
          if (hasCurrent)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: exportCurrent,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Lưu ảnh ra máy'),
                ),
                TextButton.icon(
                  onPressed: deleteCurrent,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Xóa'),
                ),
              ],
            ),
          const SizedBox(height: 18),
          if (months.isNotEmpty) ...[
            const Text(
              'Các tháng đã lưu',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: months.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final month = months[index];
                  return ChoiceChip(
                    label: Text(label(month)),
                    selected: selectedMonth == month,
                    onSelected: (_) => setState(() {
                      selected = DateTime(
                        int.parse(month.substring(0, 4)),
                        int.parse(month.substring(5)),
                      );
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (months.length >= 2) ...[
            const Text(
              'So sánh trước và sau',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      monthDropdown(compareBefore!, (month) {
                        if (month != null) {
                          setState(() => compareBefore = month);
                        }
                      }),
                      photoFrame(compareBefore),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      monthDropdown(compareAfter!, (month) {
                        if (month != null) {
                          setState(() => compareAfter = month);
                        }
                      }),
                      photoFrame(compareAfter),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Chạm vào ảnh để xem lớn và phóng to.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ] else
            const Text(
              'Lưu ảnh ở hai tháng để xem thay đổi cạnh nhau.',
              style: TextStyle(color: _muted),
            ),
          const SizedBox(height: 22),
          const Text(
            'Ảnh được giữ riêng trên thiết bị. Bản sao lưu JSON chỉ chứa nhật ký tập; hãy dùng “Lưu ảnh ra máy” trước khi gỡ ứng dụng.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }
}
