import 'package:flutter/foundation.dart';

/// Lets a controller finish a request after it was replaced on an account switch,
/// without notifying listeners that are already gone.
mixin DisposeSafeNotifier on ChangeNotifier {
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
