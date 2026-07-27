library;

export 'src/api_hook.dart' show ApiCall, ApiHook, ApiHookCallback, apiCall;
export 'src/application.dart'
    show
        BasicBlockHookCallback,
        DebugStringCallback,
        ExecutionHookCallback,
        ExceptionCallback,
        GenericAccessCallback,
        GenericActivityCallback,
        Hook,
        InstructionCallback,
        InterruptHookCallback,
        IoctrlCallback,
        MemoryAllocateCallback,
        MemoryHookCallback,
        MemoryProtectCallback,
        MemoryViolateCallback,
        ModuleLoadCallback,
        ModuleUnloadCallback,
        ProcessContext,
        RdtscCallback,
        RdtscpCallback,
        StdoutCallback,
        SuspiciousActivityCallback,
        SyscallCallback,
        ThreadCreateCallback,
        ThreadSetNameCallback,
        ThreadSwitchCallback,
        ThreadTerminatedCallback,
        WindowsApplication,
        WindowsCallbacks,
        WindowsHooks,
        WindowsMemoryManager,
        WindowsNamespace,
        configureNativeLibrary,
        createApplication,
        createEmpty,
        windows;
export 'src/exceptions.dart' show SogenCallbackException, SogenException;
export 'src/hook_continuation.dart'
    show InstructionHookCallback, MemoryViolationHookCallback;
export 'src/generated/types.g.dart'
    show
        ApiContinuation,
        Backend,
        CallingConvention,
        HookContinuation,
        Instruction,
        MemoryOperation,
        MemoryPermission,
        MemoryRegionKind,
        MemoryViolationContinuation,
        MemoryViolationType,
        Register;
export 'src/types.dart'
    show
        BasicBlock,
        ExportedSymbol,
        Handle,
        MappedModule,
        MemoryRegionInfo,
        MemoryStats,
        WindowsThread;
