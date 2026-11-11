import 'local_cache_store_base.dart';
import 'local_cache_store_stub.dart'
    if (dart.library.io) 'local_cache_store_io.dart'
    if (dart.library.html) 'local_cache_store_web.dart' as impl;

export 'local_cache_store_base.dart';

LocalCacheStore createLocalCacheStore() => impl.createLocalCacheStore();
