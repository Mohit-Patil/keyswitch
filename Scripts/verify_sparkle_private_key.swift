#!/usr/bin/env swift

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(65)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: verify_sparkle_private_key.swift <private-key-file> <expected-public-key>")
}

let seedPath = CommandLine.arguments[1]
let expectedPublicKey = CommandLine.arguments[2]

let encodedSeed: String
do {
    encodedSeed = try String(
        contentsOfFile: seedPath,
        encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
} catch {
    fail("unable to read the Sparkle private key file")
}

guard let seedData = Data(base64Encoded: encodedSeed),
      seedData.count == 32 else {
    fail("Sparkle private key must be a base64-encoded 32-byte Ed25519 seed")
}

let signer: Curve25519.Signing.PrivateKey
do {
    signer = try Curve25519.Signing.PrivateKey(
        rawRepresentation: seedData
    )
} catch {
    fail("Sparkle private key is invalid")
}

let actualPublicKey = signer.publicKey.rawRepresentation.base64EncodedString()
guard actualPublicKey == expectedPublicKey else {
    fail("Sparkle private key does not match the public key embedded in KeySwitch")
}

print(actualPublicKey)
