# wasmer-d

[![DUB Package](https://img.shields.io/dub/v/wasmer.svg)](https://code.dlang.org/packages/wasmer)
[![wasmer-d CI](https://github.com/chances/wasmer-d/workflows/wasmer-d%20CI/badge.svg)](https://github.com/chances/wasmer-d/actions)
[![codecov](https://codecov.io/gh/chances/wasmer-d/branch/master/graph/badge.svg?token=U6BqigvJI6)](https://codecov.io/gh/chances/wasmer-d)

D bindings to [wasmer](https://wasmer.io/), a standalone WebAssembly runtime for running WebAssembly outside of the browser.

Also includes an idiomatic D wrapper of the [Wasmer Runtime C API](https://github.com/wasmerio/wasmer/tree/master/lib/c-api#readme).

## Usage

```json
"dependencies": {
    "wasmer": "0.1.0"
}
```

See the official [Wasmer Runtime C API](https://github.com/wasmerio/wasmer/tree/master/lib/c-api#readme) documentation.

### Run a WebAssembly Module

Sum function in a WebAssembly [text format](https://webassembly.github.io/spec/core/text/index.html) module:

```d
const string wat_sum_module =
  "(module\n" ~
  "  (type $sum_t (func (param i32 i32) (result i32)))\n" ~
  "  (func $sum_f (type $sum_t) (param $x i32) (param $y i32) (result i32)\n" ~
  "    local.get $x\n" ~
  "    local.get $y\n" ~
  "    i32.add)\n" ~
  "  (export \"sum\" (func $sum_f)))";

auto engine = new Engine();
auto store = new Store(engine);
auto module_ = Module.from(store, wat_sum_module);
assert(engine.valid && store.valid && module_.valid, "Could not load module!");

auto instance = new Instance(store, module_);
assert(instance.valid, "Could not instantiate module!");

assert(instance.exports[0].name == "sum");
auto sumFunc = Function.from(instance.exports[0]);
assert(sumFunc.valid, "Could not load exported 'sum' function!");

Value[] results;
assert(sumFunc.call([new Value(3), new Value(4)], results), "Error calling the `sum` function!");
assert(results.length == 1 && results[0].value.of.i32 == 7);
```

### Import a D Function into a WebAssembly Module

```d
const string wat_callback_module =
  "(module" ~
  "  (func $print (import \"\" \"print\") (param i32) (result i32))" ~
  "  (func (export \"run\") (param $x i32) (param $y i32) (result i32)" ~
  "    (call $print (i32.add (local.get $x) (local.get $y)))" ~
  "  )" ~
  ")";

auto engine = new Engine();
auto store = new Store(engine);
auto module_ = Module.from(store, wat_callback_module);
assert(module_.valid, "Error compiling module!");

auto print = (Module module_, int value) => {
  return value;
}();
auto imports = [new Function(store, module_, print.toDelegate).asExtern];
auto instance = module_.instantiate(imports);
assert(instance.valid, "Could not instantiate module!");

auto runFunc = Function.from(instance.exports[0]);
assert(instance.exports[0].name == "run" && runFunc.valid, "Failed to get the `run` function!");

auto three = new Value(3);
auto four = new Value(4);
Value[] results;
assert(runFunc.call([three, four], results), "Error calling the `run` function!");
assert(results.length == 1 && results[0].value.of.i32 == 7);

destroy(three);
destroy(four);
destroy(instance);
destroy(module_);
```

## License

[MIT Licence](https://opensource.org/licenses/MIT)

Copyright &copy; 2020-2021 Chance Snow. All rights reserved.
