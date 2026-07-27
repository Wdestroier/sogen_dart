import 'dart:collection';

import 'ctypes.dart';
import 'generated/types.g.dart';

typedef ApiHookCallback = dynamic Function(ApiCall call, List<dynamic> params);

final class ApiCall {
  ApiCall({
    required this.module,
    required this.name,
    required this.address,
    required this.returnAddress,
    this.returnValue = 0,
  });

  final String module;
  final String name;
  final int address;
  final int returnAddress;
  int returnValue;
}

final class ApiHook {
  ApiHook._({
    required this.callingConvention,
    required List<CType> parameters,
    required this.returnType,
    required this._callback,
  }) : parameters = List<CType>.unmodifiable(parameters);

  final CallingConvention callingConvention;
  final List<CType> parameters;
  final CType? returnType;
  final ApiHookCallback _callback;

  List<dynamic> decodeParameters(List<int> rawParameters) {
    if (rawParameters.length != parameters.length) {
      throw StateError(
        'Expected ${parameters.length} API parameters, '
        'received ${rawParameters.length}',
      );
    }

    return UnmodifiableListView<dynamic>([
      for (var index in Iterable<int>.generate(parameters.length))
        parameters[index].decode(rawParameters[index]),
    ]);
  }

  ApiContinuation invoke(ApiCall call, List<int> rawParameters) {
    final result = Function.apply(_callback, [
      call,
      decodeParameters(rawParameters),
    ]);
    return switch (result) {
      null => ApiContinuation.runOriginal,
      false => ApiContinuation.runOriginal,
      true => ApiContinuation.intercept,
      final ApiContinuation value => value,
      _ => throw ArgumentError.value(
        result,
        'callback result',
        'Expected ApiContinuation, bool, or null',
      ),
    };
  }
}

ApiHook createApiHook({
  required CallingConvention cc,
  List<CType> params = const [],
  CType? restype,
  required ApiHookCallback cb,
}) => ApiHook._(
  callingConvention: cc,
  parameters: params,
  returnType: restype,
  callback: cb,
);

ApiHook apiCall({
  required CallingConvention cc,
  List<CType> params = const [],
  CType? restype,
  required ApiHookCallback cb,
}) => createApiHook(cc: cc, params: params, restype: restype, cb: cb);
