import 'package:chassis/chassis.dart';

final class SaveTodo extends Command<String> {
  SaveTodo(this.title);

  final String title;

  @override
  Map<String, Object?> get params => {'title': title};
}

final class LoadTodos extends ReadQuery<List<String>> {}

final class WatchTodos extends WatchQuery<List<String>> {}
