// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatState {

 List<Session> get sessions; List<Tag> get availableTags; List<Tag> get selectedTags; int? get currentSessionId; String? get currentSessionName; List<ResponseMessage> get messages; bool get isStreaming; bool get inConversation; int? get selectedMessageIndex; String get selectedPlanner; String get selectedExecutor; bool get showMetadata; double get metadataPanelWidth; Set<int> get selectedSessionIds; String get memoryMode;
/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatStateCopyWith<ChatState> get copyWith => _$ChatStateCopyWithImpl<ChatState>(this as ChatState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatState&&const DeepCollectionEquality().equals(other.sessions, sessions)&&const DeepCollectionEquality().equals(other.availableTags, availableTags)&&const DeepCollectionEquality().equals(other.selectedTags, selectedTags)&&(identical(other.currentSessionId, currentSessionId) || other.currentSessionId == currentSessionId)&&(identical(other.currentSessionName, currentSessionName) || other.currentSessionName == currentSessionName)&&const DeepCollectionEquality().equals(other.messages, messages)&&(identical(other.isStreaming, isStreaming) || other.isStreaming == isStreaming)&&(identical(other.inConversation, inConversation) || other.inConversation == inConversation)&&(identical(other.selectedMessageIndex, selectedMessageIndex) || other.selectedMessageIndex == selectedMessageIndex)&&(identical(other.selectedPlanner, selectedPlanner) || other.selectedPlanner == selectedPlanner)&&(identical(other.selectedExecutor, selectedExecutor) || other.selectedExecutor == selectedExecutor)&&(identical(other.showMetadata, showMetadata) || other.showMetadata == showMetadata)&&(identical(other.metadataPanelWidth, metadataPanelWidth) || other.metadataPanelWidth == metadataPanelWidth)&&const DeepCollectionEquality().equals(other.selectedSessionIds, selectedSessionIds)&&(identical(other.memoryMode, memoryMode) || other.memoryMode == memoryMode));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(sessions),const DeepCollectionEquality().hash(availableTags),const DeepCollectionEquality().hash(selectedTags),currentSessionId,currentSessionName,const DeepCollectionEquality().hash(messages),isStreaming,inConversation,selectedMessageIndex,selectedPlanner,selectedExecutor,showMetadata,metadataPanelWidth,const DeepCollectionEquality().hash(selectedSessionIds),memoryMode);

@override
String toString() {
  return 'ChatState(sessions: $sessions, availableTags: $availableTags, selectedTags: $selectedTags, currentSessionId: $currentSessionId, currentSessionName: $currentSessionName, messages: $messages, isStreaming: $isStreaming, inConversation: $inConversation, selectedMessageIndex: $selectedMessageIndex, selectedPlanner: $selectedPlanner, selectedExecutor: $selectedExecutor, showMetadata: $showMetadata, metadataPanelWidth: $metadataPanelWidth, selectedSessionIds: $selectedSessionIds, memoryMode: $memoryMode)';
}


}

