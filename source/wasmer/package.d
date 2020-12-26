/// Wasmer Engine API
///
/// An idiomatic D wrapper of the <a href="https://github.com/wasmerio/wasmer/tree/master/lib/c-api#readme">Wasmer Runtime</a> providing an implementation of the <a href="https://github.com/WebAssembly/wasm-c-api#readme">WebAssembly C API</a>.
///
/// See_Also: The official <a href="https://github.com/wasmerio/wasmer/tree/master/lib/c-api#readme">Wasmer Runtime C API</a> documentation.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: MIT License
module wasmer;

import std.conv : to;

public import wasmer.bindings;
public import wasmer.bindings.funcs;

private extern(C) void finalizeHostInfo(T)(void* data) if (is(T == class)) {
  destroy(this.hostInfo!T);
}

/// Manages a native handle to a Wasmer structure.
abstract class Handle(T) if (is(T == struct)) {
  private T* handle_;
  /// Whether this handle was borrowed from the Wasmer runtime. Borrowed handles are not automatically freed in D-land.
  const bool borrowed;

  ///
  this(T* value, bool borrowed = false) {
    handle_ = value;
    this.borrowed = borrowed;
  }
  ~this() {
    handle_ = null;
  }

  /// Whether this managed handle to a Wasmer structure is valid.
  bool valid() @property const {
    return handle_ !is null;
  }

  ///
  T* handle() @property const {
    return cast(T*) handle_;
  }

  /// The last error message that was raised by the Wasmer Runtime.
  string lastError() @property const {
    const size = wasmer_last_error_length();
    auto buf = new char[size];
    wasmer_last_error_message(buf.ptr, size);
    return buf.idup;
  }
}

///
final class Engine : Handle!wasm_engine_t {
  ///
  this() {
    super(wasm_engine_new());
  }
  ~this() {
    if (valid) wasm_engine_delete(handle);
  }
}

unittest {
  assert(new Engine().valid);
}

/// All runtime objects are tied to a specific store.
///
/// Multiple stores can be created, but their objects cannot interact. Every store and its objects must only be accessed in a single thread.
class Store : Handle!wasm_store_t {
  ///
  const Engine engine;

  ///
  this (Engine engine) {
    this.engine = engine;

    super(wasm_store_new(cast(wasm_engine_t*) engine.handle));
  }
  ~this() {
    if (valid) wasm_store_delete(handle);
  }
}

unittest {
  const store = new Store(new Engine());
  assert(store.valid);
  destroy(store);
}

/// Limits of the page size of a block of `Memory`. One page of memory is 64 kB.
alias Limits = wasm_limits_t;

/// Size in bytes of one page of WebAssembly memory. One page of memory is 64 kB.
enum uint pageSize = 65_536;

/// A block of memory.
class Memory : Handle!wasm_memory_t {
  private wasm_memorytype_t* type;
  ///
  const Limits limits;

  ///
  this(Store store, Limits limits) {
    this.limits = limits;
    type = wasm_memorytype_new(&this.limits);
    super(wasm_memory_new(store.handle, type));
  }
  ~this() {
    if (valid) {
      wasm_memory_delete(handle);
      wasm_memorytype_delete(type);
    }
    type = null;
  }

  /// Whether this managed handle to a `wasm_memory_t` is valid.
  override bool valid() @property const {
    return type !is null && super.valid;
  }

  /// The current length in pages of this block of memory. One page of memory is 64 kB.
  uint pageLength() @property const {
    return wasm_memory_size(handle);
  }

  /// The current length in bytes of this block of memory.
  ulong length() @property const {
    return wasm_memory_data_size(handle);
  }

  ///
  void* ptr() @property const {
    return wasm_memory_data(handle);
  }

  /// A slice of all the data in this block of memory.
  ubyte[] data() @property const {
    return cast(ubyte[]) ptr[0..length];
  }

