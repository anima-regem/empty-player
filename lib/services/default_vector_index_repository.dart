import 'dart:io';

import 'package:empty_player/services/sqlite_vector_index_repository.dart';
import 'package:empty_player/services/vector_index_repository.dart';

VectorIndexRepository createDefaultVectorIndexRepository() {
  if (Platform.isAndroid) {
    return SqliteVectorIndexRepository();
  }
  return InMemoryVectorIndexRepository();
}
