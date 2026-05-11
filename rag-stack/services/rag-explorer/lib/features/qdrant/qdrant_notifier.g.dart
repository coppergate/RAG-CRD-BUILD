// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'qdrant_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(QdrantNotifier)
final qdrantProvider = QdrantNotifierProvider._();

final class QdrantNotifierProvider
    extends $AsyncNotifierProvider<QdrantNotifier, QdrantState> {
  QdrantNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'qdrantProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$qdrantNotifierHash();

  @$internal
  @override
  QdrantNotifier create() => QdrantNotifier();
}

String _$qdrantNotifierHash() => r'ec285750286591b6dfb2a1fbb1d8682b8ce6230a';

abstract class _$QdrantNotifier extends $AsyncNotifier<QdrantState> {
  FutureOr<QdrantState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<QdrantState>, QdrantState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<QdrantState>, QdrantState>,
              AsyncValue<QdrantState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