  /// Grows this block of memory by the given amount of pages.
  /// Returns: Whether this block of memory was successfully grown. Use the `Handle.lastError` property to get more details of the error, if any.
  bool grow(uint deltaPages) {
    return wasm_memory_grow(handle, deltaPages);
  }
}

unittest {
  auto store = new Store(new Engine());
  const maxNumPages = 5;
  auto memory = new Memory(store, Limits(maxNumPages - 1, maxNumPages));

  assert(memory.valid, "Error creating block of memory!");
  assert(memory.pageLength == 4);
  assert(memory.length == 4 * pageSize);
  assert(memory.grow(0));

  assert(memory.grow(1));
  assert(memory.pageLength == 5);
  assert(memory.length == 5 * pageSize);
  assert(!memory.grow(1));

  destroy(memory);
}

/// A WebAssembly module.
class Module : Handle!wasm_module_t {
  private Store store;

  ///
  this(Store store, ubyte[] wasmBytes) {
    this.store = store;

    wasm_byte_vec_t bytes;
    wasm_byte_vec_new(&bytes, wasmBytes.length, cast(char*) wasmBytes.ptr);

    super(wasm_module_new(cast(wasm_store_t*) store.handle, &bytes));
    wasm_byte_vec_delete(&bytes);
  }
  private this(wasm_module_t* module_) {
    super(module_);
  }
  ~this() {
    if (valid) wasm_module_delete(handle);
  }

  /// Instantiate a module given a string in the WebAssembly <a href="https://webassembly.github.io/spec/core/text/index.html">Text Format</a>.
  static Module from(Store store, string source) {
    wasm_byte_vec_t wat;
    wasm_byte_vec_new(&wat, source.length, source.ptr);
    wasm_byte_vec_t wasmBytes;
    wat2wasm(&wat, &wasmBytes);
    return new Module(store, cast(ubyte[]) wasmBytes.data[0 .. wasmBytes.size]);
  }

  /// Deserializes a module given the bytes of a previously serialized module.
  /// Returns: `null` on error. Use the `Handle.lastError` property to get more details of the error, if any.
  static Module deserialize(Store store, ubyte[] data) {
    wasm_byte_vec_t dataVec = wasm_byte_vec_t(data.length, cast(char*) data.ptr);
    auto module_ = wasm_module_deserialize(store.handle, &dataVec);
    if (module_ == null) return null;
    return new Module(module_);
  }

  ///
  T hostInfo(T)() @property const {
    return cast(T) wasm_module_get_host_info(handle);
  }
  ///
  void hostInfo(T)(ref T value) @property {
    static if (is(T == class)) {
      wasm_module_set_host_info_with_finalizer(handle, &value, &finalizeHostInfo!T);
    } else {
      wasm_module_set_host_info(handle, &value);
    }
  }

  /// Creates a new `Instance` of this module from the given imports, if any.
  Instance instantiate(Extern[] imports = []) {
    assert(valid);
    return new Instance(store, this, imports);
  }

  /// Serializes this module, the result can be saved and later deserialized back into an executable module.
  /// Returns: `null` on error. Use the `Handle.lastError` property to get more details of the error, if any.
  ubyte[] serialize() {
    wasm_byte_vec_t dataVec;
    wasm_module_serialize(handle, &dataVec);
    if (dataVec.size == 0 || dataVec.data == null) return null;
    return cast(ubyte[]) dataVec.data[0..dataVec.size];
  }
}

version (unittest) {
  const string wat_sum_module =
    "(module\n" ~
    "  (type $sum_t (func (param i32 i32) (result i32)))\n" ~
    "  (func $sum_f (type $sum_t) (param $x i32) (param $y i32) (result i32)\n" ~
    "    local.get $x\n" ~
    "    local.get $y\n" ~
    "    i32.add)\n" ~
    "  (export \"sum\" (func $sum_f)))";
}

unittest {
  auto engine = new Engine();
  auto store = new Store(engine);
  auto module_ = Module.from(store, wat_sum_module);

  assert(module_.valid, "Error compiling module!");
  assert(module_.instantiate().valid, "Error instantiating module!");

  auto serializedModule = module_.serialize();
  assert(serializedModule !is null, "Error serializing module!");

  assert(Module.deserialize(store, serializedModule).valid, "Error deserializing module!");
}