/// @nodoc
abstract mixin class $ChatStateCopyWith<$Res>  {
  factory $ChatStateCopyWith(ChatState value, $Res Function(ChatState) _then) = _$ChatStateCopyWithImpl;
@useResult
$Res call({
 List<Session> sessions, List<Tag> availableTags, List<Tag> selectedTags, int? currentSessionId, String? currentSessionName, List<ResponseMessage> messages, bool isStreaming, bool inConversation, int? selectedMessageIndex, String selectedPlanner, String selectedExecutor, bool showMetadata, double metadataPanelWidth, Set<int> selectedSessionIds, String memoryMode
});




}
/// @nodoc
class _$ChatStateCopyWithImpl<$Res>
    implements $ChatStateCopyWith<$Res> {
  _$ChatStateCopyWithImpl(this._self, this._then);

  final ChatState _self;
  final $Res Function(ChatState) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessions = null,Object? availableTags = null,Object? selectedTags = null,Object? currentSessionId = freezed,Object? currentSessionName = freezed,Object? messages = null,Object? isStreaming = null,Object? inConversation = null,Object? selectedMessageIndex = freezed,Object? selectedPlanner = null,Object? selectedExecutor = null,Object? showMetadata = null,Object? metadataPanelWidth = null,Object? selectedSessionIds = null,Object? memoryMode = null,}) {
  return _then(_self.copyWith(
sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<Session>,availableTags: null == availableTags ? _self.availableTags : availableTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,selectedTags: null == selectedTags ? _self.selectedTags : selectedTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,currentSessionId: freezed == currentSessionId ? _self.currentSessionId : currentSessionId // ignore: cast_nullable_to_non_nullable
as int?,currentSessionName: freezed == currentSessionName ? _self.currentSessionName : currentSessionName // ignore: cast_nullable_to_non_nullable
as String?,messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<ResponseMessage>,isStreaming: null == isStreaming ? _self.isStreaming : isStreaming // ignore: cast_nullable_to_non_nullable
as bool,inConversation: null == inConversation ? _self.inConversation : inConversation // ignore: cast_nullable_to_non_nullable
as bool,selectedMessageIndex: freezed == selectedMessageIndex ? _self.selectedMessageIndex : selectedMessageIndex // ignore: cast_nullable_to_non_nullable
as int?,selectedPlanner: null == selectedPlanner ? _self.selectedPlanner : selectedPlanner // ignore: cast_nullable_to_non_nullable
as String,selectedExecutor: null == selectedExecutor ? _self.selectedExecutor : selectedExecutor // ignore: cast_nullable_to_non_nullable
as String,showMetadata: null == showMetadata ? _self.showMetadata : showMetadata // ignore: cast_nullable_to_non_nullable
as bool,metadataPanelWidth: null == metadataPanelWidth ? _self.metadataPanelWidth : metadataPanelWidth // ignore: cast_nullable_to_non_nullable
as double,selectedSessionIds: null == selectedSessionIds ? _self.selectedSessionIds : selectedSessionIds // ignore: cast_nullable_to_non_nullable
as Set<int>,memoryMode: null == memoryMode ? _self.memoryMode : memoryMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatState].
extension ChatStatePatterns on ChatState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatState value)  $default,){
final _that = this;
switch (_that) {
case _ChatState():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatState value)?  $default,){
final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Session> sessions,  List<Tag> availableTags,  List<Tag> selectedTags,  int? currentSessionId,  String? currentSessionName,  List<ResponseMessage> messages,  bool isStreaming,  bool inConversation,  int? selectedMessageIndex,  String selectedPlanner,  String selectedExecutor,  bool showMetadata,  double metadataPanelWidth,  Set<int> selectedSessionIds,  String memoryMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that.sessions,_that.availableTags,_that.selectedTags,_that.currentSessionId,_that.currentSessionName,_that.messages,_that.isStreaming,_that.inConversation,_that.selectedMessageIndex,_that.selectedPlanner,_that.selectedExecutor,_that.showMetadata,_that.metadataPanelWidth,_that.selectedSessionIds,_that.memoryMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Session> sessions,  List<Tag> availableTags,  List<Tag> selectedTags,  int? currentSessionId,  String? currentSessionName,  List<ResponseMessage> messages,  bool isStreaming,  bool inConversation,  int? selectedMessageIndex,  String selectedPlanner,  String selectedExecutor,  bool showMetadata,  double metadataPanelWidth,  Set<int> selectedSessionIds,  String memoryMode)  $default,) {final _that = this;
switch (_that) {
case _ChatState():
return $default(_that.sessions,_that.availableTags,_that.selectedTags,_that.currentSessionId,_that.currentSessionName,_that.messages,_that.isStreaming,_that.inConversation,_that.selectedMessageIndex,_that.selectedPlanner,_that.selectedExecutor,_that.showMetadata,_that.metadataPanelWidth,_that.selectedSessionIds,_that.memoryMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Session> sessions,  List<Tag> availableTags,  List<Tag> selectedTags,  int? currentSessionId,  String? currentSessionName,  List<ResponseMessage> messages,  bool isStreaming,  bool inConversation,  int? selectedMessageIndex,  String selectedPlanner,  String selectedExecutor,  bool showMetadata,  double metadataPanelWidth,  Set<int> selectedSessionIds,  String memoryMode)?  $default,) {final _that = this;
switch (_that) {
case _ChatState() when $default != null:
return $default(_that.sessions,_that.availableTags,_that.selectedTags,_that.currentSessionId,_that.currentSessionName,_that.messages,_that.isStreaming,_that.inConversation,_that.selectedMessageIndex,_that.selectedPlanner,_that.selectedExecutor,_that.showMetadata,_that.metadataPanelWidth,_that.selectedSessionIds,_that.memoryMode);case _:
  return null;

}
}

}

