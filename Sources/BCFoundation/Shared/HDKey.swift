//
//  HDKey.swift
//  BCFoundation
//
//  Created by Wolf McNally on 10/4/21.
//

import Foundation
import WolfBase
@_exported import BCWally
@_exported import URKit

public enum HDKeyError: Error {
    case invalidSeed
    case invalidBase58
    case cannotDerivePrivateFromPublic
    case cannotDeriveHardenedFromPublic
    case cannotDeriveFromNonDerivable
    case cannotDeriveInspecificStep
    case invalidDepth
    case unknownDerivationError
    case invalidFormat
}

public protocol HDKeyProtocol: IdentityDigestable {
    var isMaster: Bool { get }
    var keyType: KeyType { get }
    var keyData: Data { get }
    var chainCode: Data? { get }
    var useInfo: UseInfo { get }
    var parent: DerivationPath { get }
    var children: DerivationPath { get }
    var parentFingerprint: UInt32? { get }

    init(isMaster: Bool, keyType: KeyType, keyData: Data, chainCode: Data?, useInfo: UseInfo, parent: DerivationPath?, children: DerivationPath?, parentFingerprint: UInt32?)
    init(_ key: HDKeyProtocol)
}

public struct HDKey: HDKeyProtocol {
    public let isMaster: Bool
    public let keyType: KeyType
    public let keyData: Data
    public let chainCode: Data?
    public let useInfo: UseInfo
    public let parent: DerivationPath
    public let children: DerivationPath
    public let parentFingerprint: UInt32?
    
    public init(isMaster: Bool, keyType: KeyType, keyData: Data, chainCode: Data?, useInfo: UseInfo, parent: DerivationPath?, children: DerivationPath?, parentFingerprint: UInt32?) {
        self.isMaster = isMaster
        self.keyType = keyType
        self.keyData = keyData
        self.chainCode = chainCode
        self.useInfo = useInfo
        self.parent = parent ?? .init()
        self.children = children ?? .init()
        self.parentFingerprint = parentFingerprint
    }

    // Copy constructor
    public init(_ key: HDKeyProtocol) {
        self.isMaster = key.isMaster
        self.keyType = key.keyType
        self.keyData = key.keyData
        self.chainCode = key.chainCode
        self.useInfo = key.useInfo
        self.parent = key.parent
        self.children = key.children
        self.parentFingerprint = key.parentFingerprint
    }
}

extension HDKeyProtocol {
    public init(key: HDKeyProtocol, derivedKeyType: KeyType? = nil, isDerivable: Bool = true, parent: DerivationPath? = nil, children: DerivationPath? = nil) throws {
        let derivedKeyType = derivedKeyType ?? key.keyType
        
        guard key.keyType == .private || derivedKeyType == .public else {
            // public -> private
            throw HDKeyError.cannotDerivePrivateFromPublic
        }

        let keyData: Data
        if key.keyType == derivedKeyType {
            // private -> private
            // public -> public
            keyData = key.keyData
        } else {
            // private -> public
            keyData = Data(of: key.wallyExtKey.pub_key)
        }
        
        self.init(
            isMaster: key.isMaster,
            keyType: derivedKeyType,
            keyData: keyData,
            chainCode: isDerivable ? key.chainCode : nil,
            useInfo: key.useInfo,
            parent: parent ?? key.parent,
            children: children ?? key.children,
            parentFingerprint: key.parentFingerprint
        )
    }
    