///
class Extern : Handle!wasm_extern_t {
  ///
  const string name;
  ///
  const wasm_externkind_enum kind;

  private this(wasm_extern_t* extern_, string name = "") {
    super(extern_);
    this.name = name;
    kind = wasm_extern_kind(extern_).to!wasm_externkind_enum;
  }
  ~this() {
    if (valid) wasm_extern_delete(handle);
  }
}

/// A WebAssembly virtual machine instance.
class Instance : Handle!wasm_instance_t {
  private wasm_exporttype_vec_t exportTypes;

  ///
  this(Store store, Module module_, Extern[] imports = []) {
    import std.algorithm : map;
    import std.array : array;

    wasm_extern_vec_t importObject;
    auto importsVecElements = cast(wasm_extern_t**) imports.map!(import_ => import_.handle).array.ptr;
    wasm_extern_vec_new(&importObject, imports.length, importsVecElements);

    super(wasm_instance_new(
      cast(wasm_store_t*) store.handle, cast(wasm_module_t*) module_.handle, &importObject, null
    ));

    // Get exported types
    wasm_module_exports(cast(wasm_module_t*) module_.handle, &exportTypes);
  }
  ~this() {
    if (valid) wasm_instance_delete(handle);
  }

  Extern[] exports() @property const {
    wasm_extern_vec_t exportsVector;
    wasm_instance_exports(handle, &exportsVector);

    auto exports = new Extern[exportsVector.size];
    for (auto i = 0; i < exportsVector.size; i++) {
      const nameVec = wasm_exporttype_name(exportTypes.data[i]);
      const name = cast(string) nameVec.data[0..nameVec.size];

      exports[i] = new Extern(exportsVector.data[i], name.idup);
    }
    return exports;
  }
}

unittest {
  auto engine = new Engine();
  auto store = new Store(engine);
  auto module_ = Module.from(store, wat_sum_module);
  auto instance = new Instance(store, module_);

  assert(module_.valid, "Error compiling module!");
  assert(instance.valid, "Error instantiating module!");
  assert(instance.exports.length == 1, "Error accessing exports!");
  assert(instance.exports[0].kind == wasm_externkind_enum.WASM_EXTERN_FUNC);
  assert(instance.exports[0].name == "sum");

  destroy(instance);
  destroy(module_);
  destroy(store);
  destroy(engine);
}

/// A WebAssembly value, wrapping an int, long, float, or double.
class Value : Handle!wasm_val_t {
  private const bool borrowed;
  ///
  const wasm_valkind_enum kind;

  ///
  this(wasm_valkind_enum kind) {
    this.kind = kind;
    super(new wasm_val_t(kind));
    borrowed = false;
  }
  ///
  this(int value) {
    this.kind = wasm_valkind_enum.WASM_I32;
    super(new wasm_val_t);
    handle.of.i32 = value;
    borrowed = false;
  }
  ///
  this(long value) {
    this.kind = wasm_valkind_enum.WASM_I64;
    super(new wasm_val_t);
    handle.of.i64 = value;
    borrowed = false;
  }
  ///
  this(float value) {
    this.kind = wasm_valkind_enum.WASM_F32;
    super(new wasm_val_t);
    handle.of.f32 = value;
    borrowed = false;
  }
  ///
  this(double value) {
    this.kind = wasm_valkind_enum.WASM_F64;
    super(new wasm_val_t);
    handle.of.f64 = value;
    borrowed = false;
  }
  private this(wasm_val_t value) {
    super(new wasm_val_t(value.kind, value.of));
    this.kind = value.kind.to!wasm_valkind_enum;
    borrowed = false;
  }
  private this(wasm_val_t* value) {
    super(new wasm_val_t);
    this.kind = value.kind.to!wasm_valkind_enum;
    borrowed = true;
  }
  ~this() {
    if (valid && borrowed) wasm_val_delete(handle);
  }

