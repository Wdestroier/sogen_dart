@Tags(<String>['native', 'linux', 'unicorn', 'requiresCc'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sogen/linux.dart';
import 'package:test/test.dart';

final _compilerAvailability = _findCompiler();
final String? _compilerSkip = _compilerAvailability.skipReason;

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('sogen-linux-system-');
  });

  tearDown(() {
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  test(
    'returns the configured working directory from getcwd',
    () {
      final executable = _compile(temporary, 'getcwd', r'''
#include <stdio.h>
#include <unistd.h>

int main(void) {
    char buffer[4096];
    if (getcwd(buffer, sizeof(buffer)) == 0) return 1;
    printf("%s\n", buffer);
    return 0;
}
''');
      final output = StringBuffer();
      final app = createApplication(executable.path, workingDirectory: '/tmp');
      app.callbacks.onStdout = output.write;

      try {
        app.start();
        expect(output.toString(), '/tmp\n');
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
    skip: _compilerSkip ?? false,
  );

  test(
    'reads a relative file through the mapped working directory',
    () {
      final hostWork = Directory('${temporary.path}/host-work')..createSync();
      File('${hostWork.path}/mapped.txt').writeAsStringSync('mapped\n');
      final executable = _compile(temporary, 'mapped_relative', r'''
#include <fcntl.h>
#include <unistd.h>

int main(void) {
    char buffer[32] = {0};
    int fd = open("mapped.txt", O_RDONLY);
    if (fd < 0) return 1;
    ssize_t count = read(fd, buffer, sizeof(buffer));
    close(fd);
    if (count <= 0) return 2;
    write(1, buffer, (size_t)count);
    return 0;
}
''');
      final output = StringBuffer();
      final app = createApplication(
        '/guest-bin/${executable.uri.pathSegments.last}',
        workingDirectory: '/work',
        pathMappings: <String, String>{
          '/guest-bin': temporary.path,
          '/work': hostWork.path,
        },
      );
      app.callbacks.onStdout = output.write;

      try {
        app.start();
        expect(output.toString(), 'mapped\n');
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
    skip: _compilerSkip ?? false,
  );

  test(
    'confines absolute symlink targets to the emulation root',
    () {
      final escape = Directory.systemTemp.createTempSync('sogen-escape-');
      addTearDown(() {
        if (escape.existsSync()) escape.deleteSync(recursive: true);
      });
      final hostEscape = File('${escape.path}/host-escape.txt')
        ..writeAsStringSync('escaped\n');
      final sandbox = Directory('${temporary.path}/root')..createSync();
      Directory('${sandbox.path}/tmp').createSync(recursive: true);
      final guestTarget = _absoluteGuestPath(hostEscape.path);
      final confined = File(
        '${sandbox.path}${guestTarget.replaceAll('/', Platform.pathSeparator)}',
      );
      confined.parent.createSync(recursive: true);
      confined.writeAsStringSync('contained\n');
      final executable = _compile(temporary, 'symlink', '''
#include <fcntl.h>
#include <unistd.h>

int main(void) {
    char buffer[32] = {0};
    if (symlink(${jsonEncode(guestTarget)}, "/tmp/link") != 0) return 1;
    int fd = open("/tmp/link", O_RDONLY);
    if (fd < 0) return 2;
    ssize_t count = read(fd, buffer, sizeof(buffer));
    close(fd);
    if (count <= 0) return 3;
    write(1, buffer, (size_t)count);
    return 0;
}
''');
      final mappings = <String, String>{'/guest-bin': temporary.path};
      for (final path in const ['/lib', '/lib64', '/usr']) {
        if (Directory(path).existsSync()) mappings[path] = path;
      }
      final output = StringBuffer();
      final app = createApplication(
        '/guest-bin/${executable.uri.pathSegments.last}',
        emulationRoot: sandbox.path,
        workingDirectory: '/tmp',
        pathMappings: mappings,
      );
      app.callbacks.onStdout = output.write;

      try {
        app.start();
        expect(output.toString(), 'contained\n');
        expect(app.process.exitStatus, 0);
        expect(hostEscape.readAsStringSync(), 'escaped\n');
      } finally {
        app.dispose();
      }
    },
    skip: _compilerSkip ?? false,
  );

  test(
    'reads existing read-only files and rejects truncation',
    () {
      final readOnly = Directory('${temporary.path}/read-only')..createSync();
      final locked = File('${readOnly.path}/locked.txt')
        ..writeAsStringSync('locked');
      final executable = _compile(temporary, 'readonly', r'''
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    char buffer[16] = {0};
    int fd = open("/ro/locked.txt", O_RDONLY);
    if (fd < 0) return 1;
    ssize_t count = read(fd, buffer, sizeof(buffer));
    close(fd);
    if (count != 6 || memcmp(buffer, "locked", 6) != 0) return 2;
    fd = open("/ro/locked.txt", O_WRONLY | O_TRUNC);
    if (fd >= 0) {
        close(fd);
        return 3;
    }
    puts("readonly");
    return 0;
}
''');
      final output = StringBuffer();
      final app = createApplication(
        executable.path,
        readOnlyPathMappings: <String, String>{'/ro': readOnly.path},
      );
      app.callbacks.onStdout = output.write;

      try {
        app.start();
        expect(output.toString(), 'readonly\n');
        expect(app.process.exitStatus, 0);
        expect(locked.readAsStringSync(), 'locked');
      } finally {
        app.dispose();
      }
    },
    skip: _compilerSkip ?? false,
  );

  test(
    'returns ENOMEM when mprotect targets unmapped memory',
    () {
      final executable = _compile(temporary, 'mprotect', r'''
#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>

int main(void) {
    errno = 0;
    if (mprotect((void *)0x700000000000ULL, 4096, PROT_READ) != -1) return 1;
    if (errno != ENOMEM) return 2;
    puts("enomem");
    return 0;
}
''');
      final output = StringBuffer();
      final app = createApplication(executable.path);
      app.callbacks.onStdout = output.write;

      try {
        app.start();
        expect(output.toString(), 'enomem\n');
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
    skip: _compilerSkip ?? false,
  );

  test('restores write-only file descriptor access mode', () {
    final stateFile = File('${temporary.path}/writeonly-state.txt')
      ..writeAsStringSync('initial');
    final executable = _compile(temporary, 'writeonly', r'''
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    char byte = 0;
    int fd = open("/state/writeonly-state.txt", O_WRONLY);
    if (fd < 0) return 1;
    if (write(fd, "updated", 7) != 7) return 2;
    getpid();
    if (read(fd, &byte, 1) >= 0) return 3;
    close(fd);
    puts("writeonly");
    return 0;
}
''');
    final output = StringBuffer();
    final app = createApplication(
      executable.path,
      pathMappings: <String, String>{'/state': temporary.path},
    );
    var restored = false;
    app.callbacks.onStdout = output.write;
    app.callbacks.onSyscall = (_, name) {
      if (name == 'getpid' && !restored) {
        restored = true;
        app.deserializeState(app.serializeState());
      }
      return HookContinuation.run;
    };

    try {
      app.start();
      expect(restored, isTrue);
      expect(output.toString(), 'writeonly\n');
      expect(app.process.exitStatus, 0);
      expect(stateFile.readAsStringSync(), 'updated');
    } finally {
      app.dispose();
    }
  }, skip: _compilerSkip ?? false);

  test(
    'reports fatal SIGTERM and resumes handled SIGUSR1 and INT3',
    () {
      final fatal = _compile(temporary, 'fatal_signal', r'''
#include <signal.h>
#include <unistd.h>

int main(void) {
    kill(getpid(), SIGTERM);
    return 1;
}
''');
      for (final alias in const ['signal', 'exception']) {
        final fatalEvents = <(int, int, int)>[];
        final fatalApp = createApplication(fatal.path);
        if (alias == 'signal') {
          fatalApp.callbacks.onSignal = (signal, address, code) {
            fatalEvents.add((signal, address, code));
          };
        } else {
          fatalApp.callbacks.onException = (signal, address, code) {
            fatalEvents.add((signal, address, code));
          };
        }
        try {
          fatalApp.start();
          expect(fatalEvents, isNotEmpty, reason: 'on$alias did not fire');
          expect(fatalEvents.first.$1, 15);
          expect(fatalApp.lastStopReason, 'signal_termination');
          expect(fatalApp.process.exitStatus, 143);
        } finally {
          fatalApp.dispose();
        }
      }

      final handled = _compile(temporary, 'handled_signal', r'''
#include <signal.h>
#include <sys/syscall.h>
#include <unistd.h>

static volatile sig_atomic_t handled = 0;
static void handler(int signal) {
    (void)signal;
    handled++;
}

int main(void) {
    struct sigaction action = {0};
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR1, &action, 0) != 0) return 2;
    if (syscall(SYS_kill, getpid(), SIGUSR1) != 0) return 3;
    if (handled != 1) return 4;
    if (syscall(SYS_tgkill, getpid(), syscall(SYS_gettid), SIGUSR1) != 0) return 5;
    return handled == 2 ? 0 : 6;
}
''');
      final handledEvents = <(int, int, int)>[];
      final handledApp = createApplication(handled.path);
      handledApp.callbacks.onSignal = (signal, address, code) {
        handledEvents.add((signal, address, code));
      };
      try {
        handledApp.start();
        expect(handledEvents.where((event) => event.$1 == 10), hasLength(2));
        expect(handledApp.lastStopReason, 'normal_exit');
        expect(handledApp.process.exitStatus, 0);
      } finally {
        handledApp.dispose();
      }

      final trap = _compile(temporary, 'handled_trap', r'''
#include <signal.h>

static volatile sig_atomic_t handled = 0;
static void handler(int signal) {
    (void)signal;
    handled++;
}

int main(void) {
    struct sigaction action = {0};
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTRAP, &action, 0) != 0) return 2;
    __asm__ volatile("int3");
    return handled == 1 ? 0 : 3;
}
''');
      final trapEvents = <(int, int, int)>[];
      final trapApp = createApplication(trap.path);
      trapApp.callbacks.onSignal = (signal, address, code) {
        trapEvents.add((signal, address, code));
      };
      try {
        trapApp.start();
        expect(trapEvents, isNotEmpty);
        expect(trapEvents.first.$1, 5);
        expect(trapEvents.first.$3, 1);
        expect(trapApp.lastStopReason, 'normal_exit');
        expect(trapApp.process.exitStatus, 0);
      } finally {
        trapApp.dispose();
      }
    },
    skip: _compilerSkip ?? false,
  );

  test(
    'proxies mapped sockets and rejects snapshots while one is live',
    () async {
      final executable = _compile(temporary, 'socket_proxy', r'''
#include <arpa/inet.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void) {
    static const char dup_payload[] = "dup payload";
    static const char msg_payload[] = "sendmsg payload";
    static const char expected[] = "recvmsg response";
    char buffer[64] = {0};
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 1;
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons(40000);
    address.sin_addr.s_addr = htonl(0x7f000001u);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) return 2;
    struct sockaddr_in peer = {0};
    socklen_t peer_length = sizeof(peer);
    if (getpeername(fd, (struct sockaddr *)&peer, &peer_length) != 0) return 3;
    if (peer.sin_family != AF_INET || ntohs(peer.sin_port) != 40000 ||
        ntohl(peer.sin_addr.s_addr) != 0x7f000001u) return 4;
    int copy = dup(fd);
    if (copy < 0) return 5;
    if (send(copy, dup_payload, sizeof(dup_payload) - 1, 0) != sizeof(dup_payload) - 1) return 6;
    struct iovec send_iov = {(void *)msg_payload, sizeof(msg_payload) - 1};
    struct msghdr send_message = {0};
    send_message.msg_iov = &send_iov;
    send_message.msg_iovlen = 1;
    if (sendmsg(fd, &send_message, 0) != sizeof(msg_payload) - 1) return 7;
    struct iovec receive_iov = {buffer, sizeof(buffer)};
    struct msghdr receive_message = {0};
    receive_message.msg_iov = &receive_iov;
    receive_message.msg_iovlen = 1;
    ssize_t received = recvmsg(fd, &receive_message, 0);
    if (received != sizeof(expected) - 1) return 8;
    if (memcmp(buffer, expected, sizeof(expected) - 1) != 0) return 9;
    write(1, "proxied\n", 8);
    close(copy);
    close(fd);
    return 0;
}
''');
      final messages = ReceivePort();
      final portReady = Completer<int>();
      final payloadReady = Completer<List<int>>();
      final subscription = messages.listen((message) {
        if (message is int && !portReady.isCompleted) {
          portReady.complete(message);
        } else if (message is List<int> && !payloadReady.isCompleted) {
          payloadReady.complete(message);
        } else if (message is String) {
          if (!portReady.isCompleted) {
            portReady.completeError(message);
          } else if (!payloadReady.isCompleted) {
            payloadReady.completeError(message);
          }
        }
      });
      final isolate = await Isolate.spawn(_serveSocket, messages.sendPort);
      addTearDown(() async {
        isolate.kill(priority: Isolate.immediate);
        await subscription.cancel();
        messages.close();
      });
      final hostPort = await portReady.future.timeout(
        const Duration(seconds: 5),
      );
      final output = StringBuffer();
      final snapshotErrors = <String>[];
      final syscalls = <String>[];
      var received = false;
      final app = createApplication(
        executable.path,
        portMappings: <int, int>{40000: hostPort},
      );
      expect(app.getHostPort(40000), hostPort);
      expect(app.getEmulatorPort(hostPort), 40000);
      app.callbacks.onStdout = output.write;
      app.callbacks.onSyscall = (_, name) {
        syscalls.add(name);
        if (name == 'recvmsg') {
          received = true;
        } else if (name == 'close' && received && snapshotErrors.isEmpty) {
          try {
            app.serializeState();
          } on SogenException catch (error) {
            snapshotErrors.add(error.message);
          }
        }
        return HookContinuation.run;
      };

      try {
        app.start();
        final payload = await payloadReady.future.timeout(
          const Duration(seconds: 5),
        );
        expect(utf8.decode(payload), 'dup payloadsendmsg payload');
        expect(output.toString(), 'proxied\n');
        expect(
          syscalls,
          containsAll(<String>[
            'connect',
            'getpeername',
            'dup',
            'sendto',
            'sendmsg',
            'recvmsg',
          ]),
        );
        expect(snapshotErrors, isNotEmpty);
        expect(snapshotErrors.single.toLowerCase(), contains('socket'));
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
    skip: _compilerSkip ?? false,
    tags: const ['requiresNetwork'],
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

File _compile(Directory directory, String name, String source) {
  final sourceFile = File('${directory.path}/$name.c')
    ..writeAsStringSync(source);
  final output = File('${directory.path}/$name.elf');
  final compiler = _compilerAvailability.compiler!;
  final result = compiler.compile(sourceFile, output);
  if (result.exitCode != 0) {
    throw TestFailure(
      '${compiler.description} failed for $name (${result.exitCode}):'
      '\n${result.stdout}\n${result.stderr}',
    );
  }
  return output;
}

String _absoluteGuestPath(String hostPath) {
  var guestPath = hostPath.replaceAll('\\', '/');
  if (RegExp(r'^[A-Za-z]:/').hasMatch(guestPath)) {
    guestPath = guestPath.substring(2);
  }
  return guestPath.startsWith('/') ? guestPath : '/$guestPath';
}

_CompilerAvailability _findCompiler() {
  final candidates = <_Compiler>[];
  final configured = Platform.environment['CC'];
  if (configured != null && configured.trim().isNotEmpty) {
    candidates.add(_Compiler(configured.trim()));
  }
  candidates.addAll(const <_Compiler>[
    _Compiler('x86_64-linux-gnu-gcc'),
    _Compiler('cc'),
    _Compiler('gcc'),
    _Compiler('clang'),
    _Compiler('clang', prefixArguments: ['--target=x86_64-linux-gnu']),
    _Compiler('zig', prefixArguments: ['cc', '-target', 'x86_64-linux-gnu']),
  ]);
  if (Platform.isWindows) {
    candidates.addAll(const <_Compiler>[
      _Compiler('wsl.exe', prefixArguments: ['--exec', 'cc'], usesWsl: true),
      _Compiler('wsl.exe', prefixArguments: ['--exec', 'gcc'], usesWsl: true),
      _Compiler('wsl.exe', prefixArguments: ['--exec', 'clang'], usesWsl: true),
    ]);
  }

  final probeDirectory = Directory.systemTemp.createTempSync(
    'sogen-linux-cc-probe-',
  );
  try {
    final source = File('${probeDirectory.path}/probe.c')
      ..writeAsStringSync(r'''
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(void) {
    return 0;
}
''');
    final output = File('${probeDirectory.path}/probe.elf');
    for (final candidate in candidates) {
      for (final linkArguments in const <List<String>>[
        <String>['-static'],
        <String>[],
      ]) {
        final compiler = candidate.withLinkArguments(linkArguments);
        try {
          if (output.existsSync()) output.deleteSync();
          final result = compiler.compile(source, output);
          if (result.exitCode == 0 && _isX64Elf(output)) {
            return _CompilerAvailability(compiler: compiler);
          }
        } on ProcessException {
          break;
        }
      }
    }
  } finally {
    probeDirectory.deleteSync(recursive: true);
  }

  return const _CompilerAvailability(
    skipReason:
        'No available C compiler produced a linked x86-64 Linux ELF '
        'fixture with the required Linux headers.',
  );
}

bool _isX64Elf(File file) {
  if (!file.existsSync()) return false;
  final bytes = file.readAsBytesSync();
  return bytes.length >= 20 &&
      bytes[0] == 0x7f &&
      bytes[1] == 0x45 &&
      bytes[2] == 0x4c &&
      bytes[3] == 0x46 &&
      bytes[4] == 2 &&
      bytes[5] == 1 &&
      bytes[18] == 0x3e &&
      bytes[19] == 0;
}

final class _CompilerAvailability {
  const _CompilerAvailability({this.compiler, this.skipReason});

  final _Compiler? compiler;
  final String? skipReason;
}

final class _Compiler {
  const _Compiler(
    this.command, {
    this.prefixArguments = const <String>[],
    this.linkArguments = const <String>[],
    this.usesWsl = false,
  });

  final String command;
  final List<String> prefixArguments;
  final List<String> linkArguments;
  final bool usesWsl;

  String get description =>
      ([command, ...prefixArguments, ...linkArguments]).join(' ');

  _Compiler withLinkArguments(List<String> arguments) => _Compiler(
    command,
    prefixArguments: prefixArguments,
    linkArguments: arguments,
    usesWsl: usesWsl,
  );

  ProcessResult compile(File source, File output) {
    final sourcePath = usesWsl ? _wslPath(source.path) : source.path;
    final outputPath = usesWsl ? _wslPath(output.path) : output.path;
    return Process.runSync(
      command,
      <String>[
        ...prefixArguments,
        '-O0',
        ...linkArguments,
        sourcePath,
        '-o',
        outputPath,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  String _wslPath(String path) {
    final result = Process.runSync(
      'wsl.exe',
      <String>['--exec', 'wslpath', '-a', '-u', path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'wsl.exe',
        <String>['--exec', 'wslpath', '-a', '-u', path],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout.toString().trim();
  }
}

Future<void> _serveSocket(SendPort messages) async {
  ServerSocket? server;
  Socket? socket;
  try {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    messages.send(server.port);
    socket = await server.first;
    final expectedLength = utf8.encode('dup payloadsendmsg payload').length;
    final payload = <int>[];
    await for (final chunk in socket) {
      payload.addAll(chunk);
      if (payload.length >= expectedLength) {
        socket.add(utf8.encode('recvmsg response'));
        await socket.flush();
        messages.send(payload);
        break;
      }
    }
  } on Object catch (error) {
    messages.send(error.toString());
  } finally {
    await socket?.close();
    await server?.close();
  }
}
