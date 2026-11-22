import 'remote_storage_service.dart';
import 'storage_service.dart';

const String _storageMode = String.fromEnvironment(
  'STORAGE_MODE',
  defaultValue: 'local',
);

StorageService createStorageService({String? mode}) {
  final String resolved = (mode ?? _storageMode).trim().toLowerCase();
  if (resolved == 'remote') {
    return RemoteStorageService();
  }
  return StorageService();
}
