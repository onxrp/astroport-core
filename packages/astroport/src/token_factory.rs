pub use cosmos_sdk_proto::cosmos::base::v1beta1::Coin as ProtoCoin;
use cosmwasm_std::{Binary, Coin, CosmosMsg, CustomMsg, StdError};

#[cfg(feature = "injective")]
use cosmwasm_std::BankMsg;

use prost::Message;

#[cfg(not(feature = "coreum"))]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgCreateDenomResponse {
    #[prost(string, tag = "1")]
    pub new_token_denom: ::prost::alloc::string::String,
}

#[cfg(not(feature = "coreum"))]
impl MsgCreateDenomResponse {
    pub fn to_proto_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        self.encode(&mut buf).unwrap();
        buf
    }
}

#[cfg(not(feature = "coreum"))]
impl From<MsgCreateDenomResponse> for Binary {
    fn from(msg: MsgCreateDenomResponse) -> Self {
        Binary(msg.to_proto_bytes())
    }
}

#[cfg(not(feature = "coreum"))]
impl TryFrom<Binary> for MsgCreateDenomResponse {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(
                format!(
                    "MsgCreateDenomResponse Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                    binary,
                    binary.to_vec(),
                    e
                ),
            )
        })
    }
}

#[cfg(feature = "coreum")]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct EmptyResponse {}

#[cfg(feature = "coreum")]
impl EmptyResponse {
    pub const TYPE_URL: &'static str = "/coreum.asset.ft.v1.EmptyResponse";
    pub fn to_proto_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        self.encode(&mut buf).unwrap();
        buf
    }
}

#[cfg(feature = "coreum")]
impl From<EmptyResponse> for Binary {
    fn from(msg: EmptyResponse) -> Self {
        Binary(msg.to_proto_bytes())
    }
}

#[cfg(feature = "coreum")]
impl TryFrom<Binary> for EmptyResponse {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(
                format!(
                    "EmptyResponse Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                    binary,
                    binary.to_vec(),
                    e
                ),
            )
        })
    }
}

#[cfg(not(feature = "coreum"))]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgCreateDenom {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    /// subdenom can be up to 44 "alphanumeric" characters long.
    #[prost(string, tag = "2")]
    pub subdenom: ::prost::alloc::string::String,
}

#[cfg(not(feature = "coreum"))]
impl MsgCreateDenom {
    #[cfg(not(feature = "injective"))]
    pub const TYPE_URL: &'static str = "/osmosis.tokenfactory.v1beta1.MsgCreateDenom";
    #[cfg(feature = "injective")]
    pub const TYPE_URL: &'static str = "/injective.tokenfactory.v1beta1.MsgCreateDenom";
}

#[cfg(not(feature = "coreum"))]
impl TryFrom<Binary> for MsgCreateDenom {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(format!(
                "MsgCreateDenom Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                binary,
                binary.to_vec(),
                e
            ))
        })
    }
}

#[cfg(feature = "coreum")]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgIssue {
    #[prost(string, tag = "1")]
    pub issuer: ::prost::alloc::string::String,
    #[prost(string, tag = "2")]
    pub symbol: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub subunit: ::prost::alloc::string::String,
    #[prost(uint32, tag = "4")]
    pub precision: u32,
    #[prost(string, tag = "5")]
    pub initial_amount: ::prost::alloc::string::String,
    #[prost(string, tag = "6")]
    pub description: ::prost::alloc::string::String,
    #[prost(enumeration = "Feature", repeated, tag = "7")]
    pub features: ::prost::alloc::vec::Vec<i32>,
    /// burn_rate is a number between 0 and 1 which will be multiplied by send amount to determine
    /// burn_amount. This value will be burnt on top of the send amount.
    #[prost(string, tag = "8")]
    pub burn_rate: ::prost::alloc::string::String,
    /// send_commission_rate is a number between 0 and 1 which will be multiplied by send amount to determine
    /// amount sent to the token admin account.
    #[prost(string, tag = "9")]
    pub send_commission_rate: ::prost::alloc::string::String,
    #[prost(string, tag = "10")]
    pub uri: ::prost::alloc::string::String,
    #[prost(string, tag = "11")]
    pub uri_hash: ::prost::alloc::string::String,
    /// extension_settings must be provided in case wasm extensions are enabled.
    #[prost(message, optional, tag = "12")]
    pub extension_settings: ::core::option::Option<ExtensionIssueSettings>,
    /// dex_settings allowed to be customized by issuer
    #[prost(message, optional, tag = "13")]
    pub dex_settings: ::core::option::Option<DexSettings>,
}