/// @nodoc


class _ChatState implements ChatState {
  const _ChatState({final  List<Session> sessions = const [], final  List<Tag> availableTags = const [], final  List<Tag> selectedTags = const [], this.currentSessionId, this.currentSessionName, final  List<ResponseMessage> messages = const [], this.isStreaming = false, this.inConversation = false, this.selectedMessageIndex, this.selectedPlanner = 'llama3.1:latest', this.selectedExecutor = 'llama3.1:latest', this.showMetadata = true, this.metadataPanelWidth = 350.0, final  Set<int> selectedSessionIds = const {}, this.memoryMode = 'off'}): _sessions = sessions,_availableTags = availableTags,_selectedTags = selectedTags,_messages = messages,_selectedSessionIds = selectedSessionIds;
  

 final  List<Session> _sessions;
@override@JsonKey() List<Session> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}

 final  List<Tag> _availableTags;
@override@JsonKey() List<Tag> get availableTags {
  if (_availableTags is EqualUnmodifiableListView) return _availableTags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableTags);
}

 final  List<Tag> _selectedTags;
@override@JsonKey() List<Tag> get selectedTags {
  if (_selectedTags is EqualUnmodifiableListView) return _selectedTags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedTags);
}

@override final  int? currentSessionId;
@override final  String? currentSessionName;
 final  List<ResponseMessage> _messages;
@override@JsonKey() List<ResponseMessage> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

@override@JsonKey() final  bool isStreaming;
@override@JsonKey() final  bool inConversation;
@override final  int? selectedMessageIndex;
@override@JsonKey() final  String selectedPlanner;
@override@JsonKey() final  String selectedExecutor;
@override@JsonKey() final  bool showMetadata;
@override@JsonKey() final  double metadataPanelWidth;
 final  Set<int> _selectedSessionIds;
@override@JsonKey() Set<int> get selectedSessionIds {
  if (_selectedSessionIds is EqualUnmodifiableSetView) return _selectedSessionIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_selectedSessionIds);
}

@override@JsonKey() final  String memoryMode;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatStateCopyWith<_ChatState> get copyWith => __$ChatStateCopyWithImpl<_ChatState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatState&&const DeepCollectionEquality().equals(other._sessions, _sessions)&&const DeepCollectionEquality().equals(other._availableTags, _availableTags)&&const DeepCollectionEquality().equals(other._selectedTags, _selectedTags)&&(identical(other.currentSessionId, currentSessionId) || other.currentSessionId == currentSessionId)&&(identical(other.currentSessionName, currentSessionName) || other.currentSessionName == currentSessionName)&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.isStreaming, isStreaming) || other.isStreaming == isStreaming)&&(identical(other.inConversation, inConversation) || other.inConversation == inConversation)&&(identical(other.selectedMessageIndex, selectedMessageIndex) || other.selectedMessageIndex == selectedMessageIndex)&&(identical(other.selectedPlanner, selectedPlanner) || other.selectedPlanner == selectedPlanner)&&(identical(other.selectedExecutor, selectedExecutor) || other.selectedExecutor == selectedExecutor)&&(identical(other.showMetadata, showMetadata) || other.showMetadata == showMetadata)&&(identical(other.metadataPanelWidth, metadataPanelWidth) || other.metadataPanelWidth == metadataPanelWidth)&&const DeepCollectionEquality().equals(other._selectedSessionIds, _selectedSessionIds)&&(identical(other.memoryMode, memoryMode) || other.memoryMode == memoryMode));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_sessions),const DeepCollectionEquality().hash(_availableTags),const DeepCollectionEquality().hash(_selectedTags),currentSessionId,currentSessionName,const DeepCollectionEquality().hash(_messages),isStreaming,inConversation,selectedMessageIndex,selectedPlanner,selectedExecutor,showMetadata,metadataPanelWidth,const DeepCollectionEquality().hash(_selectedSessionIds),memoryMode);

