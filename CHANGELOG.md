# @axelar-network/axelar-cgp-sui

## 0.4.1

### Patch Changes

-   cf4ead4: Fixed publish error in docker container environment by removing the tmp package.
-   fd297c7: Added Bag and Operator bcs structs
-   d86325e: Renamed test package to example

## 0.4.0

### Minor Changes

-   523e24c: Use hot potato pattern with `sui::borrow` package for loan out a capabilities in operators contract.

### Patch Changes

-   86d7fa3: Include gas payment into test contract's `send_call` function
-   ab7235b: Remove postinstall script and src directory from published content

## 0.3.1

### Patch Changes

-   86d7fa3: Include gas payment into test contract's `send_call` function
-   ab7235b: Remove postinstall script and src directory from published content

## 0.3.0

### Minor Changes

-   5e28d52: Update to the Sui Typescript SDK v1

### Patch Changes

-   5c829ce: Remove all hardcoded addresses

## 0.2.0

### Minor Changes

-   b1f9ca6: added previous signer retention in gateway setup
-   7441218: move source copy util to avoid modifying sources in place
-   2dc62d0: move package build util

### Patch Changes

-   1b8d4b6: Added UID type
