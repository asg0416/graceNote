// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'iam_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$inAppMessagesHash() => r'125622312f1273b7dd12a8555ff9ace20ec2dc10';

/// See also [inAppMessages].
@ProviderFor(inAppMessages)
final inAppMessagesProvider =
    AutoDisposeStreamProvider<List<InAppMessage>>.internal(
  inAppMessages,
  name: r'inAppMessagesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$inAppMessagesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef InAppMessagesRef = AutoDisposeStreamProviderRef<List<InAppMessage>>;
String _$visibleIamHash() => r'8946470dfeae2b1af2e51c8d4d491b3d7398db24';

/// See also [visibleIam].
@ProviderFor(visibleIam)
final visibleIamProvider = AutoDisposeProvider<List<InAppMessage>>.internal(
  visibleIam,
  name: r'visibleIamProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$visibleIamHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VisibleIamRef = AutoDisposeProviderRef<List<InAppMessage>>;
String _$iamSurveyAnsweredHash() => r'bcadca489c62a37edc79b3add4a34851e610a17a';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [iamSurveyAnswered].
@ProviderFor(iamSurveyAnswered)
const iamSurveyAnsweredProvider = IamSurveyAnsweredFamily();

/// See also [iamSurveyAnswered].
class IamSurveyAnsweredFamily extends Family<AsyncValue<bool>> {
  /// See also [iamSurveyAnswered].
  const IamSurveyAnsweredFamily();

  /// See also [iamSurveyAnswered].
  IamSurveyAnsweredProvider call(
    String messageId,
  ) {
    return IamSurveyAnsweredProvider(
      messageId,
    );
  }

  @override
  IamSurveyAnsweredProvider getProviderOverride(
    covariant IamSurveyAnsweredProvider provider,
  ) {
    return call(
      provider.messageId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'iamSurveyAnsweredProvider';
}

/// See also [iamSurveyAnswered].
class IamSurveyAnsweredProvider extends AutoDisposeFutureProvider<bool> {
  /// See also [iamSurveyAnswered].
  IamSurveyAnsweredProvider(
    String messageId,
  ) : this._internal(
          (ref) => iamSurveyAnswered(
            ref as IamSurveyAnsweredRef,
            messageId,
          ),
          from: iamSurveyAnsweredProvider,
          name: r'iamSurveyAnsweredProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$iamSurveyAnsweredHash,
          dependencies: IamSurveyAnsweredFamily._dependencies,
          allTransitiveDependencies:
              IamSurveyAnsweredFamily._allTransitiveDependencies,
          messageId: messageId,
        );

  IamSurveyAnsweredProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.messageId,
  }) : super.internal();

  final String messageId;

  @override
  Override overrideWith(
    FutureOr<bool> Function(IamSurveyAnsweredRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: IamSurveyAnsweredProvider._internal(
        (ref) => create(ref as IamSurveyAnsweredRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        messageId: messageId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<bool> createElement() {
    return _IamSurveyAnsweredProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is IamSurveyAnsweredProvider && other.messageId == messageId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, messageId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin IamSurveyAnsweredRef on AutoDisposeFutureProviderRef<bool> {
  /// The parameter `messageId` of this provider.
  String get messageId;
}

class _IamSurveyAnsweredProviderElement
    extends AutoDisposeFutureProviderElement<bool> with IamSurveyAnsweredRef {
  _IamSurveyAnsweredProviderElement(super.provider);

  @override
  String get messageId => (origin as IamSurveyAnsweredProvider).messageId;
}

String _$iamSessionDismissHash() => r'587b728937e802f4acb52abb3f397afea7c94c65';

/// See also [IamSessionDismiss].
@ProviderFor(IamSessionDismiss)
final iamSessionDismissProvider =
    AutoDisposeNotifierProvider<IamSessionDismiss, Set<String>>.internal(
  IamSessionDismiss.new,
  name: r'iamSessionDismissProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$iamSessionDismissHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$IamSessionDismiss = AutoDisposeNotifier<Set<String>>;
String _$iamDismissNotifierHash() =>
    r'8e5f50f9a55fb667e878a0e3f5aa0dc6d357d0df';

/// See also [IamDismissNotifier].
@ProviderFor(IamDismissNotifier)
final iamDismissNotifierProvider = AutoDisposeAsyncNotifierProvider<
    IamDismissNotifier, Map<String, String>>.internal(
  IamDismissNotifier.new,
  name: r'iamDismissNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$iamDismissNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$IamDismissNotifier = AutoDisposeAsyncNotifier<Map<String, String>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