@override
String toString() {
  return 'ChatState(sessions: $sessions, availableTags: $availableTags, selectedTags: $selectedTags, currentSessionId: $currentSessionId, currentSessionName: $currentSessionName, messages: $messages, isStreaming: $isStreaming, inConversation: $inConversation, selectedMessageIndex: $selectedMessageIndex, selectedPlanner: $selectedPlanner, selectedExecutor: $selectedExecutor, showMetadata: $showMetadata, metadataPanelWidth: $metadataPanelWidth, selectedSessionIds: $selectedSessionIds, memoryMode: $memoryMode)';
}


}

/// @nodoc
abstract mixin class _$ChatStateCopyWith<$Res> implements $ChatStateCopyWith<$Res> {
  factory _$ChatStateCopyWith(_ChatState value, $Res Function(_ChatState) _then) = __$ChatStateCopyWithImpl;
@override @useResult
$Res call({
 List<Session> sessions, List<Tag> availableTags, List<Tag> selectedTags, int? currentSessionId, String? currentSessionName, List<ResponseMessage> messages, bool isStreaming, bool inConversation, int? selectedMessageIndex, String selectedPlanner, String selectedExecutor, bool showMetadata, double metadataPanelWidth, Set<int> selectedSessionIds, String memoryMode
});




}
/// @nodoc
class __$ChatStateCopyWithImpl<$Res>
    implements _$ChatStateCopyWith<$Res> {
  __$ChatStateCopyWithImpl(this._self, this._then);

  final _ChatState _self;
  final $Res Function(_ChatState) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessions = null,Object? availableTags = null,Object? selectedTags = null,Object? currentSessionId = freezed,Object? currentSessionName = freezed,Object? messages = null,Object? isStreaming = null,Object? inConversation = null,Object? selectedMessageIndex = freezed,Object? selectedPlanner = null,Object? selectedExecutor = null,Object? showMetadata = null,Object? metadataPanelWidth = null,Object? selectedSessionIds = null,Object? memoryMode = null,}) {
  return _then(_ChatState(
sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<Session>,availableTags: null == availableTags ? _self._availableTags : availableTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,selectedTags: null == selectedTags ? _self._selectedTags : selectedTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,currentSessionId: freezed == currentSessionId ? _self.currentSessionId : currentSessionId // ignore: cast_nullable_to_non_nullable
as int?,currentSessionName: freezed == currentSessionName ? _self.currentSessionName : currentSessionName // ignore: cast_nullable_to_non_nullable
as String?,messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<ResponseMessage>,isStreaming: null == isStreaming ? _self.isStreaming : isStreaming // ignore: cast_nullable_to_non_nullable
as bool,inConversation: null == inConversation ? _self.inConversation : inConversation // ignore: cast_nullable_to_non_nullable
as bool,selectedMessageIndex: freezed == selectedMessageIndex ? _self.selectedMessageIndex : selectedMessageIndex // ignore: cast_nullable_to_non_nullable
as int?,selectedPlanner: null == selectedPlanner ? _self.selectedPlanner : selectedPlanner // ignore: cast_nullable_to_non_nullable
as String,selectedExecutor: null == selectedExecutor ? _self.selectedExecutor : selectedExecutor // ignore: cast_nullable_to_non_nullable
as String,showMetadata: null == showMetadata ? _self.showMetadata : showMetadata // ignore: cast_nullable_to_non_nullable
as bool,metadataPanelWidth: null == metadataPanelWidth ? _self.metadataPanelWidth : metadataPanelWidth // ignore: cast_nullable_to_non_nullable
as double,selectedSessionIds: null == selectedSessionIds ? _self._selectedSessionIds : selectedSessionIds // ignore: cast_nullable_to_non_nullable
as Set<int>,memoryMode: null == memoryMode ? _self.memoryMode : memoryMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
