// MARK: Regram — reproduce the network arithmetic path with the update signer linked.
#import <Foundation/Foundation.h>
#import <OpenSSLEncryptionProvider/OpenSSLEncryptionProvider.h>
#import "RGUpdateSigner.h"
#include <RGUpdateOpenSSL/openssl/bn.h>
#include <RGUpdateOpenSSL/openssl/sha.h>
#include <stdlib.h>

static void require(bool value) { if (!value) abort(); }

extern "C" void RGCheckCryptoCoexistence() {
    @autoreleasepool {
        OpenSSLEncryptionProvider *provider = [OpenSSLEncryptionProvider new];
        BN_CTX *signerContext = BN_CTX_new();
        BIGNUM *signerA = BN_new(), *signerB = BN_new(), *signerMod = BN_new(), *signerResult = BN_new();
        require(signerContext && signerA && signerB && signerMod && signerResult);
        for (unsigned long i = 1; i <= 10000; i++) {
            // These objects are allocated by BoringSSL inside the network provider.
            id<MTBignumContext> network = [provider createBignumContext];
            id<MTBignum> a = [network create], b = [network create], modulus = [network create], result = [network create], expected = [network create];
            [network assignWordTo:a value:i];
            [network assignWordTo:b value:100];
            [network assignWordTo:modulus value:127];
            [network assignWordTo:expected value:(i + 100) % 127];
            require([network modAddInto:result a:a b:b mod:modulus]);
            require([network compare:result with:expected] == 0);
            // Signer big numbers have an independent ABI and implementation.
            require(BN_set_word(signerA, i) && BN_set_word(signerB, 100) && BN_set_word(signerMod, 127));
            require(BN_mod_add(signerResult, signerA, signerB, signerMod, signerContext));
            require(BN_get_word(signerResult) == (i + 100) % 127);
            require([network modMulInto:result a:a b:b mod:modulus]);
            [network assignWordTo:expected value:(i * 100) % 127];
            require([network compare:result with:expected] == 0);
        }
        // Exercise the exact Curve25519 polynomial from MTTcpConnection.get_y2
        // with full-size numbers, as used when creating the connection hello.
        require(BN_hex2bn(&signerMod, "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED") > 0);
        for (unsigned long i = 1; i <= 1000; i++) {
            unsigned char input[32];
            for (unsigned long j = 0; j < 32; j++) input[j] = (unsigned char)((i * 17 + j * 31) & 255);
            input[0] &= 0x7f;
            id<MTBignumContext> network = [provider createBignumContext];
            id<MTBignum> x = [network create], modulus = [network create], coef = [network create];
            [network assignBinTo:x value:[NSData dataWithBytes:input length:32]];
            [network assignHexTo:modulus value:@"7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED"];
            id<MTBignum> y = [network clone:x];
            [network assignWordTo:coef value:486662];
            require([network modAddInto:y a:y b:coef mod:modulus]);
            require([network modMulInto:y a:y b:x mod:modulus]);
            [network assignOneTo:coef];
            require([network modAddInto:y a:y b:coef mod:modulus]);
            require([network modMulInto:y a:y b:x mod:modulus]);
            require(BN_bin2bn(input, 32, signerA) != nullptr && BN_set_word(signerB, 486662));
            require(BN_mod_add(signerResult, signerA, signerB, signerMod, signerContext));
            require(BN_mod_mul(signerResult, signerResult, signerA, signerMod, signerContext));
            require(BN_set_word(signerB, 1));
            require(BN_mod_add(signerResult, signerResult, signerB, signerMod, signerContext));
            require(BN_mod_mul(signerResult, signerResult, signerA, signerMod, signerContext));
            unsigned char expected[32];
            int count = BN_bn2bin(signerResult, expected);
            require([[network getBin:y] isEqualToData:[NSData dataWithBytes:expected length:count]]);
        }
        unsigned char digest[SHA256_DIGEST_LENGTH];
        require(SHA256((const unsigned char *)"abc", 3, digest) != nullptr);
        require(digest[0] == 0xba && digest[31] == 0xad);
        NSError *error = nil;
        require([RGUpdateSigner validateCertificate:[NSData data] password:@"" installedApp:@"/nonexistent" error:&error] == nil && error.code == 1);
        BN_free(signerA); BN_free(signerB); BN_free(signerMod); BN_free(signerResult); BN_CTX_free(signerContext);
        puts("Crypto coexistence passed: 10,000 arithmetic cycles, 1,000 connection-hello polynomials, digest and signer entry point.");
    }
}