    public init(wallyExtKey key: WallyExtKey, useInfo: UseInfo? = nil, parent: DerivationPath? = nil, children: DerivationPath? = nil) throws {
        let keyData: Data
        if key.isPrivate {
            keyData = Data(of: key.priv_key)
        } else {
            keyData = Data(of: key.pub_key)
        }

        let steps: [DerivationStep]
        if key.child_num == 0 {
            steps = []
        } else {
            steps = [DerivationStep(rawValue: key.child_num)]
        }
        let newParent: DerivationPath
        if let parent = parent {
            newParent = parent
        } else {
            let o = DerivationPath.Origin.fingerprint(Wally.fingerprint(for: key))
            newParent = DerivationPath(steps: steps, origin: o, depth: Int(key.depth))
        }
        
        let useInfo = useInfo ?? .init()
        
        self.init(
            isMaster: key.isMaster,
            keyType: KeyType(isPrivate: key.isPrivate),
            keyData: keyData,
            chainCode: Data(of: key.chain_code),
            useInfo: UseInfo(asset: useInfo.asset, network: key.network!),
            parent: parent ?? newParent,
            children: children,
            parentFingerprint: deserialize(UInt32.self, Data(of: key.parent160))!
        )
    }

    public init(base58: String, useInfo: UseInfo? = nil, parent: DerivationPath? = nil, children: DerivationPath? = nil, overrideOriginFingerprint: UInt32? = nil) throws {
        guard let key = Wally.hdKey(fromBase58: base58) else {
            throw HDKeyError.invalidBase58
        }
        let isMaster: Bool
        if let parent = parent {
            isMaster = parent.isMaster
        } else {
            isMaster = key.isMaster
        }
        let keyData: Data
        if key.isPrivate {
            keyData = Data(of: key.priv_key)
        } else {
            keyData = Data(of: key.pub_key)
        }
        
        let newParent: DerivationPath
        if let parent = parent {
            newParent = parent
        } else {
            let steps: [DerivationStep]
            if key.child_num == 0 {
                steps = []
            } else {
                steps = [DerivationStep(rawValue: key.child_num)]
            }
            let originFingerprint = overrideOriginFingerprint ?? Wally.fingerprint(for: key)
            let o = DerivationPath.Origin.fingerprint(originFingerprint)
            newParent = DerivationPath(steps: steps, origin: o, depth: Int(key.depth))
        }
        let parentFingerprint: UInt32?
        if isMaster {
            parentFingerprint = nil
        } else {
            parentFingerprint = deserialize(UInt32.self, Data(of: key.parent160))!
        }
        let useInfo = useInfo ?? .init()
        self.init(
            isMaster: isMaster,
            keyType: KeyType(isPrivate: key.isPrivate),
            keyData: keyData,
            chainCode: Data(of: key.chain_code),
            useInfo: UseInfo(asset: useInfo.asset, network: key.network!),
            parent: newParent,
            children: children,
            parentFingerprint: parentFingerprint
        )
    }
    
    public init(bip39Seed: BIP39.Seed, useInfo: UseInfo? = nil, parent: DerivationPath? = nil, children: DerivationPath? = nil) throws {
        let useInfo = useInfo ?? .init()
        guard let key = Wally.hdKey(bip39Seed: bip39Seed.data, network: useInfo.network) else {
            // From libwally-core docs:
            // The entropy passed in may produce an invalid key. If this happens, WALLY_ERROR will be returned
            // and the caller should retry with new entropy.
            throw HDKeyError.invalidSeed
        }
        self.init(
            isMaster: true,
            keyType: .private,
            keyData: Data(of: key.priv_key),
            chainCode: Data(of: key.chain_code),
            useInfo: useInfo,
            parent: parent ?? DerivationPath(origin: .fingerprint(Wally.fingerprint(for: key))),
            children: children,
            parentFingerprint: nil
        )
    }
    
    public init(seed: Seed, useInfo: UseInfo? = nil, parent: DerivationPath? = nil, children: DerivationPath? = nil) throws {
        try self.init(bip39Seed: BIP39.Seed(bip39: seed.bip39), useInfo: useInfo, parent: parent, children: children)
    }

