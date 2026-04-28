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

String _$ingestionServiceHash() => r'0107870512229bebc71a98fda98db60c3e76a870';

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
