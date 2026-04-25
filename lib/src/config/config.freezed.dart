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
  String get telegramToken;
  String get telegramUsername;
  String get fireworksToken;
  String get tavilyToken;
  String get vaultPath;
  Mode<()> get mode;
  String get allowlistPath;
  String get templatesPath;
  Duration get heartbeatInterval;

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
            (identical(other.telegramToken, telegramToken) ||
                other.telegramToken == telegramToken) &&
            (identical(other.telegramUsername, telegramUsername) ||
                other.telegramUsername == telegramUsername) &&
            (identical(other.fireworksToken, fireworksToken) ||
                other.fireworksToken == fireworksToken) &&
            (identical(other.tavilyToken, tavilyToken) ||
                other.tavilyToken == tavilyToken) &&
            (identical(other.vaultPath, vaultPath) ||
                other.vaultPath == vaultPath) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.allowlistPath, allowlistPath) ||
                other.allowlistPath == allowlistPath) &&
            (identical(other.templatesPath, templatesPath) ||
                other.templatesPath == templatesPath) &&
            (identical(other.heartbeatInterval, heartbeatInterval) ||
                other.heartbeatInterval == heartbeatInterval));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      telegramToken,
      telegramUsername,
      fireworksToken,
      tavilyToken,
      vaultPath,
      mode,
      allowlistPath,
      templatesPath,
      heartbeatInterval);

  @override
  String toString() {
    return 'HorizonConfig(telegramToken: $telegramToken, telegramUsername: $telegramUsername, fireworksToken: $fireworksToken, tavilyToken: $tavilyToken, vaultPath: $vaultPath, mode: $mode, allowlistPath: $allowlistPath, templatesPath: $templatesPath, heartbeatInterval: $heartbeatInterval)';
  }
}

