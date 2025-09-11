// domain
import 'package:chassis/src/mediator/query.dart';

class AppSettings {}

// A query that can only be fetched once
final class ReadAppSettingsQuery implements ReadQuery<AppSettings> {}

final class WatchAppSettingsQuery implements WatchQuery<AppSettings> {}

class ReadAppSettingsHandler
    implements ReadHandler<ReadAppSettingsQuery, AppSettings> {
  ReadAppSettingsHandler(this.repo);

  final ISomeRepo repo;

  @override
  Future<AppSettings> read(ReadAppSettingsQuery query) {
    return repo.test();
  }
}

class WatchAppSettingsQueryHandler
    implements WatchHandler<WatchAppSettingsQuery, AppSettings> {
  WatchAppSettingsQueryHandler(this.repo);

  final ISomeRepo repo;

  @override
  Stream<AppSettings> watch(WatchAppSettingsQuery query) {
    return repo.stream;
  }
}

abstract interface class ISomeRepo {
  Future<AppSettings> test();
  Stream<AppSettings> get stream;
}