  ///
  static Value from(wasm_val_t value) {
    return new Value(value);
  }

  ///
  auto value() @property const {
    return handle;
  }
}

/// A function to be called from WASM code.
extern(C) alias Callback = wasm_trap_t* function(const wasm_val_vec_t* arguments, wasm_val_vec_t* results);
/// A function to be called from WASM code. Includes an environment variable.
extern(C) alias CallbackWithEnv = wasm_trap_t* function(
  void* env, const wasm_val_vec_t* arguments, wasm_val_vec_t* results
);

/// A WebAssembly function reference.
class Function : Handle!wasm_func_t {
  /// Instantiate a D function to be called from WASM code.
  this(Store store, wasm_functype_t* type, Callback callback) {
    super(wasm_func_new(cast(wasm_store_t*) store.handle, type, callback));
  }
  /// ditto
  this(Store store, wasm_functype_t* type, CallbackWithEnv callback, void* env) {
    super(wasm_func_new_with_env(cast(wasm_store_t*) store.handle, type, callback, env, null));
  }
  private this(wasm_func_t* func) {
    super(func);
  }

  ///
  static Function from(Extern extern_) {
    return new Function(wasm_extern_as_func(cast(wasm_extern_t*) extern_.handle));
  }

  ///
  Extern asExtern() @property const {
    return new Extern(wasm_func_as_extern(handle));
  }

  /// Params:
  /// results=Zero or more <a href="https://github.com/WebAssembly/multi-value/blob/master/proposals/multi-value/Overview.md">return values</a>
  /// Returns: Whether the function ran to completion without hitting a trap.
  bool call(out Value[] results) {
    return call([], results);
  }
  /// Params:
  /// arguments=
  /// results=Zero or more <a href="https://github.com/WebAssembly/multi-value/blob/master/proposals/multi-value/Overview.md">return values</a>
  /// Returns: Whether the function ran to completion without hitting a trap.
  bool call(Value[] arguments, out Value[] results) {
    import std.algorithm : map;
    import std.array : array;

    wasm_val_vec_t args;
    wasm_val_vec_new(&args, arguments.length, arguments.map!(param => *param.handle).array.ptr);

    wasm_val_vec_t resultsVec;
    wasm_val_vec_new_uninitialized(&resultsVec, 1);
    auto trap = wasm_func_call(handle, &args, &resultsVec);
    wasm_val_vec_delete(&args);
    if (trap !is null) throw new Exception(new Trap(trap).message);
    results = new Value[resultsVec.size];
    for (auto i = 0; i < resultsVec.size; i += 1) {
      results[i] = Value.from(resultsVec.data[i]);
    }
    wasm_val_vec_delete(&resultsVec);

    return true;
  }
}

version (unittest) {
  const string wat_callback_module =
"(module" ~
"  (func $print (import \"\" \"print\") (param i32) (result i32))" ~
"  (func $closure (import \"\" \"closure\") (result i32))" ~
"  (func (export \"run\") (param $x i32) (param $y i32) (result i32)" ~
"    (i32.add" ~
"      (call $print (i32.add (local.get $x) (local.get $y)))" ~
"      (call $closure)" ~
"    )" ~
"  )" ~
")";

  package extern(C) wasm_trap_t* print(const wasm_val_vec_t* arguments, wasm_val_vec_t* results) {
    assert(arguments.size == 1 && arguments.data[0].of.i32 == 7);
    wasm_val_copy(&results.data[0], &arguments.data[0]);
    return null;
  }

  package extern(C) wasm_trap_t* closure(void* env, const wasm_val_vec_t* args, wasm_val_vec_t* results) {
    int i = *(cast(int*) env);

    results.data[0].kind = WASM_I32;
    results.data[0].of.i32 = cast(int32_t) i;
    return null;
  }
}

