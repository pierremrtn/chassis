// import 'dart:io';

// import 'package:chassis/chassis.dart';
// import 'package:chassis_flutter/chassis_flutter.dart';

// // Domain

// // repo
// abstract class IUserRepo {
//   UserData get user;
//   Stream<UserData> get stream;
// }

// // Model
// class UserData {}


// // Use cases
// class UserQuery implements ReadAndWatch<UserData> {}

// class UserQueryHandler extends ReadAndWatchHandler<UserQuery, UserData> {
//   UserQueryHandler({required IUserRepo repo})
//       : super(
//           read: (query) async => repo.user,
//           watch: (query) => repo.stream,
//         );
// }

// final a = Mediator().read(UserQuery());


// // UI
// class MyViewModel extends ViewModel<int> {
//   MyViewModel({
//     required UserQueryHandler userHandler,
//   }) : super(0) {

//     userQuery = readHandle(userHandler);
//     userStream = watchHandle(userHandler);

//     autoDisposeStreamSubscription(userHandler.watch(UserQuery()).listen((data) {}));

//     readHandle(userHandler);

//     autoDispose(disposable)
//     autoDisposeStreamSubscription(sub)
//     listenTo(notifier, () {});
//     mergeAndListenTo([notifier, notigier], () {});
//     listenToStreams([userQuery.stream], () {});
//     listenToHandle(userQuery, (state) {});
//     listenToHandles([userQuery, userStream], () {});


//     listenToHandle(userStream, () {
//       if (userStream.state case HandleStateSuccess(:final data)) {
//         print(data);
//       }
//     });

//     // NTH
//     listenToValueNotifier(...);
//     listen2Handles(a, b, c, (a, b) {});
//     listen3Handles(a, b, c, (a, b, c) {});
//   }

//   late final ReadHandle<UserQuery, UserData> userQuery;
//   late final WatchHandle<UserQuery, UserData> userStream;



//   void getUser() async {
//     userQuery.refresh();

//     final res = await read(userHandler);
//     res.when(
//       success: (s) => emit(s),
//       error: (e) => 
//     );
//   }
// }


// // Widget tree

// // final p = Provider(
// //   create: (context) => MyViewModel(
// //     userHandler: Mediator().handler(),
// //   ),
// // );