    public init(parent: HDKey, derivedKeyType: KeyType? = nil, childDerivation: DerivationStep, wildcardChildNum: UInt32? = nil) throws {
        let derivedKeyType = derivedKeyType ?? parent.keyType
        
        guard parent.keyType == .private || derivedKeyType == .public else {
            throw HDKeyError.cannotDerivePrivateFromPublic
        }
        guard parent.isDerivable else {
            throw HDKeyError.cannotDeriveFromNonDerivable
        }
                
        guard let childNum = childDerivation.rawValue(wildcardChildNum: wildcardChildNum) else {
            throw HDKeyError.cannotDeriveInspecificStep
        }
        guard let derivedKey = Wally.key(from: parent.wallyExtKey, childNum: childNum, isPrivate: derivedKeyType.isPrivate) else {
            throw HDKeyError.unknownDerivationError
        }
                
        let origin: DerivationPath
        let parentOrigin = parent.parent
        var steps = parentOrigin.steps
        steps.append(childDerivation)
        let sourceFingerprint = parentOrigin.originFingerprint ?? parent.keyFingerprint
        let depth: Int
        if let parentDepth = parentOrigin.depth {
            depth = parentDepth + 1
        } else {
            depth = 1
        }
        origin = DerivationPath(steps: steps, origin: .fingerprint(sourceFingerprint), depth: depth)
        self.init(
            isMaster: false,
            keyType: derivedKeyType,
            keyData: derivedKeyType == .private ? Data(of: derivedKey.priv_key) : Data(of: derivedKey.pub_key),
            chainCode: Data(of: derivedKey.chain_code),
            useInfo: parent.useInfo,
            parent: origin,
            children: nil,
            parentFingerprint: parent.keyFingerprint
        )
    }
    
    public init(parent: HDKey, derivedKeyType: KeyType? = nil, childDerivationPath: DerivationPath, isDerivable: Bool = true, wildcardChildNum: UInt32? = nil, privateKeyProvider: PrivateKeyProvider? = nil, children: DerivationPath? = nil) throws {
        let derivedKeyType = derivedKeyType ?? parent.keyType
        
        guard parent.isDerivable else {
            throw HDKeyError.cannotDeriveFromNonDerivable
        }

        var effectiveDerivationPath = childDerivationPath
        if effectiveDerivationPath.origin != nil {
            let parentDepth = parent.parent.effectiveDepth
            guard let p = childDerivationPath.dropFirst(parentDepth) else {
                throw HDKeyError.invalidDepth
            }
            effectiveDerivationPath = p
        }

        var workingKey = parent
        if parent.keyType == .public {
            if derivedKeyType == .private {
                throw HDKeyError.cannotDerivePrivateFromPublic
            } else if effectiveDerivationPath.isHardened {
                guard
                    let privateKeyProvider = privateKeyProvider,
                    let privateKey = privateKeyProvider(workingKey),
                    privateKey.isPrivate
                else {
                    throw HDKeyError.cannotDeriveHardenedFromPublic
                }
                workingKey = privateKey
            }
        }

        var derivedKey = workingKey
        for step in effectiveDerivationPath.steps {
            derivedKey = try HDKey(parent: derivedKey, derivedKeyType: parent.keyType, childDerivation: step, wildcardChildNum: wildcardChildNum)
        }
        derivedKey = try HDKey(key: derivedKey, derivedKeyType: derivedKeyType)
        self.init(
            isMaster: false,
            keyType: derivedKeyType,
            keyData: derivedKey.keyData,
            chainCode: isDerivable ? derivedKey.chainCode : nil,
            useInfo: parent.useInfo,
            parent: derivedKey.parent,
            children: children ?? derivedKey.children,
            parentFingerprint: derivedKey.parentFingerprint
        )
 }
    
    public var isPrivate: Bool {
        keyType.isPrivate
    }
    
    public var isDerivable: Bool {
        chainCode != nil
    }

    public var requiresWildcardChildNum: Bool {
        children.hasWildcard
    }

    public var originFingerprint: UInt32? {
        parent.originFingerprint
    }
    
    public var keyFingerprintData: Data {
        Wally.fingerprintData(for: wallyExtKey)
    }

    public var keyFingerprint: UInt32 {
        Wally.fingerprint(for: wallyExtKey)
    }
    
