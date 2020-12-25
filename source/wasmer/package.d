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

///
interface Handle {
  bool valid() @property const;
}

///
final class Engine : Handle {
  private wasm_engine_t* engine;

  ///
  this() {
    engine = wasm_engine_new();
  }
  ~this() {
    if (valid) wasm_engine_delete(engine);
    engine = null;
  }

  /// Whether this managed handle to a `wasm_engine_t` is valid.
  bool valid() @property const {
    return engine !is null;
  }

  ///
  const(wasm_engine_t*) handle() @property const {
    return engine;
  }
}

unittest {
  assert(new Engine().valid);
}

/// All runtime objects are tied to a specific store.
///
/// Multiple stores can be created, but their objects cannot interact. Every store and its objects must only be accessed in a single thread.
class Store : Handle {
  ///
  const Engine engine;
  private wasm_store_t* store;

  ///
  this (Engine engine) {
    this.engine = engine;

    store = wasm_store_new(cast(wasm_engine_t*) engine.handle);
  }
  ~this() {
    if (valid) wasm_store_delete(store);
    store = null;
  }

  /// Whether this managed handle to a `wasm_store_t` is valid.
  bool valid() @property const {
    return store !is null;
  }

  ///
  const(wasm_store_t*) handle() @property const {
    return store;
  }
}

unittest {
  const store = new Store(new Engine());
  assert(store.valid);
  destroy(store);
}

/// A WebAssembly module.
class Module : Handle {
  private wasm_module_t* module_;

  ///
  this(Store store, ubyte[] wasmBytes) {
    wasm_byte_vec_t bytes;
    wasm_byte_vec_new(&bytes, wasmBytes.length, cast(char*) wasmBytes.ptr);

    module_ = wasm_module_new(cast(wasm_store_t*) store.handle, &bytes);
    wasm_byte_vec_delete(&bytes);
  }
  ~this() {
    if (valid) wasm_module_delete(module_);
    module_ = null;
  }

  /// Instantiate a module given a string in the WebAssembly <a href="https://webassembly.github.io/spec/core/text/index.html">Text Format</a>.
  static Module from(Store store, string source) {
    wasm_byte_vec_t wat;
    wasm_byte_vec_new(&wat, source.length, source.ptr);
    wasm_byte_vec_t wasmBytes;
    wat2wasm(&wat, &wasmBytes);
    return new Module(store, cast(ubyte[]) wasmBytes.data[0 .. wasmBytes.size]);
  }

  /// Whether this managed handle to a `wasm_module_t` is valid.
  bool valid() @property const {
    return module_ !is null;
  }

