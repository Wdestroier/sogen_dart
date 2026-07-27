@Tags(<String>['native', 'windowsGuest', 'unicorn'])
library;

import 'dart:io';

import 'package:sogen/sogen.dart' as root;
import 'package:sogen/windows.dart' as win;
import 'package:test/test.dart';

void main() {
  final exampleRoot = Directory('example/root').absolute;
  final registry = Directory('${exampleRoot.path}/registry').absolute;
  final sample = File('${exampleRoot.path}/filesys/c/test-sample.exe').absolute;
  final unavailable = <String>[
    if (!registry.existsSync()) 'example/root/registry',
    if (!sample.existsSync()) 'example/root/filesys/c/test-sample.exe',
  ];

  test(
    'root and Windows aliases use Python factory defaults',
    () {
      final rootApp = root.createEmpty(registryDirectory: registry.path);
      final namespaceApp = win.windows.createEmpty(
        registryDirectory: registry.path,
      );
      try {
        expect(rootApp.backendName, 'Unicorn Engine');
        expect(rootApp.emulationRoot, isEmpty);
        expect(namespaceApp.backendName, 'Unicorn Engine');
        expect(namespaceApp.emulationRoot, isEmpty);
      } finally {
        namespaceApp.dispose();
        rootApp.dispose();
      }
    },
    skip: unavailable.isEmpty ? false : 'Missing ${unavailable.join(', ')}.',
  );

  test(
    'copies and applies complete application factory options',
    () {
      final arguments = <String>['alpha', '', 'space value'];
      final environment = <String, String>{
        'SOGEN_FACTORY_TEST': 'enabled',
        'MixedCase': 'value=with=equals',
      };
      final paths = <String, String>{r'C:\mapped.exe': sample.path};
      final ports = <int, int>{28970: 28980, 0: 0};

      final app = win.createApplication(
        r'C:\mapped.exe',
        arguments: arguments,
        environment: environment,
        emulationRoot: exampleRoot.path,
        workingDirectory: r'C:\',
        disableLogging: true,
        useRelativeTime: true,
        registryDirectory: 'ignored-when-emulation-root-is-set',
        pathMappings: paths,
        portMappings: ports,
        numberOfProcessors: 8,
        ntProductType: 3,
        backend: win.Backend.unicorn,
      );

      arguments.clear();
      environment.clear();
      paths.clear();
      ports.clear();
      try {
        expect(app.getHostPort(28970), 28980);
        expect(app.getHostPort(0), 0);
        app.start();
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
    skip: unavailable.isEmpty ? false : 'Missing ${unavailable.join(', ')}.',
  );

  test(
    'validates fixed-width factory values',
    () {
      expect(
        () => win.createEmpty(
          registryDirectory: registry.path,
          portMappings: const <int, int>{-1: 80},
        ),
        throwsRangeError,
      );
      expect(
        () => win.createEmpty(
          registryDirectory: registry.path,
          numberOfProcessors: 0x100000000,
        ),
        throwsRangeError,
      );
      expect(
        () => win.createEmpty(
          registryDirectory: registry.path,
          ntProductType: -1,
        ),
        throwsRangeError,
      );
    },
    skip: unavailable.isEmpty ? false : 'Missing ${unavailable.join(', ')}.',
  );
}
