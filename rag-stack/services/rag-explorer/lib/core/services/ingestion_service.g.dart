// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ingestion_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IngestionService)
final ingestionServiceProvider = IngestionServiceProvider._();

final class IngestionServiceProvider
    extends $AsyncNotifierProvider<IngestionService, void> {
  IngestionServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ingestionServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ingestionServiceHash();

  @$internal
  @override
  IngestionService create() => IngestionService();
}

String _$ingestionServiceHash() => r'6917fe9cb8fa6b33c7f163d7b6c5c60979f165b4';

abstract class _$IngestionService extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
