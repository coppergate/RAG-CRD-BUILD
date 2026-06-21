// GENERATED CODE - DO NOT MODIFY BY HAND

part of 's3_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(S3Notifier)
final s3Provider = S3NotifierProvider._();

final class S3NotifierProvider
    extends $AsyncNotifierProvider<S3Notifier, S3State> {
  S3NotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r's3Provider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$s3NotifierHash();

  @$internal
  @override
  S3Notifier create() => S3Notifier();
}

String _$s3NotifierHash() => r'000a91c90c90a14f253ac5ee4896e21e06d48ecc';

abstract class _$S3Notifier extends $AsyncNotifier<S3State> {
  FutureOr<S3State> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<S3State>, S3State>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<S3State>, S3State>,
              AsyncValue<S3State>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
