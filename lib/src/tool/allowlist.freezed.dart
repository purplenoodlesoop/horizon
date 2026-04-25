// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'allowlist.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ToolParam {
  String get type;
  String get description;

  /// Create a copy of ToolParam
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ToolParamCopyWith<ToolParam> get copyWith =>
      _$ToolParamCopyWithImpl<ToolParam>(this as ToolParam, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ToolParam &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @override
  int get hashCode => Object.hash(runtimeType, type, description);

  @override
  String toString() {
    return 'ToolParam(type: $type, description: $description)';
  }
}

/// @nodoc
abstract mixin class $ToolParamCopyWith<$Res> {
  factory $ToolParamCopyWith(ToolParam value, $Res Function(ToolParam) _then) =
      _$ToolParamCopyWithImpl;
  @useResult
  $Res call({String type, String description});
}

/// @nodoc
class _$ToolParamCopyWithImpl<$Res> implements $ToolParamCopyWith<$Res> {
  _$ToolParamCopyWithImpl(this._self, this._then);

  final ToolParam _self;
  final $Res Function(ToolParam) _then;

  /// Create a copy of ToolParam
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? description = null,
  }) {
    return _then(_self.copyWith(
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [ToolParam].
extension ToolParamPatterns on ToolParam {
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
    TResult Function(_ToolParam value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ToolParam() when $default != null:
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
    TResult Function(_ToolParam value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ToolParam():
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
    TResult? Function(_ToolParam value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ToolParam() when $default != null:
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
    TResult Function(String type, String description)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ToolParam() when $default != null:
        return $default(_that.type, _that.description);
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
    TResult Function(String type, String description) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ToolParam():
        return $default(_that.type, _that.description);
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
    TResult? Function(String type, String description)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ToolParam() when $default != null:
        return $default(_that.type, _that.description);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _ToolParam implements ToolParam {
  const _ToolParam({required this.type, required this.description});

  @override
  final String type;
  @override
  final String description;

  /// Create a copy of ToolParam
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ToolParamCopyWith<_ToolParam> get copyWith =>
      __$ToolParamCopyWithImpl<_ToolParam>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ToolParam &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @override
  int get hashCode => Object.hash(runtimeType, type, description);

  @override
  String toString() {
    return 'ToolParam(type: $type, description: $description)';
  }
}

/// @nodoc
abstract mixin class _$ToolParamCopyWith<$Res>
    implements $ToolParamCopyWith<$Res> {
  factory _$ToolParamCopyWith(
          _ToolParam value, $Res Function(_ToolParam) _then) =
      __$ToolParamCopyWithImpl;
  @override
  @useResult
  $Res call({String type, String description});
}

/// @nodoc
class __$ToolParamCopyWithImpl<$Res> implements _$ToolParamCopyWith<$Res> {
  __$ToolParamCopyWithImpl(this._self, this._then);

  final _ToolParam _self;
  final $Res Function(_ToolParam) _then;

  /// Create a copy of ToolParam
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? type = null,
    Object? description = null,
  }) {
    return _then(_ToolParam(
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$AllowlistedTool {
  String get name;
  String get description;
  IMap<String, ToolParam> get parameters;
  String get commandTemplate;

  /// Create a copy of AllowlistedTool
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AllowlistedToolCopyWith<AllowlistedTool> get copyWith =>
      _$AllowlistedToolCopyWithImpl<AllowlistedTool>(
          this as AllowlistedTool, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AllowlistedTool &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.parameters, parameters) ||
                other.parameters == parameters) &&
            (identical(other.commandTemplate, commandTemplate) ||
                other.commandTemplate == commandTemplate));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, name, description, parameters, commandTemplate);

  @override
  String toString() {
    return 'AllowlistedTool(name: $name, description: $description, parameters: $parameters, commandTemplate: $commandTemplate)';
  }
}

/// @nodoc
abstract mixin class $AllowlistedToolCopyWith<$Res> {
  factory $AllowlistedToolCopyWith(
          AllowlistedTool value, $Res Function(AllowlistedTool) _then) =
      _$AllowlistedToolCopyWithImpl;
  @useResult
  $Res call(
      {String name,
      String description,
      IMap<String, ToolParam> parameters,
      String commandTemplate});
}

/// @nodoc
class _$AllowlistedToolCopyWithImpl<$Res>
    implements $AllowlistedToolCopyWith<$Res> {
  _$AllowlistedToolCopyWithImpl(this._self, this._then);

  final AllowlistedTool _self;
  final $Res Function(AllowlistedTool) _then;

  /// Create a copy of AllowlistedTool
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? description = null,
    Object? parameters = null,
    Object? commandTemplate = null,
  }) {
    return _then(_self.copyWith(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      parameters: null == parameters
          ? _self.parameters
          : parameters // ignore: cast_nullable_to_non_nullable
              as IMap<String, ToolParam>,
      commandTemplate: null == commandTemplate
          ? _self.commandTemplate
          : commandTemplate // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [AllowlistedTool].
extension AllowlistedToolPatterns on AllowlistedTool {
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
    TResult Function(_AllowlistedTool value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AllowlistedTool() when $default != null:
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
    TResult Function(_AllowlistedTool value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AllowlistedTool():
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
    TResult? Function(_AllowlistedTool value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AllowlistedTool() when $default != null:
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
    TResult Function(String name, String description,
            IMap<String, ToolParam> parameters, String commandTemplate)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AllowlistedTool() when $default != null:
        return $default(_that.name, _that.description, _that.parameters,
            _that.commandTemplate);
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
    TResult Function(String name, String description,
            IMap<String, ToolParam> parameters, String commandTemplate)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AllowlistedTool():
        return $default(_that.name, _that.description, _that.parameters,
            _that.commandTemplate);
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
    TResult? Function(String name, String description,
            IMap<String, ToolParam> parameters, String commandTemplate)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AllowlistedTool() when $default != null:
        return $default(_that.name, _that.description, _that.parameters,
            _that.commandTemplate);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _AllowlistedTool implements AllowlistedTool {
  const _AllowlistedTool(
      {required this.name,
      required this.description,
      required this.parameters,
      required this.commandTemplate});

  @override
  final String name;
  @override
  final String description;
  @override
  final IMap<String, ToolParam> parameters;
  @override
  final String commandTemplate;

  /// Create a copy of AllowlistedTool
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AllowlistedToolCopyWith<_AllowlistedTool> get copyWith =>
      __$AllowlistedToolCopyWithImpl<_AllowlistedTool>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AllowlistedTool &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.parameters, parameters) ||
                other.parameters == parameters) &&
            (identical(other.commandTemplate, commandTemplate) ||
                other.commandTemplate == commandTemplate));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, name, description, parameters, commandTemplate);

  @override
  String toString() {
    return 'AllowlistedTool(name: $name, description: $description, parameters: $parameters, commandTemplate: $commandTemplate)';
  }
}

/// @nodoc
abstract mixin class _$AllowlistedToolCopyWith<$Res>
    implements $AllowlistedToolCopyWith<$Res> {
  factory _$AllowlistedToolCopyWith(
          _AllowlistedTool value, $Res Function(_AllowlistedTool) _then) =
      __$AllowlistedToolCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String name,
      String description,
      IMap<String, ToolParam> parameters,
      String commandTemplate});
}

/// @nodoc
class __$AllowlistedToolCopyWithImpl<$Res>
    implements _$AllowlistedToolCopyWith<$Res> {
  __$AllowlistedToolCopyWithImpl(this._self, this._then);

  final _AllowlistedTool _self;
  final $Res Function(_AllowlistedTool) _then;

  /// Create a copy of AllowlistedTool
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? name = null,
    Object? description = null,
    Object? parameters = null,
    Object? commandTemplate = null,
  }) {
    return _then(_AllowlistedTool(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      parameters: null == parameters
          ? _self.parameters
          : parameters // ignore: cast_nullable_to_non_nullable
              as IMap<String, ToolParam>,
      commandTemplate: null == commandTemplate
          ? _self.commandTemplate
          : commandTemplate // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