/// Feature defines possible features of fungible token.
#[cfg(feature = "coreum")]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum Feature {
    Minting = 0,
    Burning = 1,
    Freezing = 2,
    Whitelisting = 3,
    Ibc = 4,
    BlockSmartContracts = 5,
    Clawback = 6,
    Extension = 7,
    DexBlock = 8,
    DexWhitelistedDenoms = 9,
    DexOrderCancellation = 10,
    DexUnifiedRefAmountChange = 11,
}
#[cfg(feature = "coreum")]
impl Feature {
    /// String value of the enum field names used in the ProtoBuf definition.
    ///
    /// The values are not transformed in any way and thus are considered stable
    /// (if the ProtoBuf definition does not change) and safe for programmatic use.
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Feature::Minting => "minting",
            Feature::Burning => "burning",
            Feature::Freezing => "freezing",
            Feature::Whitelisting => "whitelisting",
            Feature::Ibc => "ibc",
            Feature::BlockSmartContracts => "block_smart_contracts",
            Feature::Clawback => "clawback",
            Feature::Extension => "extension",
            Feature::DexBlock => "dex_block",
            Feature::DexWhitelistedDenoms => "dex_whitelisted_denoms",
            Feature::DexOrderCancellation => "dex_order_cancellation",
            Feature::DexUnifiedRefAmountChange => "dex_unified_ref_amount_change",
        }
    }
    /// Creates an enum from field names used in the ProtoBuf definition.
    pub fn from_str_name(value: &str) -> ::core::option::Option<Self> {
        match value {
            "minting" => Some(Self::Minting),
            "burning" => Some(Self::Burning),
            "freezing" => Some(Self::Freezing),
            "whitelisting" => Some(Self::Whitelisting),
            "ibc" => Some(Self::Ibc),
            "block_smart_contracts" => Some(Self::BlockSmartContracts),
            "clawback" => Some(Self::Clawback),
            "extension" => Some(Self::Extension),
            "dex_block" => Some(Self::DexBlock),
            "dex_whitelisted_denoms" => Some(Self::DexWhitelistedDenoms),
            "dex_order_cancellation" => Some(Self::DexOrderCancellation),
            "dex_unified_ref_amount_change" => Some(Self::DexUnifiedRefAmountChange),
            _ => None,
        }
    }
}

/// ExtensionIssueSettings are settings that will be used to Instantiate the smart contract which contains
/// the source code for the extension.
#[cfg(feature = "coreum")]
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ExtensionIssueSettings {
    /// code_id is the reference to the stored WASM code
    #[prost(uint64, tag = "1")]
    pub code_id: u64,
    /// label is optional metadata to be stored with a contract instance.
    #[prost(string, tag = "2")]
    pub label: ::prost::alloc::string::String,
    /// funds coins that are transferred to the contract on instantiation
    #[prost(message, repeated, tag = "3")]
    pub funds: ::prost::alloc::vec::Vec<cosmos_sdk_proto::cosmos::base::v1beta1::Coin>,
    /// optional json encoded data to pass to WASM on instantiation by the ft issuer
    #[prost(bytes = "vec", tag = "4")]
    pub issuance_msg: ::prost::alloc::vec::Vec<u8>,
}

/// DEXSettings defines the token settings of the dex.
#[cfg(feature = "coreum")]
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, Eq, ::prost::Message)]
pub struct DexSettings {
    /// unified_ref_amount is the approximate amount you need to buy 1USD, used to define the price tick size
    #[prost(string, tag = "1")]
    pub unified_ref_amount: ::prost::alloc::string::String,
    /// whitelisted_denoms is the list of denoms to trade with.
    #[prost(string, repeated, tag = "2")]
    pub whitelisted_denoms: ::prost::alloc::vec::Vec<::prost::alloc::string::String>,
}