    public var `public`: HDKey {
        try! HDKey(key: self, derivedKeyType: .public)
    }
    
    public var base58: String {
        base58PrivateKey ?? base58PublicKey ?? "invalid"
    }
    
    public var base58PublicKey: String? {
        Wally.base58(from: wallyExtKey, isPrivate: false)
    }
    
    public var base58PrivateKey: String? {
        Wally.base58(from: wallyExtKey, isPrivate: true)
    }
    
    public var ecPublicKey: ECCompressedPublicKey {
        ECCompressedPublicKey(Data(of: wallyExtKey.pub_key))!
    }

    public var ecPrivateKey: ECPrivateKey? {
        if !isPrivate {
            return nil
        }
        var data = Data(of: wallyExtKey.priv_key)
        // skip prefix byte 0
        precondition(data.popFirst() != nil)
        return ECPrivateKey(data)!
    }

    public var wallyExtKey: ext_key {
        var k = ext_key()
        
        let effectiveDepth = parent.effectiveDepth
        if effectiveDepth > 0 {
            k.depth = UInt8(effectiveDepth)

            if let lastStep = parent.steps.last,
               case let ChildIndexSpec.index(childIndex) = lastStep.childIndexSpec {
                let value = childIndex.value
                let isHardened = lastStep.isHardened
                let childNum = value | (isHardened ? 0x80000000 : 0)
                k.child_num = childNum
            }
        }
        
        switch keyType {
        case .private:
            keyData.store(into: &k.priv_key)
            Wally.updatePublicKey(in: &k)
            switch useInfo.network {
            case .mainnet:
                k.version = UInt32(BIP32_VER_MAIN_PRIVATE)
            case .testnet:
                k.version = UInt32(BIP32_VER_TEST_PRIVATE)
            }
        case .public:
            k.priv_key.0 = 0x01;
            keyData.store(into: &k.pub_key)
            switch useInfo.network {
            case .mainnet:
                k.version = UInt32(BIP32_VER_MAIN_PUBLIC)
            case .testnet:
                k.version = UInt32(BIP32_VER_TEST_PUBLIC)
            }
        }
        
        Wally.updateHash160(in: &k)
        
        if let chainCode = chainCode {
            chainCode.store(into: &k.chain_code)
        }
        
        if let parentFingerprint = parentFingerprint {
            parentFingerprint.serialized.store(into: &k.parent160)
        }
        
        k.checkValid()
        return k
    }

    public func description(withParent: Bool = false, withChildren: Bool = false) -> String {
        var comps: [String] = []
        if withParent && !parent.isEmpty {
            comps.append("[\(parent)]")
        }
        comps.append(base58)
        if withChildren && !children.isEmpty {
            comps.append("/\(children)")
        }
        return comps.joined()
    }

    public var fullDescription: String {
        description(withParent: true, withChildren: true)
    }
}

extension HDKeyProtocol {
    public func cbor(nameLimit: Int = .max, noteLimit: Int = .max) -> CBOR {
        var a: [OrderedMapEntry] = []

        if isMaster {
            a.append(.init(key: 1, value: true))
        }

        if keyType == .private {
            a.append(.init(key: 2, value: true))
        }

        a.append(.init(key: 3, value: CBOR.byteString(keyData.bytes)))

        if let chainCode = chainCode {
            a.append(.init(key: 4, value: CBOR.byteString(chainCode.bytes)))
        }

        if !useInfo.isDefault {
            a.append(.init(key: 5, value: useInfo.taggedCBOR))
        }

        if !parent.isEmpty {
            a.append(.init(key: 6, value: parent.taggedCBOR))
        }

        if !children.isEmpty {
            a.append(.init(key: 7, value: children.taggedCBOR))
        }

        if let parentFingerprint = parentFingerprint {
            a.append(.init(key: 8, value: CBOR.unsignedInt(UInt64(parentFingerprint))))
        }

        return CBOR.orderedMap(a)
    }