unittest {
  auto engine = new Engine();
  auto store = new Store(engine);
  auto module_ = Module.from(store, wat_callback_module);
  assert(module_.valid, "Error compiling module!");
  int i = 42;
  auto imports = [
    new Function(store, wasm_functype_new_1_1(wasm_valtype_new_i32(), wasm_valtype_new_i32()), &print).asExtern,
    new Function(store, wasm_functype_new_0_1(wasm_valtype_new_i32()), &closure, &i).asExtern
  ];
  auto instance = module_.instantiate(imports);
  auto runFunc = Function.from(instance.exports[0]);

  assert(instance.exports[0].name == "run" && runFunc.valid, "Failed to get the `run` function!");

  auto three = new Value(3);
  auto four = new Value(4);
  Value[] results;
  assert(runFunc.call([three, four], results), "Error calling the `run` function!");
  assert(results.length == 1 && results[0].value.of.i32 == 49);

  destroy(three);
  destroy(four);
  destroy(instance);
  destroy(module_);
}

///
class Trap : Handle!wasm_trap_t {
  ///
  const string message;
  ///
  this(wasm_trap_t* trap) {
    super(trap, true);
    wasm_name_t messageVec;
    wasm_trap_message(trap, &messageVec);
    this.message = messageVec.data[0..messageVec.size].idup;
  }
  ///
  this(Store store, string message = "") {
    import std.string : toStringz;

    super(wasm_trap_new(cast(wasm_store_t*) store.handle, null), );
    this.message = message;
    if (message.length) {
      wasm_byte_vec_t stringVec;
      wasm_byte_vec_new(&stringVec, message.length, message.toStringz);
      wasm_trap_message(handle, &stringVec);
      wasm_byte_vec_delete(&stringVec);
    }
  }
  ~this() {
    if (valid && !borrowed) wasm_trap_delete(handle);
  }

  ///
  T hostInfo(T)() @property const {
    return cast(T) wasm_trap_get_host_info(handle);
  }
  ///
  void hostInfo(T)(ref T value) @property {
    static if (is(T == class)) {
      wasm_trap_set_host_info_with_finalizer(handle, &value, &finalizeHostInfo!T);
    } else {
      wasm_trap_set_host_info(handle, &value);
    }
  }
}

version (unittest) {
  const string wat_trap_module =
    "(module" ~
    "  (func $callback (import \"\" \"callback\") (result i32))" ~
    "  (func (export \"callback\") (result i32) (call $callback))" ~
    "  (func (export \"unreachable\") (result i32) (unreachable) (i32.const 1))" ~
    ")";

  package extern(C) wasm_trap_t* fail(void* env, const wasm_val_vec_t* args, wasm_val_vec_t* results) {
    assert(env !is null);
    wasm_name_t message;
    wasm_name_new_from_string_nt(&message, "callback abort"c.ptr);
    wasm_trap_t* trap = wasm_trap_new(cast(wasm_store_t*) env, &message);
    wasm_name_delete(&message);
    return trap;
  }
}

unittest {
  import std.exception : assertThrown, collectExceptionMsg;

  auto engine = new Engine();
  auto store = new Store(engine);
  auto module_ = Module.from(store, wat_trap_module);
  assert(module_.valid, "Error compiling module!");
  auto imports = [
    new Function(store, wasm_functype_new_0_1(wasm_valtype_new_i32()), &fail, store.handle).asExtern
  ];
  auto instance = new Instance(store, module_, imports);
  assert(instance.valid && instance.exports.length == 2, "Error accessing exports!");
  auto callbackFunc = Function.from(instance.exports[0]);

  assert(instance.exports[0].name == "callback" && callbackFunc.valid, "Failed to get the `callback` function!");

  Value[] results;
  assertThrown(callbackFunc.call(results));
  // TODO: Assert trap message equals "callback abort"
  // assert(
  //   collectExceptionMsg!Exception(callbackFunc.call(results)) == "callback abort",
  //   "Error calling exported function, expected trap!"
  // );

  destroy(instance);
  destroy(module_);
}
