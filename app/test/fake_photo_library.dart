import 'dart:typed_data';

import 'package:platter/services/photo_library.dart';

/// Stands in for the system prompt: [answer] is what the user taps.
class FakePhotoLibrary implements PhotoLibrary {
  FakePhotoLibrary({this.access = PhotoAccess.notAsked, this.answer});

  PhotoAccess access;
  PhotoAccess? answer;
  int count = 3;
  int requests = 0;
  int pickerOpens = 0;
  int settingsOpens = 0;

  /// What [thumbnail] returns for every photo; null stands for photos that
  /// can't be loaded.
  Uint8List? thumbnailBytes;

  /// The sizes thumbnails were asked for, in order.
  final thumbnailSizes = <int>[];

  @override
  Future<PhotoAccess> currentAccess() async => access;

  @override
  Future<PhotoAccess> requestAccess() async {
    requests++;
    if (access == PhotoAccess.notAsked && answer != null) access = answer!;
    return access;
  }

  @override
  Future<void> changeSelection() async => pickerOpens++;

  @override
  Future<int> photoCount() async => count;

  @override
  Future<List<Uint8List>> recentThumbnails(int count) async => const [];

  @override
  Future<Uint8List?> thumbnail(String id, {int size = 200}) async {
    thumbnailSizes.add(size);
    return thumbnailBytes;
  }

  @override
  Future<void> openSettings() async => settingsOpens++;
}
