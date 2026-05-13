// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'capability.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Capability {
  String get id;
  String get description;
  String get relativePath;
  String? get schedule;
  IList<String> get watch;

  /// Create a copy of Capability
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CapabilityCopyWith<Capability> get copyWith =>
      _$CapabilityCopyWithImpl<Capability>(this as Capability, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Capability &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.relativePath, relativePath) ||
                other.relativePath == relativePath) &&
            (identical(other.schedule, schedule) ||
                other.schedule == schedule) &&
            const DeepCollectionEquality().equals(other.watch, watch));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, description, relativePath,
      schedule, const DeepCollectionEquality().hash(watch));

  @override
  String toString() {
    return 'Capability(id: $id, description: $description, relativePath: $relativePath, schedule: $schedule, watch: $watch)';
  }
}

/// @nodoc
abstract mixin class $CapabilityCopyWith<$Res> {
  factory $CapabilityCopyWith(
          Capability value, $Res Function(Capability) _then) =
      _$CapabilityCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String description,
      String relativePath,
      String? schedule,
      IList<String> watch});
}

/// @nodoc
class _$CapabilityCopyWithImpl<$Res> implements $CapabilityCopyWith<$Res> {
  _$CapabilityCopyWithImpl(this._self, this._then);

  final Capability _self;
  final $Res Function(Capability) _then;

  /// Create a copy of Capability
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? description = null,
    Object? relativePath = null,
    Object? schedule = freezed,
    Object? watch = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      relativePath: null == relativePath
          ? _self.relativePath
          : relativePath // ignore: cast_nullable_to_non_nullable
              as String,
      schedule: freezed == schedule
          ? _self.schedule
          : schedule // ignore: cast_nullable_to_non_nullable
              as String?,
      watch: null == watch
          ? _self.watch
          : watch // ignore: cast_nullable_to_non_nullable
              as IList<String>,
    ));
  }
}

/// Adds pattern-matching-related methods to [Capability].
extension CapabilityPatterns on Capability {
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
    TResult Function(_Capability value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Capability() when $default != null:
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
    TResult Function(_Capability value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Capability():
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
    TResult? Function(_Capability value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Capability() when $default != null:
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
    TResult Function(String id, String description, String relativePath,
            String? schedule, IList<String> watch)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Capability() when $default != null:
        return $default(_that.id, _that.description, _that.relativePath,
            _that.schedule, _that.watch);
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
    TResult Function(String id, String description, String relativePath,
            String? schedule, IList<String> watch)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Capability():
        return $default(_that.id, _that.description, _that.relativePath,
            _that.schedule, _that.watch);
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
    TResult? Function(String id, String description, String relativePath,
            String? schedule, IList<String> watch)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Capability() when $default != null:
        return $default(_that.id, _that.description, _that.relativePath,
            _that.schedule, _that.watch);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _Capability implements Capability {
  const _Capability(
      {required this.id,
      required this.description,
      required this.relativePath,
      this.schedule,
      this.watch = const IListConst([])});

  @override
  final String id;
  @override
  final String description;
  @override
  final String relativePath;
  @override
  final String? schedule;
  @override
  @JsonKey()
  final IList<String> watch;

  /// Create a copy of Capability
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$CapabilityCopyWith<_Capability> get copyWith =>
      __$CapabilityCopyWithImpl<_Capability>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Capability &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.relativePath, relativePath) ||
                other.relativePath == relativePath) &&
            (identical(other.schedule, schedule) ||
                other.schedule == schedule) &&
            const DeepCollectionEquality().equals(other.watch, watch));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, description, relativePath,
      schedule, const DeepCollectionEquality().hash(watch));

  @override
  String toString() {
    return 'Capability(id: $id, description: $description, relativePath: $relativePath, schedule: $schedule, watch: $watch)';
  }
}

/// @nodoc
abstract mixin class _$CapabilityCopyWith<$Res>
    implements $CapabilityCopyWith<$Res> {
  factory _$CapabilityCopyWith(
          _Capability value, $Res Function(_Capability) _then) =
      __$CapabilityCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String description,
      String relativePath,
      String? schedule,
      IList<String> watch});
}

/// @nodoc
class __$CapabilityCopyWithImpl<$Res> implements _$CapabilityCopyWith<$Res> {
  __$CapabilityCopyWithImpl(this._self, this._then);

  final _Capability _self;
  final $Res Function(_Capability) _then;

  /// Create a copy of Capability
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? description = null,
    Object? relativePath = null,
    Object? schedule = freezed,
    Object? watch = null,
  }) {
    return _then(_Capability(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      relativePath: null == relativePath
          ? _self.relativePath
          : relativePath // ignore: cast_nullable_to_non_nullable
              as String,
      schedule: freezed == schedule
          ? _self.schedule
          : schedule // ignore: cast_nullable_to_non_nullable
              as String?,
      watch: null == watch
          ? _self.watch
          : watch // ignore: cast_nullable_to_non_nullable
              as IList<String>,
    ));
  }
}

// dart format on
