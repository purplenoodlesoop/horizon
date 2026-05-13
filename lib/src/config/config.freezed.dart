// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$HorizonConfig {
  String get vaultPath;
  Mode<()> get mode;
  String get allowlistOverride;
  IList<String> get extraAllowlists;
  String get templatesPath;
  Duration get heartbeatInterval;
  bool get streamUi;
  String get envFilePath;

  /// Create a copy of HorizonConfig
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $HorizonConfigCopyWith<HorizonConfig> get copyWith =>
      _$HorizonConfigCopyWithImpl<HorizonConfig>(
          this as HorizonConfig, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is HorizonConfig &&
            (identical(other.vaultPath, vaultPath) ||
                other.vaultPath == vaultPath) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.allowlistOverride, allowlistOverride) ||
                other.allowlistOverride == allowlistOverride) &&
            const DeepCollectionEquality()
                .equals(other.extraAllowlists, extraAllowlists) &&
            (identical(other.templatesPath, templatesPath) ||
                other.templatesPath == templatesPath) &&
            (identical(other.heartbeatInterval, heartbeatInterval) ||
                other.heartbeatInterval == heartbeatInterval) &&
            (identical(other.streamUi, streamUi) ||
                other.streamUi == streamUi) &&
            (identical(other.envFilePath, envFilePath) ||
                other.envFilePath == envFilePath));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      vaultPath,
      mode,
      allowlistOverride,
      const DeepCollectionEquality().hash(extraAllowlists),
      templatesPath,
      heartbeatInterval,
      streamUi,
      envFilePath);

  @override
  String toString() {
    return 'HorizonConfig(vaultPath: $vaultPath, mode: $mode, allowlistOverride: $allowlistOverride, extraAllowlists: $extraAllowlists, templatesPath: $templatesPath, heartbeatInterval: $heartbeatInterval, streamUi: $streamUi, envFilePath: $envFilePath)';
  }
}

/// @nodoc
abstract mixin class $HorizonConfigCopyWith<$Res> {
  factory $HorizonConfigCopyWith(
          HorizonConfig value, $Res Function(HorizonConfig) _then) =
      _$HorizonConfigCopyWithImpl;
  @useResult
  $Res call(
      {String vaultPath,
      Mode<()> mode,
      String allowlistOverride,
      IList<String> extraAllowlists,
      String templatesPath,
      Duration heartbeatInterval,
      bool streamUi,
      String envFilePath});
}

