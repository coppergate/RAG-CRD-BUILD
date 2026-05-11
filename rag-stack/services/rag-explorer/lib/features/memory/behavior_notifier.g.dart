// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'behavior_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BehaviorNotifier)
final behaviorProvider = BehaviorNotifierProvider._();

final class BehaviorNotifierProvider
    extends $AsyncNotifierProvider<BehaviorNotifier, BehaviorState> {
  BehaviorNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'behaviorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$behaviorNotifierHash();

  @$internal
  @override
  BehaviorNotifier create() => BehaviorNotifier();
}

String _$behaviorNotifierHash() => r'73324e73566290ea3bd21c362dea51878d43def9';

abstract class _$BehaviorNotifier extends $AsyncNotifier<BehaviorState> {
  FutureOr<BehaviorState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<BehaviorState>, BehaviorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BehaviorState>, BehaviorState>,
              AsyncValue<BehaviorState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
