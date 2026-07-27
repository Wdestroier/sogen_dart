import 'package:sogen/ctypes.dart' show bool32, int8, uint32;
import 'package:sogen/windows.dart'
    show ApiCall, ApiContinuation, ApiHook, apiCall;
import 'package:test/test.dart';

void main() {
  test('apiCall decodes heterogeneous descriptors', () {
    late List<dynamic> received;
    final hook = apiCall(
      cc: .stdcall,
      params: [uint32, int8, bool32],
      cb: (call, params) {
        received = params;
      },
    );

    final continuation = hook.invoke(
      ApiCall(
        module: 'kernel32.dll',
        name: 'Example',
        address: 0x1000,
        returnAddress: 0x2000,
      ),
      [0x100000001, 0xff, 2],
    );

    expect(received, [1, -1, true]);
    expect(() => received.add(4), throwsUnsupportedError);
    expect(continuation, ApiContinuation.runOriginal);
  });

  test('apiCall coerces bool and continuation results', () {
    ApiHook hookFor(result) =>
        apiCall(cc: .fastcall, cb: (call, params) => result);

    final call = ApiCall(
      module: 'sample.dll',
      name: 'Target',
      address: 1,
      returnAddress: 2,
    );
    expect(hookFor(false).invoke(call, const []), ApiContinuation.runOriginal);
    expect(hookFor(true).invoke(call, const []), ApiContinuation.intercept);
    expect(
      hookFor(ApiContinuation.skip).invoke(call, const []),
      ApiContinuation.intercept,
    );
  });

  test('apiCall rejects wrong arity and callback return type', () {
    final arityHook = apiCall(
      cc: .stdcall,
      params: [uint32],
      cb: (call, params) {},
    );
    expect(
      () => arityHook.invoke(
        ApiCall(module: 'a', name: 'b', address: 0, returnAddress: 0),
        const [],
      ),
      throwsStateError,
    );

    final resultHook = apiCall(cc: .stdcall, cb: (call, params) => 'invalid');
    expect(
      () => resultHook.invoke(
        ApiCall(module: 'a', name: 'b', address: 0, returnAddress: 0),
        const [],
      ),
      throwsArgumentError,
    );
  });
}