#[cfg(feature = "coreum")]
impl MsgIssue {
    pub const TYPE_URL: &'static str = "/coreum.asset.ft.v1.MsgIssue";
}

#[cfg(feature = "coreum")]
impl TryFrom<Binary> for MsgIssue {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(format!(
                "MsgIssue Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                binary,
                binary.to_vec(),
                e
            ))
        })
    }
}

#[cfg(not(any(feature = "coreum", feature = "injective")))]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgBurn {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub amount: ::core::option::Option<cosmos_sdk_proto::cosmos::base::v1beta1::Coin>,
    #[prost(string, tag = "3")]
    pub burn_from_address: ::prost::alloc::string::String,
}

#[cfg(feature = "injective")]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgBurn {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub amount: ::core::option::Option<cosmos_sdk_proto::cosmos::base::v1beta1::Coin>,
}

#[cfg(feature = "coreum")]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgBurn {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    /// Coreum's MsgBurn puts `coin` on tag 3, unlike MsgMint which puts it on tag 2 -
    /// do not "helpfully" align these, they are genuinely different on the wire.
    #[prost(message, optional, tag = "3")]
    pub coin: ::core::option::Option<cosmos_sdk_proto::cosmos::base::v1beta1::Coin>,
}

impl MsgBurn {
    #[cfg(not(any(feature = "coreum", feature = "injective")))]
    pub const TYPE_URL: &'static str = "/osmosis.tokenfactory.v1beta1.MsgBurn";
    #[cfg(feature = "injective")]
    pub const TYPE_URL: &'static str = "/injective.tokenfactory.v1beta1.MsgBurn";
    #[cfg(feature = "coreum")]
    pub const TYPE_URL: &'static str = "/coreum.asset.ft.v1.MsgBurn";
}

impl TryFrom<Binary> for MsgBurn {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(format!(
                "MsgBurn Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                binary,
                binary.to_vec(),
                e
            ))
        })
    }
}

#[cfg(not(any(feature = "coreum", feature = "injective")))]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgMint {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub amount: ::core::option::Option<cosmos_sdk_proto::cosmos::base::v1beta1::Coin>,
    #[prost(string, tag = "3")]
    pub mint_to_address: ::prost::alloc::string::String,
}

#[cfg(feature = "injective")]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgMint {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub amount: ::core::option::Option<cosmos_sdk_proto::cosmos::base::v1beta1::Coin>,
}

#[cfg(feature = "coreum")]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgMint {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub coin: ::core::option::Option<cosmos_sdk_proto::cosmos::base::v1beta1::Coin>,
    #[prost(string, tag = "3")]
    pub recipient: ::prost::alloc::string::String,
}

impl MsgMint {
    #[cfg(not(any(feature = "coreum", feature = "injective")))]
    pub const TYPE_URL: &'static str = "/osmosis.tokenfactory.v1beta1.MsgMint";
    #[cfg(feature = "injective")]
    pub const TYPE_URL: &'static str = "/injective.tokenfactory.v1beta1.MsgMint";
    #[cfg(feature = "coreum")]
    pub const TYPE_URL: &'static str = "/coreum.asset.ft.v1.MsgMint";
}

impl TryFrom<Binary> for MsgMint {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(format!(
                "MsgMint Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                binary,
                binary.to_vec(),
                e
            ))
        })
    }
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgSetBeforeSendHook {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    #[prost(string, tag = "2")]
    pub denom: ::prost::alloc::string::String,
    #[prost(string, tag = "3")]
    pub cosmwasm_address: ::prost::alloc::string::String,
}

impl MsgSetBeforeSendHook {
    pub const TYPE_URL: &'static str = "/osmosis.tokenfactory.v1beta1.MsgSetBeforeSendHook";
}

impl TryFrom<Binary> for MsgSetBeforeSendHook {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(format!(
                "MsgSetBeforeSendHook Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                binary,
                binary.to_vec(),
                e
            ))
        })
    }
}