/// @nodoc
class _$HorizonConfigCopyWithImpl<$Res>
    implements $HorizonConfigCopyWith<$Res> {
  _$HorizonConfigCopyWithImpl(this._self, this._then);

  final HorizonConfig _self;
  final $Res Function(HorizonConfig) _then;

  /// Create a copy of HorizonConfig
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? vaultPath = null,
    Object? mode = null,
    Object? allowlistOverride = null,
    Object? extraAllowlists = null,
    Object? templatesPath = null,
    Object? heartbeatInterval = null,
    Object? streamUi = null,
    Object? envFilePath = null,
  }) {
    return _then(_self.copyWith(
      vaultPath: null == vaultPath
          ? _self.vaultPath
          : vaultPath // ignore: cast_nullable_to_non_nullable
              as String,
      mode: null == mode
          ? _self.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as Mode<()>,
      allowlistOverride: null == allowlistOverride
          ? _self.allowlistOverride
          : allowlistOverride // ignore: cast_nullable_to_non_nullable
              as String,
      extraAllowlists: null == extraAllowlists
          ? _self.extraAllowlists
          : extraAllowlists // ignore: cast_nullable_to_non_nullable
              as IList<String>,
      templatesPath: null == templatesPath
          ? _self.templatesPath
          : templatesPath // ignore: cast_nullable_to_non_nullable
              as String,
      heartbeatInterval: null == heartbeatInterval
          ? _self.heartbeatInterval
          : heartbeatInterval // ignore: cast_nullable_to_non_nullable
              as Duration,
      streamUi: null == streamUi
          ? _self.streamUi
          : streamUi // ignore: cast_nullable_to_non_nullable
              as bool,
      envFilePath: null == envFilePath
          ? _self.envFilePath
          : envFilePath // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [HorizonConfig].
extension HorizonConfigPatterns on HorizonConfig {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_HorizonConfig value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_HorizonConfig value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_HorizonConfig value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            String vaultPath,
            Mode<()> mode,
            String allowlistOverride,
            IList<String> extraAllowlists,
            String templatesPath,
            Duration heartbeatInterval,
            bool streamUi,
            String envFilePath)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig() when $default != null:
        return $default(
            _that.vaultPath,
            _that.mode,
            _that.allowlistOverride,
            _that.extraAllowlists,
            _that.templatesPath,
            _that.heartbeatInterval,
            _that.streamUi,
            _that.envFilePath);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            String vaultPath,
            Mode<()> mode,
            String allowlistOverride,
            IList<String> extraAllowlists,
            String templatesPath,
            Duration heartbeatInterval,
            bool streamUi,
            String envFilePath)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig():
        return $default(
            _that.vaultPath,
            _that.mode,
            _that.allowlistOverride,
            _that.extraAllowlists,
            _that.templatesPath,
            _that.heartbeatInterval,
            _that.streamUi,
            _that.envFilePath);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            String vaultPath,
            Mode<()> mode,
            String allowlistOverride,
            IList<String> extraAllowlists,
            String templatesPath,
            Duration heartbeatInterval,
            bool streamUi,
            String envFilePath)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig() when $default != null:
        return $default(
            _that.vaultPath,
            _that.mode,
            _that.allowlistOverride,
            _that.extraAllowlists,
            _that.templatesPath,
            _that.heartbeatInterval,
            _that.streamUi,
            _that.envFilePath);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _HorizonConfig implements HorizonConfig {
  const _HorizonConfig(
      {required this.vaultPath,
      required this.mode,
      required this.allowlistOverride,
      required this.extraAllowlists,
      required this.templatesPath,
      required this.heartbeatInterval,
      required this.streamUi,
      required this.envFilePath});

  @override
  final String vaultPath;
  @override
  final Mode<()> mode;
  @override
  final String allowlistOverride;
  @override
  final IList<String> extraAllowlists;
  @override
  final String templatesPath;
  @override
  final Duration heartbeatInterval;
  @override
  final bool streamUi;
  @override
  final String envFilePath;

  /// Create a copy of HorizonConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$HorizonConfigCopyWith<_HorizonConfig> get copyWith =>
      __$HorizonConfigCopyWithImpl<_HorizonConfig>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _HorizonConfig &&
            (identical(other.vaultPath, vaultPath) ||
                other.vaultPath == vaultPath) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.allowlistOverride, allowlistOverride) ||
                other.allowlistOverride == allowlistOverride) &&
            const DeepCollectionEquality()
                .equals(other.extraAllowlists, extraAllowlists) &&
            (identical(other.templatesPath, templatesPath) ||
                other.templatesPath == templatesPath) &&
            (identical(other.heartbeatInterval, heartbeatInterval) ||
                other.heartbeatInterval == heartbeatInterval) &&
            (identical(other.streamUi, streamUi) ||
                other.streamUi == streamUi) &&
            (identical(other.envFilePath, envFilePath) ||
                other.envFilePath == envFilePath));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      vaultPath,
      mode,
      allowlistOverride,
      const DeepCollectionEquality().hash(extraAllowlists),
      templatesPath,
      heartbeatInterval,
      streamUi,
      envFilePath);

  @override
  String toString() {
    return 'HorizonConfig(vaultPath: $vaultPath, mode: $mode, allowlistOverride: $allowlistOverride, extraAllowlists: $extraAllowlists, templatesPath: $templatesPath, heartbeatInterval: $heartbeatInterval, streamUi: $streamUi, envFilePath: $envFilePath)';
  }
}

/// @nodoc
abstract mixin class _$HorizonConfigCopyWith<$Res>
    implements $HorizonConfigCopyWith<$Res> {
  factory _$HorizonConfigCopyWith(
          _HorizonConfig value, $Res Function(_HorizonConfig) _then) =
      __$HorizonConfigCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String vaultPath,
      Mode<()> mode,
      String allowlistOverride,
      IList<String> extraAllowlists,
      String templatesPath,
      Duration heartbeatInterval,
      bool streamUi,
      String envFilePath});
}

/// @nodoc
class __$HorizonConfigCopyWithImpl<$Res>
    implements _$HorizonConfigCopyWith<$Res> {
  __$HorizonConfigCopyWithImpl(this._self, this._then);

  final _HorizonConfig _self;
  final $Res Function(_HorizonConfig) _then;

  /// Create a copy of HorizonConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? vaultPath = null,
    Object? mode = null,
    Object? allowlistOverride = null,
    Object? extraAllowlists = null,
    Object? templatesPath = null,
    Object? heartbeatInterval = null,
    Object? streamUi = null,
    Object? envFilePath = null,
  }) {
    return _then(_HorizonConfig(
      vaultPath: null == vaultPath
          ? _self.vaultPath
          : vaultPath // ignore: cast_nullable_to_non_nullable
              as String,
      mode: null == mode
          ? _self.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as Mode<()>,
      allowlistOverride: null == allowlistOverride
          ? _self.allowlistOverride
          : allowlistOverride // ignore: cast_nullable_to_non_nullable
              as String,
      extraAllowlists: null == extraAllowlists
          ? _self.extraAllowlists
          : extraAllowlists // ignore: cast_nullable_to_non_nullable
              as IList<String>,
      templatesPath: null == templatesPath
          ? _self.templatesPath
          : templatesPath // ignore: cast_nullable_to_non_nullable
              as String,
      heartbeatInterval: null == heartbeatInterval
          ? _self.heartbeatInterval
          : heartbeatInterval // ignore: cast_nullable_to_non_nullable
              as Duration,
      streamUi: null == streamUi
          ? _self.streamUi
          : streamUi // ignore: cast_nullable_to_non_nullable
              as bool,
      envFilePath: null == envFilePath
          ? _self.envFilePath
          : envFilePath // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
