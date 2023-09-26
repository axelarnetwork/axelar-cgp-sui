# Axelar CGP Sui

An implementation of the Axelar gateway for the Sui blockchain.

## Installation

Install Sui and run a local Sui network: https://docs.sui.io/build/sui-local-network.

## Scripts

First run `node scripts/publish-package` and then any of `node scripts/<testScritpt>` which can be `test-receive-call`, `test-send-call`, and `test-transfer-operatorship`.

## Gateway

The gateway lives in a few modules but has all of its storage in a single shared object called `AxelarValidators`. This is not very aptly named and we might rename it.

## Relayer Spec

Relaying to Sui is a bit complicated: the concept of 'smart contracts' is quite warped compared to EVM chains. 

### The Problems

Firstly, all perstistent storage stems from `Objects` that have the `key` property and are either shared or owned by an account. These objects have a specific `type`, which is defined in a certain module, and only that module can access their storage (either to read or to write to it). This means that instead of calling a smart contract with some data, in Sui one needs to call a module, pass the Objects that are to be modified as arguments, alongside extra arguments that specify the kind of change that should occur. This additionally means that the concept of `msg.sender` does not apply to applications, and a certain `capability` object that functions like a 'key' to unlock certain functionality needs to be used instead.

The second issue is the lack of interfaces whatsoever. It is impossible for a module to ever call a module that is published at a later time. This means applications that want to interface with future applications must be called by those future applications, but need to call pre-existing ones. To expand on this, we expect contract calls that are received to potentially modify the storage of multiple objects in a single call, which makes it impossible to require modules to implement a 'standardized' function that a relayer will call, because the number of arguments required varies depending on the application (or the type of call).

Finally, we do not want to require the payload of incoming calls to have a certain format, because that would mean that working applications that want to exapnd to Sui need to redesign their working protocoll to accomodate Sui, discouraging them from doing so.

### The Solutions

First of all, as we mentioned before, for applications to 'validate' themselves with other applications need to use a `capability` object. This object will be called `Channel`, and it will hold information about the executed contract calls as well. It has a field called `id` which specifies the 'address' of the application for the purposed of incoming and outgoing extenral calls. This `id` has to match the `id` of a shared object that is passed in the channel creation method (alongside a witness for security). This shared object can easily be querried by the relayer to get call fullfilment information. Specifically:
- The shared object has to have a field called `get_call_info_object_ids` that is a `vector<address>`.
- The module that defined the shared object type has to implement a function called `get_call_info`, which has no types, and takes the incoming call `payload` as the first argument, followed by a number of shared objects whose ids are specified by the `get_call_info_object_ids` mentioned above. This function has to return a `std::ascii::String` which is the JSON encoded call data to fullfill the contract call.
- This calldata has the following 3 fields:
  - `target`: the target method, in the form of `packag_iId::module_name::function_name`.
  - `arguments`: an array of arguments that can be:
    - `contractCall`: the `ApprovedCall` object (see below).
    - `pure:${info}`: a pure argument specified by `$info`.
    - `obj:${objectId}`: a shared object with the specified `id`.