import 'package:sogen/ctypes.dart' show uint32;
import 'package:sogen/windows.dart' show apiCall, createApplication;

main() {
  final app = createApplication(r'c:/test-sample.exe', emulationRoot: './root');

  final onSleep = apiCall(
    cc: .stdcall,
    params: const [uint32],
    cb: (call, params) {
      final milliseconds = params[0];
      print('Sleep($milliseconds)');
    },
  );

  app.hooks.apis['Sleep'] = onSleep;

  app.start();
}
