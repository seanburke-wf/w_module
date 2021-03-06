// Copyright 2017 Workiva Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

library w_module.src.lifecycle_module;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart' show protected, required;
import 'package:w_common/disposable.dart';

import 'package:w_module/src/simple_module.dart';

/// Possible states a [LifecycleModule] may occupy.
enum LifecycleState {
  /// The module has been instantiated.
  instantiated,

  /// The module is in the process of being loaded.
  loading,

  /// The module has been loaded.
  loaded,

  /// The module is in the process of being suspended.
  suspending,

  /// The module has been suspended.
  suspended,

  /// The module is in the process of resuming from the suspended state.
  resuming,

  /// The module is in the process of unloading.
  unloading,

  /// The module has been unloaded.
  unloaded
}

/// Intended to be extended by most base module classes in order to provide a
/// unified lifecycle API.
abstract class LifecycleModule extends SimpleModule
    implements DisposableManagerV3 {
  List<LifecycleModule> _childModules = [];
  StreamController<LifecycleModule> _didLoadChildModuleController;
  StreamController<LifecycleModule> _didLoadController;
  StreamController<LifecycleModule> _didResumeController;
  StreamController<LifecycleModule> _didSuspendController;
  StreamController<LifecycleModule> _didUnloadChildModuleController;
  final Map<LifecycleModule, StreamSubscription<LifecycleModule>>
      _didUnloadChildModuleSubscriptions = {};
  StreamController<LifecycleModule> _didUnloadController;
  final Disposable _disposableProxy = new Disposable();
  Logger _logger;
  String _name = 'Module';
  LifecycleState _previousState;
  LifecycleState _state = LifecycleState.instantiated;
  Completer<Null> _transition;
  StreamController<LifecycleModule> _willLoadChildModuleController;
  StreamController<LifecycleModule> _willLoadController;
  StreamController<LifecycleModule> _willResumeController;
  StreamController<LifecycleModule> _willSuspendController;
  StreamController<LifecycleModule> _willUnloadChildModuleController;
  final Map<LifecycleModule, StreamSubscription<LifecycleModule>>
      _willUnloadChildModuleSubscriptions = {};
  StreamController<LifecycleModule> _willUnloadController;

  // constructor necessary to init load / unload state stream
  LifecycleModule() {
    // The didUnload event must be emitted after disposal which requires that
    // the stream controller must be disposed of manually at the end of the
    // unload transition.
    _didUnloadController = new StreamController<LifecycleModule>.broadcast();

    [
      _willLoadController = new StreamController<LifecycleModule>.broadcast(),
      _didLoadController = new StreamController<LifecycleModule>.broadcast(),
      _willUnloadController = new StreamController<LifecycleModule>.broadcast(),
      _willLoadChildModuleController =
          new StreamController<LifecycleModule>.broadcast(),
      _didLoadChildModuleController =
          new StreamController<LifecycleModule>.broadcast(),
      _willUnloadChildModuleController =
          new StreamController<LifecycleModule>.broadcast(),
      _didUnloadChildModuleController =
          new StreamController<LifecycleModule>.broadcast(),
      _willSuspendController =
          new StreamController<LifecycleModule>.broadcast(),
      _didSuspendController = new StreamController<LifecycleModule>.broadcast(),
      _willResumeController = new StreamController<LifecycleModule>.broadcast(),
      _didResumeController = new StreamController<LifecycleModule>.broadcast()
    ].forEach(manageStreamController);

    _logger = new Logger('w_module');
  }

  /// Name of the module for identification in exceptions and debug messages.
  // ignore: unnecessary_getters_setters
  String get name => _name;

  /// Deprecated: the module name should be defined by overriding the getter in
  /// a subclass and it should not be mutable.
  @deprecated
  // ignore: unnecessary_getters_setters
  set name(String newName) {
    _name = newName;
  }

  /// List of child components so that lifecycle can iterate over them as needed
  Iterable<LifecycleModule> get childModules => _childModules;

  /// The [LifecycleModule] was loaded.
  ///
  /// Any error or exception thrown during the [LifecycleModule]'s
  /// [onLoad] call will be emitted.
  Stream<LifecycleModule> get didLoad => _didLoadController.stream;

  /// A child [LifecycleModule] was loaded.
  ///
  /// Any error or exception thrown during the child [LifecycleModule]'s
  /// [onLoad] call will be emitted.
  ///
  /// Any error or exception thrown during the parent [LifecycleModule]'s
  /// [onDidLoadChildModule] call will be emitted.
  Stream<LifecycleModule> get didLoadChildModule =>
      _didLoadChildModuleController.stream;

  /// The [LifecycleModule] was resumed.
  ///
  /// Any error or exception thrown during the child [LifecycleModule]'s
  /// [resume] call will be emitted.
  ///
  /// Any error or exception thrown during the [LifecycleModule]'s
  /// [onResume] call will be emitted.
  Stream<LifecycleModule> get didResume => _didResumeController.stream;

  /// The [LifecycleModule] was suspended.
  ///
  /// Any error or exception thrown during the child [LifecycleModule]'s
  /// [suspend] call will be emitted.
  ///
  /// Any error or exception thrown during the [LifecycleModule]'s
  /// [onSuspend] call will be emitted.
  Stream<LifecycleModule> get didSuspend => _didSuspendController.stream;

  /// The [LifecycleModule] was unloaded.
  ///
  /// Any error or exception thrown during the child [LifecycleModule]'s
  /// [unload] call will be emitted.
  ///
  /// Any error or exception thrown during the [LifecycleModule]'s
  /// [onUnload] call will be emitted.
  Stream<LifecycleModule> get didUnload => _didUnloadController.stream;

  /// A child [LifecycleModule] was unloaded.
  ///
  /// Any error or exception thrown during the child [LifecycleModule]'s
  /// [onUnload] call will be emitted.
  ///
  /// Any error or exception thrown during the parent [LifecycleModule]'s
  /// [onDidUnloadChildModule] call will be emitted.
  Stream<LifecycleModule> get didUnloadChildModule =>
      _didUnloadChildModuleController.stream;

  /// A child [LifecycleModule] is about to be loaded.
  ///
  /// Any error or exception thrown during the parent [LifecycleModule]'s
  /// [onDidLoadChildModule] call will be emitted.
  Stream<LifecycleModule> get willLoadChildModule =>
      _willLoadChildModuleController.stream;

  /// A child [LifecycleModule] is about to be unloaded.
  ///
  /// Any error or exception thrown during the parent [LifecycleModule]'s
  /// [onDidUnloadChildModule] call will be emitted.
  Stream<LifecycleModule> get willUnloadChildModule =>
      _willUnloadChildModuleController.stream;

  /// The [LifecycleModule] is about to be resumed.
  Stream<LifecycleModule> get willResume => _willResumeController.stream;

  /// The [LifecycleModule] is about to be unloaded.
  Stream<LifecycleModule> get willUnload => _willUnloadController.stream;

  /// The [LifecycleModule] is about to be loaded.
  Stream<LifecycleModule> get willLoad => _willLoadController.stream;

  /// The [LifecycleModule] is about to be suspended.
  Stream<LifecycleModule> get willSuspend => _willSuspendController.stream;

  @override
  Future<T> awaitBeforeDispose<T>(Future<T> future) => _disposableProxy
      .awaitBeforeDispose(future);

  @override
  Future<T> getManagedDelayedFuture<T>(Duration duration, T callback()) =>
      _disposableProxy.getManagedDelayedFuture(duration, callback);

  @override
  Timer getManagedPeriodicTimer(
          Duration duration, void callback(Timer timer)) =>
      _disposableProxy.getManagedPeriodicTimer(duration, callback);

  @override
  Timer getManagedTimer(Duration duration, void callback()) =>
      _disposableProxy.getManagedTimer(duration, callback);

  /// Whether the module is currently instantiated.
  bool get isInstantiated => _state == LifecycleState.instantiated;

  /// Whether the module is currently loaded.
  bool get isLoaded => _state == LifecycleState.loaded;

  /// Whether the module is currently loading.
  bool get isLoading => _state == LifecycleState.loading;

  /// Whether the module is currently resuming.
  bool get isResuming => _state == LifecycleState.resuming;

  /// Whether the module is currently suspended.
  bool get isSuspended => _state == LifecycleState.suspended;

  /// Whether the module is currently suspending.
  bool get isSuspending => _state == LifecycleState.suspending;

  /// Whether the module is currently unloaded.
  bool get isUnloaded => _state == LifecycleState.unloaded;

  /// Whether the module is currently unloading.
  bool get isUnloading => _state == LifecycleState.unloading;

  //--------------------------------------------------------
  // Public methods that can be used directly to trigger
  // module lifecycle / check current lifecycle state
  //--------------------------------------------------------

  /// Public method to trigger the loading of a Module.
  ///
  /// Calls the onLoad() method, which can be implemented on a Module.
  /// Executes the willLoad and didLoad event streams.
  ///
  /// Initiates the loading process when the module is in the instantiated
  /// state. If the module is in the loaded or loading state a warning is logged
  /// and the method is a noop. If the module is in any other state, a
  /// StateError is thrown.
  ///
  /// If an [Exception] is thrown during the call to [onLoad] it will be emitted
  /// on the [didLoad] lifecycle stream. The returned [Future] will also resolve
  /// with this exception.
  ///
  /// Note that [LifecycleModule] only supports one load/unload cycle. If [load]
  /// is called after a module has been unloaded, a [StateError] is thrown.
  Future<Null> load() {
    if (isLoading || isLoaded) {
      return _buildNoopResponse(
          isTransitioning: isLoading,
          methodName: 'load',
          currentState:
              isLoading ? LifecycleState.loading : LifecycleState.loaded);
    }

    if (!isInstantiated) {
      return _buildIllegalTransitionResponse(
          reason: 'A module can only be loaded once.');
    }

    _state = LifecycleState.loading;
    _transition = new Completer<Null>();

    _load().then(_transition.complete).catchError(_transition.completeError);

    return _transition.future;
  }

  /// Public method to async load a child module and register it
  /// for lifecycle management.
  ///
  /// If an [Exception] is thrown during the call to the parent
  /// [onWillLoadChildModule] it will be emitted on the [willLoadChildModule]
  /// lifecycle stream. The returned [Future] will also resolve with this
  /// exception.
  ///
  /// If an [Exception] is thrown during the call to the child [onLoad] it will
  /// be emitted on the [didLoadChildModule] lifecycle stream. The returned
  /// [Future] will also resolve with this exception.
  ///
  /// If an [Exception] is thrown during the call to the parent
  /// [onDidLoadChildModule] it will be emitted on the [didLoadChildModule]
  /// lifecycle stream. The returned [Future] will also resolve with this
  /// exception.
  ///
  /// Attempting to load a child module after a module has been unloaded will
  /// throw a [StateError].
  @protected
  Future<Null> loadChildModule(LifecycleModule childModule) {
    if (_childModules.contains(childModule)) {
      return new Future.value(null);
    }

    if (isUnloaded || isUnloading) {
      var stateLabel = isUnloaded ? 'unloaded' : 'unloading';
      return new Future.error(new StateError(
          'Cannot load child module when module is $stateLabel'));
    }

    final completer = new Completer<Null>();
    onWillLoadChildModule(childModule).then((LifecycleModule _) async {
      _willLoadChildModuleController.add(childModule);

      _didUnloadChildModuleSubscriptions[childModule] = childModule.didUnload
          .listen(_onChildModuleDidUnload,
              onError: _didUnloadChildModuleController.addError);

      _willUnloadChildModuleSubscriptions[childModule] = childModule.willUnload
          .listen(_onChildModuleWillUnload,
              onError: _willUnloadChildModuleController.addError);

      try {
        await childModule.load();
        await onDidLoadChildModule(childModule);
        _childModules.add(childModule);
        _didLoadChildModuleController.add(childModule);
        completer.complete();
      } catch (error, stackTrace) {
        await _didUnloadChildModuleSubscriptions[childModule]?.cancel();
        await _willUnloadChildModuleSubscriptions[childModule]?.cancel();
        _didLoadChildModuleController.addError(error, stackTrace);
        completer.completeError(error, stackTrace);
      }
    }).catchError((Object error, StackTrace stackTrace) {
      _willLoadChildModuleController.addError(error, stackTrace);
      completer.completeError(error, stackTrace);
    });

    return completer.future;
  }

  /// Ensures a given [Completer] is completed when the module is unloaded.
  @override
  Completer<T> manageCompleter<T>(Completer<T> completer) => _disposableProxy
      .manageCompleter(completer);

  /// Ensures a given [Disposable] is disposed when the module is unloaded.
  @override
  void manageDisposable(Disposable disposable) =>
      _disposableProxy.manageDisposable(disposable);

  /// Ensures a given [Disposer] callback is called when the module is unloaded.
  @override
  void manageDisposer(Disposer disposer) =>
      _disposableProxy.manageDisposer(disposer);

  /// Ensures a given [StreamController] is closed when the module is unloaded.
  @override
  void manageStreamController(StreamController controller) =>
      _disposableProxy.manageStreamController(controller);

  /// Ensures a given [StreamSubscription] is cancelled when the module is
  /// unloaded.
  @override
  void manageStreamSubscription(StreamSubscription subscription) =>
      _disposableProxy.manageStreamSubscription(subscription);

  /// Public method to suspend the module.
  ///
  /// Suspend indicates to the module that it should go into a low-activity
  /// state. For example, by disconnecting from backend services and unloading
  /// heavy data structures.
  ///
  /// Initiates the suspend process when the module is in the loaded state. If
  /// the module is in the suspended or suspending state a warning is logged and
  /// the method is a noop. If the module is in any other state, a StateError is
  /// thrown.
  ///
  /// The [Future] values of all children [suspend] calls will be awaited. The
  /// first child to return an error value will emit the error on the
  /// [didSuspend] lifecycle stream. The returned [Future] will also resolve
  /// with this exception.
  ///
  /// If an [Exception] is thrown during the call to [onSuspend] it will be
  /// emitted on the [didSuspend] lifecycle stream. The returned [Future] will
  /// also resolve with this exception.
  ///
  /// If an error or exception is thrown during the call to the parent
  /// [onSuspend] lifecycle method it will be emitted on the [didSuspend]
  /// lifecycle stream. The error will also be returned by [suspend].
  Future<Null> suspend() {
    if (isSuspended || isSuspending) {
      return _buildNoopResponse(
          isTransitioning: isSuspending,
          methodName: 'suspend',
          currentState: isSuspending
              ? LifecycleState.suspending
              : LifecycleState.suspended);
    }

    if (!(isLoaded || isLoading || isResuming)) {
      return _buildIllegalTransitionResponse(
          targetState: LifecycleState.suspended,
          allowedStates: [
            LifecycleState.loaded,
            LifecycleState.loading,
            LifecycleState.resuming
          ]);
    }
    var previousTransition = _transition?.future;
    _transition = new Completer<Null>();
    _state = LifecycleState.suspending;

    _suspend(previousTransition)
        .then(_transition.complete)
        .catchError(_transition.completeError);
    return _transition.future;
  }

  /// Public method to resume the module.
  ///
  /// This should put the module back into its normal state after the module
  /// was suspended.
  ///
  /// Only initiates the resume process when the module is in the suspended
  /// state. If the module is in the resuming state a warning is logged and the
  /// method is a noop. If the module is in any other state, a StateError is
  /// thrown.
  ///
  /// The [Future] values of all children [resume] calls will be awaited. The
  /// first child to return an error value will emit the error on the
  /// [didResume] lifecycle stream. The returned [Future] will also resolve with
  /// this exception.
  ///
  /// If an [Exception] is thrown during the call to [onResume] it will be
  /// emitted on the [didResume] lifecycle stream. The returned [Future] will
  /// also resolve with this exception.
  ///
  /// If an error or exception is thrown during the call to the parent
  /// [onResume] lifecycle method it will be emitted on the [didResume]
  /// lifecycle stream. The error will also be returned by [resume].
  Future<Null> resume() {
    if (isLoaded || isResuming) {
      return _buildNoopResponse(
          isTransitioning: isResuming,
          methodName: 'resume',
          currentState:
              isResuming ? LifecycleState.resuming : LifecycleState.loaded);
    }

    if (!(isSuspended || isSuspending)) {
      return _buildIllegalTransitionResponse(
          targetState: LifecycleState.loaded,
          allowedStates: [LifecycleState.suspended, LifecycleState.suspending]);
    }

    var pendingTransition = _transition?.future;
    _state = LifecycleState.resuming;
    _transition = new Completer<Null>();

    _resume(pendingTransition)
        .then(_transition.complete)
        .catchError(_transition.completeError);

    return _transition.future;
  }

  /// Public method to query the unloadable state of the Module.
  ///
  /// Calls the onShouldUnload() method, which can be implemented on a Module.
  /// onShouldUnload is also called on all registered child modules.
  ShouldUnloadResult shouldUnload() {
    // collect results from all child modules and self
    List<ShouldUnloadResult> shouldUnloads = [];
    for (var child in _childModules) {
      shouldUnloads.add(child.shouldUnload());
    }
    shouldUnloads.add(onShouldUnload());

    // aggregate into 1 combined result
    ShouldUnloadResult finalResult = new ShouldUnloadResult();
    for (var result in shouldUnloads) {
      if (!result.shouldUnload) {
        finalResult.shouldUnload = false;
        finalResult.messages.addAll(result.messages);
      }
    }
    return finalResult;
  }

  /// Public method to trigger the Module unload cycle.
  ///
  /// Calls shouldUnload(), and, if that completes successfully, continues to
  /// call onUnload() on the module and all registered child modules. If
  /// unloading is rejected, this method will complete with an error. The rejection
  /// error will not be added to the [didUnload] lifecycle event stream.
  ///
  /// Initiates the unload process when the module is in the loaded or suspended
  /// state. If the module is in the unloading or unloaded state a warning is
  /// logged and the method is a noop. If the module is in any other state, a
  /// StateError is thrown.
  ///
  /// The [Future] values of all children [unload] calls will be awaited. The
  /// first child to return an error value will emit the error on the
  /// [didUnload] lifecycle stream. The returned [Future] will also resolve with
  /// this exception.
  ///
  /// If an [Exception] is thrown during the call to [onUnload] it will be
  /// emitted on the [didUnload] lifecycle stream. The returned [Future] will
  /// also resolve with this exception.
  ///
  /// If an error or exception is thrown during the call to the parent
  /// [onUnload] lifecycle method it will be emitted on the [didUnload]
  /// lifecycle stream. The error will also be returned by [unload].
  Future<Null> unload() {
    if (isUnloaded || isUnloading) {
      return _buildNoopResponse(
          isTransitioning: isUnloading,
          methodName: 'unload',
          currentState:
              isUnloading ? LifecycleState.unloading : LifecycleState.unloaded);
    }

    if (!(isLoaded || isLoading || isResuming || isSuspended || isSuspending)) {
      return _buildIllegalTransitionResponse(
          targetState: LifecycleState.unloaded,
          allowedStates: [
            LifecycleState.loaded,
            LifecycleState.loading,
            LifecycleState.resuming,
            LifecycleState.suspended,
            LifecycleState.suspending
          ]);
    }

    var pendingTransition = _transition?.future;
    _previousState = _state;
    _state = LifecycleState.unloading;
    _transition = new Completer<Null>();

    _unload(pendingTransition)
        .then(_transition.complete)
        .catchError(_transition.completeError);

    return _transition.future;
  }

  //--------------------------------------------------------
  // Methods that can be optionally implemented by subclasses
  // to execute code during certain phases of the module
  // lifecycle
  //--------------------------------------------------------

  /// Custom logic to be executed during load.
  ///
  /// Initial data queries and interactions with the server can be triggered
  /// here.  Returns a future with no payload that completes when the module has
  /// finished loading.
  @protected
  Future onLoad() async {}

  /// Custom logic to be executed when a child module is to be loaded.
  @protected
  Future<Null> onWillLoadChildModule(LifecycleModule module) async {}

  /// Custom logic to be executed when a child module has been loaded.
  @protected
  Future<Null> onDidLoadChildModule(LifecycleModule module) async {}

  /// Custom logic to be executed when a child module is to be unloaded.
  @protected
  Future<Null> onWillUnloadChildModule(LifecycleModule module) async {}

  /// Custom logic to be executed when a child module has been unloaded.
  @protected
  Future<Null> onDidUnloadChildModule(LifecycleModule module) async {}

  /// Custom logic to be executed during suspend.
  ///
  /// Server connections can be dropped and large data structures unloaded here.
  /// Nothing should be done here that cannot be undone in [onResume].
  @protected
  Future<Null> onSuspend() async {}

  /// Custom logic to be executed during resume.
  ///
  /// Any changes made in [onSuspend] can be reverted here.
  @protected
  Future<Null> onResume() async {}

  /// Custom logic to be executed during shouldUnload (consequently also in unload).
  ///
  /// Returns a ShouldUnloadResult.
  /// [ShouldUnloadResult.shouldUnload == true] indicates that the module is safe to unload.
  /// [ShouldUnloadResult.shouldUnload == false] indicates that the module should not be unloaded.
  /// In this case, ShouldUnloadResult.messages contains a list of string messages indicating
  /// why unload was rejected.
  @protected
  ShouldUnloadResult onShouldUnload() {
    return new ShouldUnloadResult();
  }

  /// Custom logic to be executed during unload.
  ///
  /// Called on unload if shouldUnload completes with true. This can be used for
  /// cleanup. Returns a future with no payload that completes when the module
  /// has finished unloading.
  @protected
  Future<Null> onUnload() async {}

  /// Returns a new [Future] error with a constructed reason.
  Future<Null> _buildIllegalTransitionResponse(
      {LifecycleState targetState,
      Iterable<LifecycleState> allowedStates,
      String reason}) {
    reason = reason ??
        'Only a module in the '
        '${allowedStates.map(_readableStateName).join(", ")} states can '
        'transition to ${_readableStateName(targetState)}';
    return new Future.error(new StateError(
        'Transitioning from $_state to $targetState is not allowed. $reason'));
  }

  Future<Null> _buildNoopResponse(
      {@required String methodName,
      @required LifecycleState currentState,
      @required isTransitioning}) {
    _logger.warning('.$methodName() was called while Module "$name" is already '
        '${_readableStateName(currentState)}; this is a no-op. Check for any '
        'unnecessary calls to .$methodName().');

    return _transition?.future ?? new Future.value(null);
  }

  Future<Null> _load() async {
    try {
      _willLoadController.add(this);
      await onLoad();
      if (_state == LifecycleState.loading) {
        _state = LifecycleState.loaded;
        _transition = null;
      }
      _didLoadController.add(this);
    } catch (error, stackTrace) {
      _didLoadController.addError(error, stackTrace);
      rethrow;
    }
  }

  /// Handles a child [LifecycleModule]'s [didUnload] event.
  Future<Null> _onChildModuleDidUnload(LifecycleModule module) async {
    try {
      await onDidUnloadChildModule(module);
      _didUnloadChildModuleController.add(module);
      await _didUnloadChildModuleSubscriptions.remove(module).cancel();
    } catch (error, stackTrace) {
      _didUnloadChildModuleController.addError(error, stackTrace);
    }
  }

  /// Handles a child [LifecycleModule]'s [willUnload] event.
  Future<Null> _onChildModuleWillUnload(LifecycleModule module) async {
    try {
      await onWillUnloadChildModule(module);
      _willUnloadChildModuleController.add(module);
      _childModules.remove(module);
      await _willUnloadChildModuleSubscriptions.remove(module).cancel();
    } catch (error, stackTrace) {
      _willUnloadChildModuleController.addError(error, stackTrace);
    }
  }

  /// Obtains the value of a [LifecycleState] enumeration.
  String _readableStateName(LifecycleState state) => '$state'.split('.')[1];

  Future<Null> _resume(Future<Null> pendingTransition) async {
    try {
      if (pendingTransition != null) {
        await pendingTransition;
      }
      _willResumeController.add(this);
      List<Future<Null>> childResumeFutures = <Future<Null>>[];
      for (var child in _childModules.toList()) {
        childResumeFutures.add(child.resume());
      }
      await Future.wait(childResumeFutures);
      await onResume();
      if (_state == LifecycleState.resuming) {
        _state = LifecycleState.loaded;
        _transition = null;
      }
      _didResumeController.add(this);
    } catch (error, stackTrace) {
      _didResumeController.addError(error, stackTrace);
      rethrow;
    }
  }

  Future<Null> _suspend(Future<Null> pendingTransition) async {
    try {
      if (pendingTransition != null) {
        await pendingTransition;
      }
      _willSuspendController.add(this);
      List<Future<Null>> childSuspendFutures = <Future<Null>>[];
      for (var child in _childModules.toList()) {
        childSuspendFutures.add(child.suspend());
      }
      await Future.wait(childSuspendFutures);
      await onSuspend();
      if (_state == LifecycleState.suspending) {
        _state = LifecycleState.suspended;
        _transition = null;
      }
      _didSuspendController.add(this);
    } catch (error, stackTrace) {
      _didSuspendController.addError(error, stackTrace);
      rethrow;
    }
  }

  Future<Null> _unload(Future<Null> pendingTransition) async {
    try {
      if (pendingTransition != null) {
        await pendingTransition;
      }

      ShouldUnloadResult shouldUnloadResult = shouldUnload();
      if (!shouldUnloadResult.shouldUnload) {
        _state = _previousState;
        _previousState = null;
        _transition = null;
        // reject with shouldUnload messages
        throw new ModuleUnloadCanceledException(
            shouldUnloadResult.messagesAsString());
      }
      _willUnloadController.add(this);
      List<Future<Null>> childUnloadFutures = <Future<Null>>[];
      for (var child in _childModules.toList()) {
        childUnloadFutures.add(child.unload());
      }
      _childModules.clear();
      await Future.wait(childUnloadFutures);
      await onUnload();
      await _disposableProxy.dispose();
      if (_state == LifecycleState.unloading) {
        _state = LifecycleState.unloaded;
        _previousState = null;
        _transition = null;
      }
      _didUnloadController.add(this);
      await _didUnloadController.close();
    } on ModuleUnloadCanceledException catch (error, _) {
      rethrow;
    } catch (error, stackTrace) {
      _didUnloadController.addError(error, stackTrace);
      await _didUnloadController.close();
      rethrow;
    }
  }
}

/// Exception thrown when unload fails.
class ModuleUnloadCanceledException implements Exception {
  String message;

  ModuleUnloadCanceledException(this.message);
}

/// A set of messages returned from the hierarchical application of shouldUnload
class ShouldUnloadResult {
  bool shouldUnload;
  List<String> messages;

  ShouldUnloadResult([this.shouldUnload = true, String message]) {
    messages = [];
    if (message != null) {
      messages.add(message);
    }
  }

  bool call() => shouldUnload;

  String messagesAsString() {
    return messages.join('\n');
  }
}
