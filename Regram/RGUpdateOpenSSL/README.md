# Update signer crypto isolation

Telegram's network encryption provider uses BoringSSL. Its BN/EVP/ASN1 functions must not resolve to another OpenSSL implementation. The update signer uses the pinned OpenSSL 1.1.1d source with its own `RGUpdateSSL_` symbol namespace and `RGUpdateOpenSSL/openssl` include path.

The build keeps OpenSSL's original preprocessing, then rewrites all object symbol definitions and references in the static archive, retaining relocation indexes. The archive index is regenerated with Apple's ranlib. Only consumers include the generated API prefix header. This avoids OpenSSL's function-name `#ifndef` guards and token-pasting definitions changing behavior under forced compiler macros.

`symbols.txt` is generated from the pinned no-assembly crypto archive (`xcrun nm -g -U -j`) and supplies client API names. The build also inventories its own definitions and refuses to export any unprefixed crypto symbol. Original OpenSSL headers are rewritten into an independent include tree, so the network provider continues including BoringSSL headers.

The macOS `//Regram/RGUpdateSigner:CryptoCoexistenceTests` links the actual network provider and update signer together and compares 10,000 arithmetic cycles plus 1,000 full-size Curve25519 connection-hello polynomials. The signer fixture check separately verifies every page and signature slot on the app and six extensions. Both checks use synthetic input and avoid production certificates.
