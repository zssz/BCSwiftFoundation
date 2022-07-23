//
//  TxOutput.swift
//  BCFoundation
//
//  Created by Wolf McNally on 11/21/20.
//

import Foundation
import BCWally

public struct TxOutput {
    public let scriptPubKey: ScriptPubKey
    public var amount: Satoshi

    public func address(network: Network) -> String {
        Bitcoin.Address(scriptPubKey: self.scriptPubKey, network: network)!.description
    }

    public init(scriptPubKey: ScriptPubKey, amount: Satoshi) {
        self.scriptPubKey = scriptPubKey
        self.amount = amount
    }

    public func createWallyOutput() -> WallyTxOutput {
        scriptPubKey.script.data.withUnsafeByteBuffer { scriptPubKeyBytes in
            var output: WallyTxOutput!
            precondition(wally_tx_output_init_alloc(amount, scriptPubKeyBytes.baseAddress, scriptPubKeyBytes.count, &output) == WALLY_OK)
            return output
        }
    }
}

extension TxOutput: CustomStringConvertible {
    public var description: String {
        "TxOutput(scriptPubKey: \(scriptPubKey), amount: \(amount.btcFormat))"
    }
}
