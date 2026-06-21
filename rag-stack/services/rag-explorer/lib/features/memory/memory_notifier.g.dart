// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MemoryNotifier)
final memoryProvider = MemoryNotifierProvider._();

final class MemoryNotifierProvider
    extends $NotifierProvider<MemoryNotifier, MemoryState> {
  MemoryNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memoryNotifierHash();

  @$internal
  @override
  MemoryNotifier create() => MemoryNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MemoryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MemoryState>(value),
    );
  }
}

String _$memoryNotifierHash() => r'2a15dc8666f84b8d1170b95e4c0a16bb44ef97dd';

abstract class _$MemoryNotifier extends $Notifier<MemoryState> {
  MemoryState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<MemoryState, MemoryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MemoryState, MemoryState>,
              MemoryState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
