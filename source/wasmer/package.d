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

  /// Whether this managed handle to a `wasm_engine_t` is valid.
  bool valid() @property const {
    return engine !is null;
  }

  ///
  const(wasm_engine_t*) handle() @property const {
    return engine;
  }
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

/// A WebAssembly module.
class Module : Handle {
  private wasm_module_t* module_;

  ///
  this(Store store, ubyte[] wasmBytes) {
    wasm_byte_vec_t* bytes;
    wasm_byte_vec_new_uninitialized(bytes, wasmBytes.length);
    bytes.data = cast(char*) wasmBytes.ptr;

    module_ = wasm_module_new(cast(wasm_store_t*) store.handle, bytes);
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

///
class Extern : Handle {
  private wasm_extern_t* extern_;

  private this(wasm_extern_t* extern_) {
    this.extern_ = extern_;
  }
  ~this() {
    if (valid) wasm_extern_delete(extern_);
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

    wasm_extern_vec_t* importObject;
    wasm_extern_vec_new_uninitialized(importObject, imports.length);
    importObject.data = cast(wasm_extern_t**) imports.map!(import_ => import_.handle).array.ptr;

    instance = wasm_instance_new(
      cast(wasm_store_t*) store.handle, cast(wasm_module_t*) module_.handle, importObject, null
    );
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

/// A WebAssembly value reference.
class Value : Handle {
  private wasm_val_t* value;
  private wasm_valtype_t* type;
  ///
  const wasm_valkind_enum kind;

  ///
  this(wasm_valkind_enum kind) {
    type = wasm_valtype_new(kind);
    this.kind = kind;
  }
  ///
  this(ref int value) {
    this.type = wasm_valtype_new_i32();
    this.kind = wasm_valkind_enum.WASM_I32;
    wasm_val_init_ptr(this.value, &value);
  }
  ///
  this(ref long value) {
    this.type = wasm_valtype_new_i64();
    this.kind = wasm_valkind_enum.WASM_I64;
    wasm_val_init_ptr(this.value, &value);
  }
  ///
  this(ref float value) {
    this.type = wasm_valtype_new_f32();
    this.kind = wasm_valkind_enum.WASM_F32;
    wasm_val_init_ptr(this.value, &value);
  }
  ///
  this(ref double value) {
    this.type = wasm_valtype_new_f64();
    this.kind = wasm_valkind_enum.WASM_F64;
    wasm_val_init_ptr(this.value, &value);
  }
  private this(wasm_val_t* value) {
    this.value = value;
    this.type = wasm_valtype_new(value.kind);
    this.kind = value.kind.to!wasm_valkind_enum;
  }

  ///
  static Value from(wasm_val_t* value) {
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

/// A WebAssembly function reference.
class Function : Handle {
  private wasm_func_t* func;

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
  bool call(Value[] arguments, out Value[] results) {
    import std.algorithm : map;
    import std.array : array;

    wasm_val_vec_t* args;
    wasm_val_vec_new(args, arguments.length, arguments.map!(param => *param.handle).array.ptr);

    wasm_val_vec_t* resultsVec;
    if (wasm_func_call(func, args, resultsVec) !is null) {
      return false;
    }
    results = new Value[resultsVec.size];
    for (auto i = 0; i < resultsVec.size; i += 1) {
      results[i] = Value.from(&resultsVec.data[i]);
    }

    return true;
  }
}