  ///
  const(wasm_module_t*) handle() @property const {
    return module_;
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

  private static extern(C) void finalizeHostInfo(T)(void* data) if (is(T == class)) {
    destroy(this.hostInfo!T);
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

  assert(Module.from(store, wat_sum_module).valid, "Error compiling module!");
}

///
class Extern : Handle {
  private wasm_extern_t* extern_;
  ///
  const wasm_externkind_enum kind;

  private this(wasm_extern_t* extern_) {
    this.extern_ = extern_;
    kind = wasm_extern_kind(extern_).to!wasm_externkind_enum;
  }
  ~this() {
    if (valid) wasm_extern_delete(extern_);
    extern_ = null;
  }

  ///
  static Extern from(wasm_extern_t* extern_) {
    return new Extern(extern_);
  }

  /// Whether this managed handle to a `wasm_extern_t` is valid.
  bool valid() @property const {
    return extern_ !is null;
  }

  ///
  const(wasm_extern_t*) handle() @property const {
    return extern_;
  }
}

/// A WebAssembly virtual machine instance.
class Instance : Handle {
  private wasm_instance_t* instance;

  ///
  this(Store store, Module module_, Extern[] imports = []) {
    import std.algorithm : map;
    import std.array : array;

    wasm_extern_vec_t importObject;
    auto importsVecElements = cast(wasm_extern_t**) imports.map!(import_ => import_.handle).array.ptr;
    wasm_extern_vec_new(&importObject, imports.length, importsVecElements);

    instance = wasm_instance_new(
      cast(wasm_store_t*) store.handle, cast(wasm_module_t*) module_.handle, &importObject, null
    );
  }
  ~this() {
    if (valid) wasm_instance_delete(instance);
    instance = null;
  }

  /// Whether this managed handle to a `wasm_instance_t` is valid.
  bool valid() @property const {
    return instance !is null;
  }

  ///
  const(wasm_instance_t*) handle() @property const {
    return instance;
  }

  Extern[] exports() @property const {
    wasm_extern_vec_t exportsVector;
    wasm_instance_exports(instance, &exportsVector);

    auto exports = new Extern[exportsVector.size];
    for (auto i = 0; i < exportsVector.size; i++) {
      exports[i] = Extern.from(exportsVector.data[i]);
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

  destroy(instance);
  destroy(module_);
  destroy(store);
  destroy(engine);
}

/// A WebAssembly value.
class Value : Handle {
  private wasm_val_t* value;
  private const bool borrowed;
  ///
  const wasm_valkind_enum kind;

  ///
  this(wasm_valkind_enum kind) {
    this.kind = kind;
    this.value = new wasm_val_t(kind);
    borrowed = false;
  }
  ///
  this(int value) {
    this.kind = wasm_valkind_enum.WASM_I32;
    this.value = new wasm_val_t;
    this.value.of.i32 = value;
    borrowed = false;
    // wasm_val_init_ptr(this.value, &value);
  }
  ///
  this(long value) {
    this.kind = wasm_valkind_enum.WASM_I64;
    this.value = new wasm_val_t;
    this.value.of.i64 = value;
    borrowed = false;
    // wasm_val_init_ptr(this.value, &value);
  }
  ///
  this(float value) {
    this.kind = wasm_valkind_enum.WASM_F32;
    this.value = new wasm_val_t;
    this.value.of.f32 = value;
    borrowed = false;
    // wasm_val_init_ptr(this.value, &value);
  }
  ///
  this(double value) {
    this.kind = wasm_valkind_enum.WASM_F64;
    this.value = new wasm_val_t;
    this.value.of.f64 = value;
    borrowed = false;
    // wasm_val_init_ptr(this.value, &value);
  }
  private this(wasm_val_t value) {
    this.value = new wasm_val_t(value.kind, value.of);
    this.kind = value.kind.to!wasm_valkind_enum;
    borrowed = false;
  }
  private this(wasm_val_t* value) {
    this.value = value;
    this.kind = value.kind.to!wasm_valkind_enum;
    borrowed = true;
  }
  ~this() {
    if (valid && borrowed) wasm_val_delete(value);
    value = null;
  }

  ///
  static Value from(wasm_val_t value) {
    return new Value(value);
  }

  /// Whether this managed handle to a `wasm_val_t` is valid.
  bool valid() @property const {
    return value !is null;
  }

  ///
  const(wasm_val_t*) handle() @property const {
    return value;
  }
}

/// A function to be called from WASM code.
extern(C) alias Callback = wasm_trap_t* function(const wasm_val_vec_t* arguments, wasm_val_vec_t* results);
/// A function to be called from WASM code. Includes an environment variable.
extern(C) alias CallbackWithEnv = wasm_trap_t* function(
  void* env, const wasm_val_vec_t* arguments, wasm_val_vec_t* results
);

/// A WebAssembly function reference.
class Function : Handle {
  private wasm_func_t* func;

  /// Instantiate a D function to be called from WASM code.
  this(Store store, wasm_functype_t* type, Callback callback) {
    func = wasm_func_new(cast(wasm_store_t*) store.handle, type, callback);
  }
  /// ditto
  this(Store store, wasm_functype_t* type, CallbackWithEnv callback, void* env) {
    func = wasm_func_new_with_env(cast(wasm_store_t*) store.handle, type, callback, env, null);
  }
  private this(wasm_func_t* func) {
    this.func = func;
  }

  ///
  static Function from(Extern extern_) {
    return new Function(wasm_extern_as_func(cast(wasm_extern_t*) extern_.handle));
  }

  /// Whether this managed handle to a `wasm_func_t` is valid.
  bool valid() @property const {
    return func !is null;
  }

  ///
  const(wasm_func_t*) handle() @property const {
    return func;
  }

  ///
  Extern asExtern() @property const {
    return new Extern(wasm_func_as_extern(cast(wasm_func_t*) func));
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
    const funcTrapped = wasm_func_call(func, &args, &resultsVec) !is null;
    wasm_val_vec_delete(&args);
    if (funcTrapped) return false;
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
  auto instance = new Instance(store, module_, imports);
  auto runFunc = Function.from(instance.exports[0]);

  assert(runFunc.valid, "Failed to get the `run` function!");

  Value[] results;
  assert(runFunc.call([new Value(3), new Value(4)], results), "Error calling the `run` function!");
  assert(results.length == 1 && results[0].value.of.i32 == 49);

  destroy(instance);
  destroy(module_);
}
