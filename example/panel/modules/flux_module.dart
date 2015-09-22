library w_module.example.panel.modules.flux_module;

import 'dart:math';

import 'package:w_flux/w_flux.dart';
import 'package:react/react.dart' as react;
import 'package:w_module/w_module.dart';

class FluxModule extends Module {
  final String name = 'FluxModule';

  FluxActions _actions;
  FluxStore _stores;

  FluxComponents _components;
  FluxComponents get components => _components;

  FluxModule() {
    _actions = new FluxActions();
    _stores = new FluxStore(_actions);
    _components = new FluxComponents(_actions, _stores);
  }
}

class FluxComponents implements ModuleComponents {
  FluxActions _actions;
  FluxStore _stores;

  FluxComponents(this._actions, this._stores);

  content() => MyFluxComponent({'actions': _actions, 'store': _stores});
}

class FluxActions {
  final Action changeBackgroundColor = new Action();
}

class FluxStore extends Store {
  /// Public data
  String _backgroundColor = 'gray';
  String get backgroundColor => _backgroundColor;

  /// Internals
  FluxActions _actions;

  FluxStore(FluxActions this._actions) {
    triggerOnAction(_actions.changeBackgroundColor, _changeBackgroundColor);
  }

  _changeBackgroundColor(_) {
    // generate a random hex color string
    _backgroundColor =
        '#' + (new Random().nextDouble() * 16777215).floor().toRadixString(16);
  }
}

var MyFluxComponent = react.registerComponent(() => new _MyFluxComponent());

class _MyFluxComponent extends FluxComponent<FluxActions, FluxStore> {
  render() {
    return react.div({
      'style': {
        'padding': '50px',
        'backgroundColor': store.backgroundColor,
        'color': 'white'
      }
    }, [
      'This module uses a flux pattern to change its background color.',
      react.button({
        'style': {'padding': '10px', 'margin': '10px'},
        'onClick': actions.changeBackgroundColor
      }, 'Random Background Color')
    ]);
  }
}