/// MsgSetDenomMetadata is the sdk.Msg type for allowing an admin account to set
/// the denom's bank metadata
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct MsgSetDenomMetadata {
    #[prost(string, tag = "1")]
    pub sender: ::prost::alloc::string::String,
    #[prost(message, optional, tag = "2")]
    pub metadata: ::core::option::Option<Metadata>,
}

/// Metadata represents a struct that describes
/// a basic token.
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Metadata {
    #[prost(string, tag = "1")]
    pub description: ::prost::alloc::string::String,
    /// denom_units represents the list of DenomUnit's for a given coin
    #[prost(message, repeated, tag = "2")]
    pub denom_units: ::prost::alloc::vec::Vec<DenomUnit>,
    /// base represents the base denom (should be the DenomUnit with exponent = 0).
    #[prost(string, tag = "3")]
    pub base: ::prost::alloc::string::String,
    /// display indicates the suggested denom that should be
    /// displayed in clients.
    #[prost(string, tag = "4")]
    pub display: ::prost::alloc::string::String,
    /// name defines the name of the token (eg: Cosmos Atom)
    ///
    /// Since: cosmos-sdk 0.43
    #[prost(string, tag = "5")]
    pub name: ::prost::alloc::string::String,
    /// symbol is the token symbol usually shown on exchanges (eg: ATOM). This can
    /// be the same as the display.
    ///
    /// Since: cosmos-sdk 0.43
    #[prost(string, tag = "6")]
    pub symbol: ::prost::alloc::string::String,
    /// URI to a document (on or off-chain) that contains additional information. Optional.
    ///
    /// Since: cosmos-sdk 0.46
    #[prost(string, tag = "7")]
    pub uri: ::prost::alloc::string::String,
    /// URIHash is a sha256 hash of a document pointed by URI. It's used to verify that
    /// the document didn't change. Optional.
    ///
    /// Since: cosmos-sdk 0.46
    #[prost(string, tag = "8")]
    pub uri_hash: ::prost::alloc::string::String,
}

/// DenomUnit represents a struct that describes a given
/// denomination unit of the basic token.
#[allow(clippy::derive_partial_eq_without_eq)]
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct DenomUnit {
    /// denom represents the string name of the given denom unit (e.g uatom).
    #[prost(string, tag = "1")]
    pub denom: ::prost::alloc::string::String,
    /// exponent represents power of 10 exponent that one must
    /// raise the base_denom to in order to equal the given DenomUnit's denom
    /// 1 denom = 10^exponent base_denom
    /// (e.g. with a base_denom of uatom, one can create a DenomUnit of 'atom' with
    /// exponent = 6, thus: 1 atom = 10^6 uatom).
    #[prost(uint32, tag = "2")]
    pub exponent: u32,
    /// aliases is a list of string aliases for the given denom
    #[prost(string, repeated, tag = "3")]
    pub aliases: ::prost::alloc::vec::Vec<::prost::alloc::string::String>,
}

impl MsgSetDenomMetadata {
    pub const TYPE_URL: &'static str = "/osmosis.tokenfactory.v1beta1.MsgSetDenomMetadata";
}

impl TryFrom<Binary> for MsgSetDenomMetadata {
    type Error = StdError;
    fn try_from(binary: Binary) -> Result<Self, Self::Error> {
        Self::decode(binary.as_slice()).map_err(|e| {
            StdError::generic_err(format!(
                "MsgSetDenomMetadata Unable to decode binary: \n  - base64: {}\n  - bytes array: {:?}\n\n{:?}",
                binary,
                binary.to_vec(),
                e
            ))
        })
    }
}

#[cfg(not(feature = "coreum"))]
pub fn tf_create_denom_msg<T>(sender: impl Into<String>, denom: impl Into<String>) -> CosmosMsg<T>
where
    T: CustomMsg,
{
    let create_denom_msg = MsgCreateDenom {
        sender: sender.into(),
        subdenom: denom.into(),
    };

    CosmosMsg::Stargate {
        type_url: MsgCreateDenom::TYPE_URL.to_string(),
        value: Binary::from(create_denom_msg.encode_to_vec()),
    }
}

