// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timescale_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TimescaleNotifier)
final timescaleProvider = TimescaleNotifierProvider._();

final class TimescaleNotifierProvider
    extends $AsyncNotifierProvider<TimescaleNotifier, TimescaleState> {
  TimescaleNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timescaleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timescaleNotifierHash();

  @$internal
  @override
  TimescaleNotifier create() => TimescaleNotifier();
}

String _$timescaleNotifierHash() => r'fed8abed085f2c99378f2fc44460908ed8600c79';

abstract class _$TimescaleNotifier extends $AsyncNotifier<TimescaleState> {
  FutureOr<TimescaleState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<TimescaleState>, TimescaleState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<TimescaleState>, TimescaleState>,
              AsyncValue<TimescaleState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
