// Certificate pinning for the phone apps; browsers handle certificates themselves.
export 'pinning_stub.dart' if (dart.library.io) 'pinning_io.dart';
