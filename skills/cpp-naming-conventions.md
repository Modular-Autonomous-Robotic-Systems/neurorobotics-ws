All C++ code in this workspace must follow these naming conventions.

- Use camelCase as the general naming convention.
- All methods must start with a title case name, for example `void ExampleMethod()`.
- All member variables must be prefixed with `m` to denote they are member variables, for example `mCounter`.
- All private member variables must be prefixed with `mp` to denote they are private member variables, for example `mpInternalState`.
- All vector or array type member variables must be prefixed with `mv`, for example `mvPoints`. Private vector or array member variables must be prefixed with `mvp`, for example `mvpInternalPoints`. Method-local vector or array variables must be prefixed with `v`, for example `vResults`.
- Mutex member variables must be prefixed with `mMtx`, for example `mMtxDataGuard`. Private mutex member variables must be prefixed with `mpMtx`, for example `mpMtxInternalLock`.