/// Issues the contract's own denom (the LP share token, or xASTRO for staking).
///
/// Only `minting` is requested, and that is deliberate on both counts.
///
/// `burning` is absent because it is not needed. Coreum lets the token admin burn
/// its own balance whether or not the feature is set -- it is the one feature with
/// an explicit admin exemption (`IsFeatureAllowed` in x/asset/ft/types/token.go).
/// The issuing contract is the admin, so `tf_burn_msg` works regardless. What the
/// feature actually grants is the right for *other holders* to burn, which for an
/// LP token means destroying a claim on the pool without withdrawing against it:
/// the burner loses their deposit and the remaining holders absorb it.
///
/// `freezing` is absent because no contract here ever sends a freeze, and the
/// admin is the contract rather than a human operator, so nobody can. Requesting
/// it only advertised on chain that these tokens are freezable. It is not inert
/// either: a frozen holder cannot send LP tokens to the pair, which is how a
/// withdrawal starts.
///
/// Features are immutable after issue -- there is no MsgUpdateFeatures, and the v1
/// upgrade path only ever adds `ibc`. Denoms already live keep whatever they were
/// issued with; this only affects newly created ones.
#[cfg(feature = "coreum")]
pub fn tf_create_denom_msg<T>(sender: impl Into<String>, denom: impl Into<String>) -> CosmosMsg<T>
where
    T: CustomMsg,
{
    use cosmwasm_std::Uint128;

    let symbol = denom.into();
    let create_denom_msg = MsgIssue {
        issuer: sender.into(),
        subunit: symbol.clone(),
        symbol: symbol,
        precision: 6,
        initial_amount: Uint128::zero().to_string(),
        features: vec![Feature::Minting as i32],
        ..MsgIssue::default()
    };

    CosmosMsg::Stargate {
        type_url: MsgIssue::TYPE_URL.to_string(),
        value: Binary::from(create_denom_msg.encode_to_vec()),
    }
}

/// Same as [`tf_create_denom_msg`], plus the metadata fields. See that function for
/// why `minting` is the only feature requested.
#[cfg(feature = "coreum")]
pub fn tf_issue_msg<T>(
    sender: impl Into<String>,
    denom: impl Into<String>,
    description: impl Into<String>,
    uri: impl Into<String>,
    uri_hash: impl Into<String>,
) -> CosmosMsg<T>
where
    T: CustomMsg,
{
    use cosmwasm_std::Uint128;

    let symbol = denom.into();
    let create_denom_msg = MsgIssue {
        issuer: sender.into(),
        subunit: symbol.clone(),
        symbol: symbol,
        precision: 6,
        initial_amount: Uint128::zero().to_string(),
        features: vec![Feature::Minting as i32],
        description: description.into(),
        uri: uri.into(),
        uri_hash: uri_hash.into(),
        ..MsgIssue::default()
    };

    CosmosMsg::Stargate {
        type_url: MsgIssue::TYPE_URL.to_string(),
        value: Binary::from(create_denom_msg.encode_to_vec()),
    }
}

pub fn tf_mint_msg<T>(
    sender: impl Into<String>,
    coin: Coin,
    receiver: impl Into<String>,
) -> Vec<CosmosMsg<T>>
where
    T: CustomMsg,
{
    let sender_addr: String = sender.into();
    let receiver_addr: String = receiver.into();

    #[cfg(not(any(feature = "coreum", feature = "injective")))]
    let mint_msg = MsgMint {
        sender: sender_addr.clone(),
        amount: Some(ProtoCoin {
            denom: coin.denom.to_string(),
            amount: coin.amount.to_string(),
        }),
        mint_to_address: receiver_addr.clone(),
    };

    #[cfg(feature = "injective")]
    let mint_msg = MsgMint {
        sender: sender_addr.clone(),
        amount: Some(ProtoCoin {
            denom: coin.denom.to_string(),
            amount: coin.amount.to_string(),
        }),
    };

    #[cfg(feature = "coreum")]
    let mint_msg = MsgMint {
        sender: sender_addr.clone(),
        coin: Some(ProtoCoin {
            denom: coin.denom.to_string(),
            amount: coin.amount.to_string(),
        }),
        recipient: receiver_addr.clone(),
    };

    #[cfg(not(feature = "injective"))]
    return vec![CosmosMsg::Stargate {
        type_url: MsgMint::TYPE_URL.to_string(),
        value: Binary::from(mint_msg.encode_to_vec()),
    }];

    #[cfg(feature = "injective")]
    if sender_addr == receiver_addr {
        vec![CosmosMsg::Stargate {
            type_url: MsgMint::TYPE_URL.to_string(),
            value: Binary::from(mint_msg.encode_to_vec()),
        }]
    } else {
        vec![
            CosmosMsg::Stargate {
                type_url: MsgMint::TYPE_URL.to_string(),
                value: Binary::from(mint_msg.encode_to_vec()),
            },
            BankMsg::Send {
                to_address: receiver_addr,
                amount: vec![coin],
            }
            .into(),
        ]
    }
}

