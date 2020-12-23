# Third-Party Components

## [wasmer C API](https://github.com/wasmerio/wasmer/tree/master/lib/c-api#readme)

1. [Installl Wasmer locally](https://github.com/wasmerio/wasmer-install#readme)
2. Ensure wasmer is exposed in the current shell, i.e.:

  ```bash
  export WASMER_DIR="/home/$USER/.wasmer"
  [ -s "$WASMER_DIR/wasmer.sh" ] && source "$WASMER_DIR/wasmer.sh"
  ```
