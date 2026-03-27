
Successfully verified dependencies on-chain against source.
{
  "digest": "J5a2hEyVbeyCDnWNGMwAqfWDr9sosYd197HLJzkiN5rm",
  "transaction": {
    "data": {
      "messageVersion": "v1",
      "transaction": {
        "kind": "ProgrammableTransaction",
        "inputs": [
          {
            "type": "pure",
            "valueType": "address",
            "value": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b"
          }
        ],
        "transactions": [
          {
            "Publish": [
              "0x0000000000000000000000000000000000000000000000000000000000000001",
              "0x0000000000000000000000000000000000000000000000000000000000000002"
            ]
          },
          {
            "TransferObjects": [
              [
                {
                  "Result": 0
                }
              ],
              {
                "Input": 0
              }
            ]
          }
        ]
      },
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "gasData": {
        "payment": [
          {
            "objectId": "0x878b9090ec919686c5cbe3fdaf2542552bb789a90cbdbd01104a7190285c6f4c",
            "version": 6846,
            "digest": "AnZZygrKF74PwhTVgJyx1KyQY1VwpKhRg16h5fdM3MUs"
          }
        ],
        "owner": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
        "price": "1000",
        "budget": "500000000"
      }
    },
    "txSignatures": [
      "AMJjBeHfLqzpx4vFu38j6WsWjHLh9exzFBquWQ65FGI2wtIy0HMLiXG6w00vnDdPnvA9/HZlXu222Fvl34pQswtAy2Oh658eCxFKbc2L+JjwUVRlOOBW4dqgGkix4w/DXg=="
    ]
  },
  "effects": {
    "messageVersion": "v1",
    "status": {
      "status": "success"
    },
    "executedEpoch": "142",
    "gasUsed": {
      "computationCost": "2000000",
      "storageCost": "117815200",
      "storageRebate": "978120",
      "nonRefundableStorageFee": "9880"
    },
    "modifiedAtVersions": [
      {
        "objectId": "0x878b9090ec919686c5cbe3fdaf2542552bb789a90cbdbd01104a7190285c6f4c",
        "sequenceNumber": "6846"
      }
    ],
    "transactionDigest": "J5a2hEyVbeyCDnWNGMwAqfWDr9sosYd197HLJzkiN5rm",
    "created": [
      {
        "owner": {
          "ObjectOwner": "0x7f0bb0aa74733a1bb2ad4c58985a78633dad56c441d92a115e817a79d9e086fa"
        },
        "reference": {
          "objectId": "0x21e9d9b2a5d020562c7dc43fd2c9f4ff1c4ebbf864a0e515273ce77dbb0b2408",
          "version": 6847,
          "digest": "By66L7wGv9VwttUnYoCMbMShknsvqome831gF72TSjZf"
        }
      },
      {
        "owner": {
          "Shared": {
            "initial_shared_version": 6847
          }
        },
        "reference": {
          "objectId": "0x22e918c32c44fe4281dfb29a854e1131f55193b740428429e8752eaad1ed7d33",
          "version": 6847,
          "digest": "HATEHNHTvaiPMPAMuMDrHouD5TsFw71e4EwzQd8T3mKm"
        }
      },
      {
        "owner": {
          "AddressOwner": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b"
        },
        "reference": {
          "objectId": "0x583258ce7773a882dff6c8ee3b6ecc20d46c3594a248453df97cf554eac6bc9b",
          "version": 6847,
          "digest": "CFNPLA5pFtK3MQHQzqXx2LeKks7ZC3q7vnEAUwXBhrXp"
        }
      },
      {
        "owner": {
          "Shared": {
            "initial_shared_version": 6847
          }
        },
        "reference": {
          "objectId": "0xc4638c06e44bcfd52db1539c936531f705b0e283e46563e53e12715790d8a257",
          "version": 6847,
          "digest": "H4TB9D8ZTAoJa3vT2KTYPJqPS2Jz9PCu7WqAfVey3KWq"
        }
      },
      {
        "owner": "Immutable",
        "reference": {
          "objectId": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a",
          "version": 1,
          "digest": "G8JQyT5mtamKzFX3eE8XzQvETg3BWCTMvszWWJhfyqeS"
        }
      }
    ],
    "mutated": [
      {
        "owner": {
          "AddressOwner": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b"
        },
        "reference": {
          "objectId": "0x878b9090ec919686c5cbe3fdaf2542552bb789a90cbdbd01104a7190285c6f4c",
          "version": 6847,
          "digest": "G3UKhoWAKJX51avQ1fnAbHF77jXh5t9QBtvB3Df5JCCb"
        }
      }
    ],
    "gasObject": {
      "owner": {
        "AddressOwner": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b"
      },
      "reference": {
        "objectId": "0x878b9090ec919686c5cbe3fdaf2542552bb789a90cbdbd01104a7190285c6f4c",
        "version": 6847,
        "digest": "G3UKhoWAKJX51avQ1fnAbHF77jXh5t9QBtvB3Df5JCCb"
      }
    },
    "eventsDigest": "3JVxaqY7GKQQFRjEdJDCTSQn3wTpY1JsGUPVdfDyzLx9",
    "dependencies": [
      "9hoAbrZhpF8NoZXdk4DpFPrVRqyudyKJwqQYqtwpg76L",
      "BazzT6FMwS4Z56K5BF5h9nb8EmLQgDzbB5GrLLtZPDEx"
    ]
  },
  "events": [
    {
      "id": {
        "txDigest": "J5a2hEyVbeyCDnWNGMwAqfWDr9sosYd197HLJzkiN5rm",
        "eventSeq": "0"
      },
      "packageId": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a",
      "transactionModule": "price_feed",
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "type": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a::price_feed::PriceFeedCreated",
      "parsedJson": {
        "admin": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
        "feed_id": "0xc4638c06e44bcfd52db1539c936531f705b0e283e46563e53e12715790d8a257"
      },
      "bcsEncoding": "base64",
      "bcs": "xGOMBuRLz9UtsVOck2Ux9wWw4oPkZWPlPhJxV5DYold+ZFUlnNDrIn2FsCc8BtFE2LZ67Hix5vI5gd+T5S2aGw=="
    },
    {
      "id": {
        "txDigest": "J5a2hEyVbeyCDnWNGMwAqfWDr9sosYd197HLJzkiN5rm",
        "eventSeq": "1"
      },
      "packageId": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a",
      "transactionModule": "perpetual_exchange",
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "type": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a::perpetual_exchange::PoolCreated",
      "parsedJson": {
        "pool_id": "0x22e918c32c44fe4281dfb29a854e1131f55193b740428429e8752eaad1ed7d33"
      },
      "bcsEncoding": "base64",
      "bcs": "IukYwyxE/kKB37KahU4RMfVRk7dAQoQp6HUuqtHtfTM="
    }
  ],
  "objectChanges": [
    {
      "type": "mutated",
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "owner": {
        "AddressOwner": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b"
      },
      "objectType": "0x2::coin::Coin<0x2::oct::OCT>",
      "objectId": "0x878b9090ec919686c5cbe3fdaf2542552bb789a90cbdbd01104a7190285c6f4c",
      "version": "6847",
      "previousVersion": "6846",
      "digest": "G3UKhoWAKJX51avQ1fnAbHF77jXh5t9QBtvB3Df5JCCb"
    },
    {
      "type": "created",
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "owner": {
        "ObjectOwner": "0x7f0bb0aa74733a1bb2ad4c58985a78633dad56c441d92a115e817a79d9e086fa"
      },
      "objectType": "0x2::dynamic_field::Field<address, bool>",
      "objectId": "0x21e9d9b2a5d020562c7dc43fd2c9f4ff1c4ebbf864a0e515273ce77dbb0b2408",
      "version": "6847",
      "digest": "By66L7wGv9VwttUnYoCMbMShknsvqome831gF72TSjZf"
    },
    {
      "type": "created",
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "owner": {
        "Shared": {
          "initial_shared_version": 6847
        }
      },
      "objectType": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a::perpetual_exchange::LiquidityPool",
      "objectId": "0x22e918c32c44fe4281dfb29a854e1131f55193b740428429e8752eaad1ed7d33",
      "version": "6847",
      "digest": "HATEHNHTvaiPMPAMuMDrHouD5TsFw71e4EwzQd8T3mKm"
    },
    {
      "type": "created",
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "owner": {
        "AddressOwner": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b"
      },
      "objectType": "0x2::package::UpgradeCap",
      "objectId": "0x583258ce7773a882dff6c8ee3b6ecc20d46c3594a248453df97cf554eac6bc9b",
      "version": "6847",
      "digest": "CFNPLA5pFtK3MQHQzqXx2LeKks7ZC3q7vnEAUwXBhrXp"
    },
    {
      "type": "created",
      "sender": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b",
      "owner": {
        "Shared": {
          "initial_shared_version": 6847
        }
      },
      "objectType": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a::price_feed::PriceFeed",
      "objectId": "0xc4638c06e44bcfd52db1539c936531f705b0e283e46563e53e12715790d8a257",
      "version": "6847",
      "digest": "H4TB9D8ZTAoJa3vT2KTYPJqPS2Jz9PCu7WqAfVey3KWq"
    },
    {
      "type": "published",
      "packageId": "0xfc6cada19d744f2e08efeb3b7551e8aa040b2b8dc396519cd07b44c9ac3a9a8a",
      "version": "1",
      "digest": "G8JQyT5mtamKzFX3eE8XzQvETg3BWCTMvszWWJhfyqeS",
      "modules": [
        "perp_fees",
        "perp_liquidation",
        "perp_math",
        "perp_positions",
        "perpetual_exchange",
        "price_feed"
      ]
    }
  ],
  "balanceChanges": [
    {
      "owner": {
        "AddressOwner": "0x7e6455259cd0eb227d85b0273c06d144d8b67aec78b1e6f23981df93e52d9a1b"
      },
      "coinType": "0x2::oct::OCT",
      "amount": "-118837080"
    }
  ],
  "timestampMs": "1765060144923",
  "confirmedLocalExecution": true,
  "checkpoint": "56636103"
}