pub fn tf_burn_msg<T>(sender: impl Into<String>, coin: Coin) -> CosmosMsg<T>
where
    T: CustomMsg,
{
    #[cfg(not(any(feature = "coreum", feature = "injective")))]
    let burn_msg = MsgBurn {
        sender: sender.into(),
        amount: Some(ProtoCoin {
            denom: coin.denom,
            amount: coin.amount.to_string(),
        }),
        burn_from_address: "".to_string(),
    };

    #[cfg(feature = "injective")]
    let burn_msg = MsgBurn {
        sender: sender.into(),
        amount: Some(ProtoCoin {
            denom: coin.denom,
            amount: coin.amount.to_string(),
        }),
    };

    #[cfg(feature = "coreum")]
    let burn_msg = MsgBurn {
        sender: sender.into(),
        coin: Some(ProtoCoin {
            denom: coin.denom,
            amount: coin.amount.to_string(),
        }),
    };

    CosmosMsg::Stargate {
        type_url: MsgBurn::TYPE_URL.to_string(),
        value: Binary::from(burn_msg.encode_to_vec()),
    }
}

pub fn tf_before_send_hook_msg<T>(
    sender: impl Into<String>,
    denom: impl Into<String>,
    cosmwasm_address: impl Into<String>,
) -> CosmosMsg<T>
where
    T: CustomMsg,
{
    let msg = MsgSetBeforeSendHook {
        sender: sender.into(),
        denom: denom.into(),
        cosmwasm_address: cosmwasm_address.into(),
    };

    CosmosMsg::Stargate {
        type_url: MsgSetBeforeSendHook::TYPE_URL.to_string(),
        value: Binary::from(msg.encode_to_vec()),
    }
}

