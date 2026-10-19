import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

/// How much of the photo library the user has let Platter see.
enum PhotoAccess {
  /// The system prompt hasn't been shown yet.
  notAsked,
  full,

  /// iOS "Limit Access": only the photos the user picked.
  limited,

  /// Denied, or blocked by parental controls.
  none,
}

/// The device photo library, behind an interface so screens can be tested
/// without the platform plugin.
abstract interface class PhotoLibrary {
  Future<PhotoAccess> currentAccess();

  /// Shows the system prompt if it hasn't been answered yet, and returns the
  /// resulting access either way.
  Future<PhotoAccess> requestAccess();

  /// Opens the system picker so a limited-access user can change which photos
  /// Platter sees. Completes once the picker is dismissed.
  Future<void> changeSelection();

  /// Number of photos Platter can currently see.
  Future<int> photoCount();

  /// Square thumbnails of the newest visible photos, at most [count].
  Future<List<Uint8List>> recentThumbnails(int count);

  Future<void> openSettings();
}

class DevicePhotoLibrary implements PhotoLibrary {
  const DevicePhotoLibrary();

  static const _option = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  static final _newestFirst = FilterOptionGroup(
    orders: [const OrderOption(type: OrderOptionType.createDate)],
  );

  @override
  Future<PhotoAccess> currentAccess() async =>
      _map(await PhotoManager.getPermissionState(requestOption: _option));

  @override
  Future<PhotoAccess> requestAccess() async =>
      _map(await PhotoManager.requestPermissionExtend(requestOption: _option));

  @override
  Future<void> changeSelection() =>
      PhotoManager.presentLimited(type: RequestType.image);

  @override
  Future<int> photoCount() =>
      PhotoManager.getAssetCount(type: RequestType.image);

  @override
  Future<List<Uint8List>> recentThumbnails(int count) async {
    final assets = await PhotoManager.getAssetListRange(
      start: 0,
      end: count,
      type: RequestType.image,
      filterOption: _newestFirst,
    );
    final thumbs = await Future.wait(
      assets.map(
        (a) => a.thumbnailDataWithSize(const ThumbnailSize.square(88)),
      ),
    );
    return thumbs.nonNulls.toList();
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  static PhotoAccess _map(PermissionState state) => switch (state) {
    PermissionState.notDetermined => PhotoAccess.notAsked,
    PermissionState.authorized => PhotoAccess.full,
    PermissionState.limited => PhotoAccess.limited,
    PermissionState.denied || PermissionState.restricted => PhotoAccess.none,
  };
}
