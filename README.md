# wasmer-d

[![DUB Package](https://img.shields.io/dub/v/wasmer.svg)](https://code.dlang.org/packages/wasmer)
[![wasmer-d CI](https://github.com/chances/wasmer-d/workflows/wasmer-d%20CI/badge.svg)](https://github.com/chances/wasmer-d/actions)
[![codecov](https://codecov.io/gh/chances/wasmer-d/branch/master/graph/badge.svg?token=U6BqigvJI6)](https://codecov.io/gh/chances/wasmer-d)

D bindings to [wasmer](https://wasmer.io/), a standalone WebAssembly runtime for running WebAssembly outside of the browser.

Also includes an idiomatic D wrapper of the [Wasmer Runtime C API](https://github.com/wasmerio/wasmer/tree/master/lib/c-api#readme).

## Usage

```json
"dependencies": {
    "wasmer": "0.1.0-alpha.2"
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
auto instance = new Instance(store, module_);
auto sumFunc = Function.from(instance.exports[0]);

assert(engine.valid && store.valid && module_.valid && instance.valid && sumFunc.valid, "Could not instantiate module!");

Value[] results;
assert(sumFunc.call([new Value(3), new Value(4)], results), "Error calling the `sum` function!");
assert(results.length == 1 && results[0].value.of.i32 == 7);
```

## License

[MIT Licence](https://opensource.org/licenses/MIT)

Copyright &copy; 2020 Chance Snow. All rights reserved.