/// @nodoc
abstract mixin class $HorizonConfigCopyWith<$Res> {
  factory $HorizonConfigCopyWith(
          HorizonConfig value, $Res Function(HorizonConfig) _then) =
      _$HorizonConfigCopyWithImpl;
  @useResult
  $Res call(
      {String telegramToken,
      String telegramUsername,
      String fireworksToken,
      String tavilyToken,
      String vaultPath,
      Mode<()> mode,
      String allowlistPath,
      String templatesPath,
      Duration heartbeatInterval});
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
    Object? telegramToken = null,
    Object? telegramUsername = null,
    Object? fireworksToken = null,
    Object? tavilyToken = null,
    Object? vaultPath = null,
    Object? mode = null,
    Object? allowlistPath = null,
    Object? templatesPath = null,
    Object? heartbeatInterval = null,
  }) {
    return _then(_self.copyWith(
      telegramToken: null == telegramToken
          ? _self.telegramToken
          : telegramToken // ignore: cast_nullable_to_non_nullable
              as String,
      telegramUsername: null == telegramUsername
          ? _self.telegramUsername
          : telegramUsername // ignore: cast_nullable_to_non_nullable
              as String,
      fireworksToken: null == fireworksToken
          ? _self.fireworksToken
          : fireworksToken // ignore: cast_nullable_to_non_nullable
              as String,
      tavilyToken: null == tavilyToken
          ? _self.tavilyToken
          : tavilyToken // ignore: cast_nullable_to_non_nullable
              as String,
      vaultPath: null == vaultPath
          ? _self.vaultPath
          : vaultPath // ignore: cast_nullable_to_non_nullable
              as String,
      mode: null == mode
          ? _self.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as Mode<()>,
      allowlistPath: null == allowlistPath
          ? _self.allowlistPath
          : allowlistPath // ignore: cast_nullable_to_non_nullable
              as String,
      templatesPath: null == templatesPath
          ? _self.templatesPath
          : templatesPath // ignore: cast_nullable_to_non_nullable
              as String,
      heartbeatInterval: null == heartbeatInterval
          ? _self.heartbeatInterval
          : heartbeatInterval // ignore: cast_nullable_to_non_nullable
              as Duration,
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
            String telegramToken,
            String telegramUsername,
            String fireworksToken,
            String tavilyToken,
            String vaultPath,
            Mode<()> mode,
            String allowlistPath,
            String templatesPath,
            Duration heartbeatInterval)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig() when $default != null:
        return $default(
            _that.telegramToken,
            _that.telegramUsername,
            _that.fireworksToken,
            _that.tavilyToken,
            _that.vaultPath,
            _that.mode,
            _that.allowlistPath,
            _that.templatesPath,
            _that.heartbeatInterval);
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
            String telegramToken,
            String telegramUsername,
            String fireworksToken,
            String tavilyToken,
            String vaultPath,
            Mode<()> mode,
            String allowlistPath,
            String templatesPath,
            Duration heartbeatInterval)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig():
        return $default(
            _that.telegramToken,
            _that.telegramUsername,
            _that.fireworksToken,
            _that.tavilyToken,
            _that.vaultPath,
            _that.mode,
            _that.allowlistPath,
            _that.templatesPath,
            _that.heartbeatInterval);
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
            String telegramToken,
            String telegramUsername,
            String fireworksToken,
            String tavilyToken,
            String vaultPath,
            Mode<()> mode,
            String allowlistPath,
            String templatesPath,
            Duration heartbeatInterval)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _HorizonConfig() when $default != null:
        return $default(
            _that.telegramToken,
            _that.telegramUsername,
            _that.fireworksToken,
            _that.tavilyToken,
            _that.vaultPath,
            _that.mode,
            _that.allowlistPath,
            _that.templatesPath,
            _that.heartbeatInterval);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _HorizonConfig implements HorizonConfig {
  const _HorizonConfig(
      {required this.telegramToken,
      required this.telegramUsername,
      required this.fireworksToken,
      required this.tavilyToken,
      required this.vaultPath,
      required this.mode,
      required this.allowlistPath,
      required this.templatesPath,
      required this.heartbeatInterval});

  @override
  final String telegramToken;
  @override
  final String telegramUsername;
  @override
  final String fireworksToken;
  @override
  final String tavilyToken;
  @override
  final String vaultPath;
  @override
  final Mode<()> mode;
  @override
  final String allowlistPath;
  @override
  final String templatesPath;
  @override
  final Duration heartbeatInterval;

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
            (identical(other.telegramToken, telegramToken) ||
                other.telegramToken == telegramToken) &&
            (identical(other.telegramUsername, telegramUsername) ||
                other.telegramUsername == telegramUsername) &&
            (identical(other.fireworksToken, fireworksToken) ||
                other.fireworksToken == fireworksToken) &&
            (identical(other.tavilyToken, tavilyToken) ||
                other.tavilyToken == tavilyToken) &&
            (identical(other.vaultPath, vaultPath) ||
                other.vaultPath == vaultPath) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.allowlistPath, allowlistPath) ||
                other.allowlistPath == allowlistPath) &&
            (identical(other.templatesPath, templatesPath) ||
                other.templatesPath == templatesPath) &&
            (identical(other.heartbeatInterval, heartbeatInterval) ||
                other.heartbeatInterval == heartbeatInterval));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      telegramToken,
      telegramUsername,
      fireworksToken,
      tavilyToken,
      vaultPath,
      mode,
      allowlistPath,
      templatesPath,
      heartbeatInterval);

  @override
  String toString() {
    return 'HorizonConfig(telegramToken: $telegramToken, telegramUsername: $telegramUsername, fireworksToken: $fireworksToken, tavilyToken: $tavilyToken, vaultPath: $vaultPath, mode: $mode, allowlistPath: $allowlistPath, templatesPath: $templatesPath, heartbeatInterval: $heartbeatInterval)';
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
      {String telegramToken,
      String telegramUsername,
      String fireworksToken,
      String tavilyToken,
      String vaultPath,
      Mode<()> mode,
      String allowlistPath,
      String templatesPath,
      Duration heartbeatInterval});
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
    Object? telegramToken = null,
    Object? telegramUsername = null,
    Object? fireworksToken = null,
    Object? tavilyToken = null,
    Object? vaultPath = null,
    Object? mode = null,
    Object? allowlistPath = null,
    Object? templatesPath = null,
    Object? heartbeatInterval = null,
  }) {
    return _then(_HorizonConfig(
      telegramToken: null == telegramToken
          ? _self.telegramToken
          : telegramToken // ignore: cast_nullable_to_non_nullable
              as String,
      telegramUsername: null == telegramUsername
          ? _self.telegramUsername
          : telegramUsername // ignore: cast_nullable_to_non_nullable
              as String,
      fireworksToken: null == fireworksToken
          ? _self.fireworksToken
          : fireworksToken // ignore: cast_nullable_to_non_nullable
              as String,
      tavilyToken: null == tavilyToken
          ? _self.tavilyToken
          : tavilyToken // ignore: cast_nullable_to_non_nullable
              as String,
      vaultPath: null == vaultPath
          ? _self.vaultPath
          : vaultPath // ignore: cast_nullable_to_non_nullable
              as String,
      mode: null == mode
          ? _self.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as Mode<()>,
      allowlistPath: null == allowlistPath
          ? _self.allowlistPath
          : allowlistPath // ignore: cast_nullable_to_non_nullable
              as String,
      templatesPath: null == templatesPath
          ? _self.templatesPath
          : templatesPath // ignore: cast_nullable_to_non_nullable
              as String,
      heartbeatInterval: null == heartbeatInterval
          ? _self.heartbeatInterval
          : heartbeatInterval // ignore: cast_nullable_to_non_nullable
              as Duration,
    ));
  }
}

// dart format on
