// domain
import 'package:chassis/src/mediator/query.dart';

class AppSettings {}

// A query that can only be fetched once
class AppSettingsQuery implements ReadAndWatch<AppSettings> {}

// A handler that ONLY implements IQueryHandler
class AppSettingsHandler
    implements
        ReadHandler<AppSettingsQuery, AppSettings>,
        WatchHandler<AppSettingsQuery, AppSettings> {
  AppSettingsHandler(this.repo);

  final ISomeRepo repo;

  @override
  Future<AppSettings> read(AppSettingsQuery query) {
    return repo.test();
  }

  @override
  Stream<AppSettings> watch(AppSettingsQuery query) {
    return repo.stream;
  }
}

abstract interface class ISomeRepo {
  Future<AppSettings> test();
  Stream<AppSettings> get stream;
}

class AppSettingsHandler2
    extends ReadAndWatchHandler<AppSettingsQuery, AppSettings> {
  AppSettingsHandler2({required ISomeRepo repo})
      : super(
          read: (query) => repo.test(),
          watch: (query) => repo.stream,
        );
}