pub fn tf_set_denom_metadata_msg<T>(
    sender: impl Into<String>,
    metadata: impl Into<Metadata>,
) -> CosmosMsg<T>
where
    T: CustomMsg,
{
    let msg = MsgSetDenomMetadata {
        sender: sender.into(),
        metadata: Some(metadata.into()),
    };

    CosmosMsg::Stargate {
        type_url: MsgSetDenomMetadata::TYPE_URL.to_string(),
        value: Binary::from(msg.encode_to_vec()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pulls the raw protobuf bytes out of a `CosmosMsg::Stargate`, panicking on any other
    /// variant since every message built in this module is a Stargate message.
    fn stargate_value(msg: CosmosMsg) -> Vec<u8> {
        match msg {
            CosmosMsg::Stargate { value, .. } => value.to_vec(),
            other => panic!("expected CosmosMsg::Stargate, got {other:?}"),
        }
    }

    fn stargate_type_url(msg: &CosmosMsg) -> &str {
        match msg {
            CosmosMsg::Stargate { type_url, .. } => type_url,
            other => panic!("expected CosmosMsg::Stargate, got {other:?}"),
        }
    }

    #[cfg(feature = "coreum")]
    #[test]
    fn tf_burn_msg_encodes_coin_on_tag_3() {
        let sender = "sender_addr";
        let coin = Coin::new(100u128, "uusd");

        let msg: CosmosMsg = tf_burn_msg(sender, coin);
        assert_eq!(stargate_type_url(&msg), "/coreum.asset.ft.v1.MsgBurn");

        let bytes = stargate_value(msg);

        // Wire-format breakdown (field number << 3 | wire type, then length-delimited payload):
        //   0x0a, 0x0b            -> field 1 (sender), wire type 2 (length-delimited), len 11
        //   "sender_addr"         -> 11 payload bytes
        //   0x1a, 0x0b            -> field 3 (coin), wire type 2, len 11
        //     0x0a, 0x04, "uusd"  -> nested field 1 (denom), len 4
        //     0x12, 0x03, "100"   -> nested field 2 (amount), len 3
        #[rustfmt::skip]
        let expected: Vec<u8> = vec![
            0x0a, 0x0b, b's', b'e', b'n', b'd', b'e', b'r', b'_', b'a', b'd', b'd', b'r',
            0x1a, 0x0b,
                0x0a, 0x04, b'u', b'u', b's', b'd',
                0x12, 0x03, b'1', b'0', b'0',
        ];

        assert_eq!(
            bytes, expected,
            "encoded MsgBurn bytes do not match the hand-computed wire format"
        );

        // This is the regression check for the original bug: Coreum's MsgBurn.coin lives on
        // tag 3 (key 0x1a), not tag 2 (key 0x12) like MsgMint.coin. If the coin field is ever
        // moved back to tag 2, wasmd/prost will still encode *something*, but the assetft
        // module on Coreum will parse an empty coin from the unexpected tag and reject the
        // message with "invalid denom:" (empty) - exactly the on-chain failure this fixes.
        //
        // The key byte for the *top-level* coin field is the byte right after the sender
        // field's payload (13 bytes: 2-byte key/len header + 11-byte "sender_addr"), so we
        // check that specific position rather than scanning the whole buffer - 0x12 also
        // legitimately appears deeper in the message as the nested Coin.amount field's key.
        let coin_field_key = bytes[13];
        assert_eq!(
            coin_field_key, 0x1a,
            "expected key byte 0x1a (field 3, wire type 2) for MsgBurn's top-level coin \
             field, found {coin_field_key:#04x}; if this is 0x12 (field 2), the coin field \
             regressed off tag 3, which would make Coreum receive an empty coin and reject \
             withdraw_liquidity with \"invalid denom:\""
        );
        assert_ne!(
            coin_field_key, 0x12,
            "MsgBurn's top-level coin field is encoded with key 0x12 (field 2, wire type 2); \
             Coreum's chain does not recognize field 2 for MsgBurn's coin - the coin would \
             arrive empty and be rejected with \"invalid denom:\""
        );
    }

    #[cfg(feature = "coreum")]
    #[test]
    fn tf_mint_msg_encodes_coin_on_tag_2_and_recipient_on_tag_3() {
        let sender = "sender_addr";
        let recipient = "recipient_addr";
        let coin = Coin::new(100u128, "uusd");

        let msgs: Vec<CosmosMsg> = tf_mint_msg(sender, coin, recipient);
        assert_eq!(msgs.len(), 1);
        assert_eq!(stargate_type_url(&msgs[0]), "/coreum.asset.ft.v1.MsgMint");

        let bytes = stargate_value(msgs.into_iter().next().unwrap());

        // Wire-format breakdown:
        //   0x0a, 0x0b            -> field 1 (sender), len 11
        //   "sender_addr"         -> 11 payload bytes
        //   0x12, 0x0b            -> field 2 (coin), wire type 2, len 11
        //     0x0a, 0x04, "uusd"  -> nested field 1 (denom), len 4
        //     0x12, 0x03, "100"   -> nested field 2 (amount), len 3
        //   0x1a, 0x0e            -> field 3 (recipient), len 14
        //   "recipient_addr"      -> 14 payload bytes
        #[rustfmt::skip]
        let expected: Vec<u8> = vec![
            0x0a, 0x0b, b's', b'e', b'n', b'd', b'e', b'r', b'_', b'a', b'd', b'd', b'r',
            0x12, 0x0b,
                0x0a, 0x04, b'u', b'u', b's', b'd',
                0x12, 0x03, b'1', b'0', b'0',
            0x1a, 0x0e, b'r', b'e', b'c', b'i', b'p', b'i', b'e', b'n', b't', b'_', b'a', b'd', b'd', b'r',
        ];

        assert_eq!(
            bytes, expected,
            "encoded MsgMint bytes do not match the hand-computed wire format"
        );

        // MsgMint.coin is correctly on tag 2 (key 0x12) - locked down so it isn't accidentally
        // "fixed" to match MsgBurn's tag 3 by someone aligning the two structs.
        assert!(
            bytes.windows(2).any(|w| w == [0x12, 0x0b]),
            "expected MsgMint's coin field on tag 2 (key 0x12) with length 11"
        );
    }

    #[cfg(feature = "coreum")]
    #[test]
    fn tf_burn_msg_round_trips_through_decode() {
        let sender = "sender_addr";
        let coin = Coin::new(100u128, "uusd");

        let msg: CosmosMsg = tf_burn_msg(sender, coin);
        let bytes = stargate_value(msg);

        let decoded = MsgBurn::try_from(Binary::from(bytes)).unwrap();
        assert_eq!(decoded.sender, "sender_addr");
        let decoded_coin = decoded.coin.expect("coin must decode back");
        assert_eq!(decoded_coin.denom, "uusd");
        assert_eq!(decoded_coin.amount, "100");
    }

    #[cfg(feature = "coreum")]
    #[test]
    fn tf_mint_msg_round_trips_through_decode() {
        let sender = "sender_addr";
        let recipient = "recipient_addr";
        let coin = Coin::new(100u128, "uusd");

        let msgs: Vec<CosmosMsg> = tf_mint_msg(sender, coin, recipient);
        let bytes = stargate_value(msgs.into_iter().next().unwrap());

        let decoded = MsgMint::try_from(Binary::from(bytes)).unwrap();
        assert_eq!(decoded.sender, "sender_addr");
        assert_eq!(decoded.recipient, "recipient_addr");
        let decoded_coin = decoded.coin.expect("coin must decode back");
        assert_eq!(decoded_coin.denom, "uusd");
        assert_eq!(decoded_coin.amount, "100");
    }

    #[cfg(feature = "coreum")]
    #[test]
    fn tf_create_denom_msg_encodes_populated_msg_issue_fields_on_expected_tags() {
        // tf_create_denom_msg only populates: issuer (1), symbol (2), subunit (3),
        // precision (4), initial_amount (5), features (7, packed repeated enum).
        let msg: CosmosMsg = tf_create_denom_msg("issuer_addr", "utoken");
        assert_eq!(stargate_type_url(&msg), "/coreum.asset.ft.v1.MsgIssue");

        let bytes = stargate_value(msg);

        // Wire-format breakdown:
        //   0x0a, 0x0b, "issuer_addr" -> field 1 (issuer), len 11
        //   0x12, 0x06, "utoken"      -> field 2 (symbol), len 6
        //   0x1a, 0x06, "utoken"      -> field 3 (subunit), len 6
        //   0x20, 0x06                -> field 4 (precision), varint 6
        //   0x2a, 0x01, "0"           -> field 5 (initial_amount), len 1
        //   0x3a, 0x01, 0x00          -> field 7 (features), wire type 2 (packed repeated
        //                                enum, proto3 default), len 1, varint [0]
        //                                (Feature::Minting)
        #[rustfmt::skip]
        let expected: Vec<u8> = vec![
            0x0a, 0x0b, b'i', b's', b's', b'u', b'e', b'r', b'_', b'a', b'd', b'd', b'r',
            0x12, 0x06, b'u', b't', b'o', b'k', b'e', b'n',
            0x1a, 0x06, b'u', b't', b'o', b'k', b'e', b'n',
            0x20, 0x06,
            0x2a, 0x01, b'0',
            0x3a, 0x01, 0x00,
        ];

        assert_eq!(
            bytes, expected,
            "encoded MsgIssue bytes do not match the hand-computed wire format for the \
             fields tf_create_denom_msg populates"
        );

        let decoded = MsgIssue::try_from(Binary::from(bytes)).unwrap();
        assert_eq!(decoded.issuer, "issuer_addr");
        assert_eq!(decoded.symbol, "utoken");
        assert_eq!(decoded.subunit, "utoken");
        assert_eq!(decoded.precision, 6);
        assert_eq!(decoded.initial_amount, "0");
        assert_eq!(decoded.features, vec![Feature::Minting as i32]);
    }
}