    public var taggedCBOR: CBOR {
        CBOR.tagged(.hdKey, cbor())
    }

    public var ur: UR {
        return try! UR(type: "crypto-hdkey", cbor: cbor())
    }

    public var sizeLimitedUR: UR {
        return try! UR(type: "crypto-hdkey", cbor: cbor(nameLimit: 100, noteLimit: 500))
    }
}

extension HDKeyProtocol {
    public init(cbor: CBOR) throws {
        guard case let CBOR.map(pairs) = cbor
        else {
            // Doesn't contain a map.
            throw HDKeyError.invalidFormat
        }

        guard case let CBOR.boolean(isMaster) = pairs[1] ?? CBOR.boolean(false)
        else {
            // Invalid `isMaster` field.
            throw HDKeyError.invalidFormat
        }

        guard case let CBOR.boolean(isPrivate) = pairs[2] ?? CBOR.boolean(isMaster)
        else {
            // Invalid `isPrivate` field.
            throw HDKeyError.invalidFormat
        }
        if isMaster && !isPrivate {
            // Master key cannot be public
            throw HDKeyError.invalidFormat
        }

        guard
            case let CBOR.byteString(keyDataValue) = pairs[3] ?? CBOR.null,
            keyDataValue.count == 33
        else {
            // Invalid key data.
            throw HDKeyError.invalidFormat
        }
        let keyData = Data(keyDataValue)

        let chainCode: Data?
        if let chainCodeItem = pairs[4] {
            guard
                case let CBOR.byteString(chainCodeValue) = chainCodeItem,
                chainCodeValue.count == 32
            else {
                // Invalid key chain code.
                throw HDKeyError.invalidFormat
            }
            chainCode = Data(chainCodeValue)
        } else {
            chainCode = nil
        }

        let useInfo: UseInfo
        if let useInfoItem = pairs[5] {
            useInfo = try UseInfo(taggedCBOR: useInfoItem)
        } else {
            useInfo = UseInfo()
        }

        let origin: DerivationPath?
        if let originItem = pairs[6] {
            origin = try DerivationPath(taggedCBOR: originItem)
        } else {
            origin = nil
        }

        let children: DerivationPath?
        if let childrenItem = pairs[7] {
            children = try DerivationPath(taggedCBOR: childrenItem)
        } else {
            children = nil
        }

        let parentFingerprint: UInt32?
        if let parentFingerprintItem = pairs[8] {
            guard
                case let CBOR.unsignedInt(parentFingerprintValue) = parentFingerprintItem,
                parentFingerprintValue > 0,
                parentFingerprintValue <= UInt32.max
            else {
                // Invalid parent fingerprint.
                throw HDKeyError.invalidFormat
            }
            parentFingerprint = UInt32(parentFingerprintValue)
        } else {
            parentFingerprint = nil
        }

        let keyType: KeyType = isPrivate ? .private : .public

        self.init(HDKey(isMaster: isMaster, keyType: keyType, keyData: keyData, chainCode: chainCode, useInfo: useInfo, parent: origin, children: children, parentFingerprint: parentFingerprint))
    }

    public init(taggedCBOR: CBOR) throws {
        guard case let CBOR.tagged(.hdKey, cbor) = taggedCBOR else {
            // Tag (303) not found
            throw HDKeyError.invalidFormat
        }
        try self.init(cbor: cbor)
    }
}

extension HDKeyProtocol {
    public var identityDigestSource: Data {
        var result: [CBOR] = []

        result.append(CBOR.byteString(keyData.bytes))

        if let chainCode = chainCode {
            result.append(CBOR.byteString(chainCode.bytes))
        } else {
            result.append(CBOR.null)
        }

        result.append(CBOR.unsignedInt(UInt64(useInfo.asset.rawValue)))
        result.append(CBOR.unsignedInt(UInt64(useInfo.network.rawValue)))

        return Data(result.encode())
    }
}
