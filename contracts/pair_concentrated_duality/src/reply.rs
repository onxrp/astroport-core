use cosmwasm_std::{DepsMut, Env, Reply, Response, StdError, SubMsgResponse, SubMsgResult};

use astroport::pair_concentrated_duality::ReplyIds;
#[cfg(not(feature = "coreum"))]
use astroport::token_factory::MsgCreateDenomResponse;

use crate::error::ContractError;
#[cfg(feature = "coreum")]
use crate::instantiate::LP_SUBDENOM;
use crate::orderbook::state::OrderbookState;
use crate::orderbook::utils::{fetch_autoexecuted_trade, Liquidity};
use crate::state::CONFIG;

/// The entry point to the contract for processing replies from submessages.
#[cfg_attr(not(feature = "library"), cosmwasm_std::entry_point)]
pub fn reply(deps: DepsMut, env: Env, msg: Reply) -> Result<Response, ContractError> {
    match ReplyIds::try_from(msg.id)? {
        ReplyIds::CreateDenom => {
            let new_token_denom = match msg.result {
                SubMsgResult::Ok(SubMsgResponse { data, .. }) => {
                    #[cfg(not(feature = "coreum"))]
                    {
                        // Non-coreum chains expect the protobuf response in `data`
                        let b = data.ok_or(ContractError::FailedToParseReply {})?;
                        let MsgCreateDenomResponse { new_token_denom } = b.try_into()?;
                        new_token_denom
                    }
                    #[cfg(feature = "coreum")]
                    {
                        // Coreum doesn't return tokenfactory MsgCreateDenomResponse data.
                        format!("{}-{}", LP_SUBDENOM, env.contract.address)
                    }
                }
                SubMsgResult::Err(_) => return Err(ContractError::FailedToParseReply {}),
            };

            CONFIG.update(deps.storage, |mut config| {
                if !config.pair_info.liquidity_token.is_empty() {
                    return Err(StdError::generic_err(
                        "Liquidity token is already set in the config",
                    ));
                }

                config
                    .pair_info
                    .liquidity_token
                    .clone_from(&new_token_denom);

                Ok(config)
            })?;

            Ok(Response::new().add_attribute("lp_denom", new_token_denom))
        }
        ReplyIds::PostLimitOrderCb => {
            let mut ob_state = OrderbookState::load(deps.storage)?;
            ob_state.fetch_all_orders(deps.as_ref(), &env.contract.address)?;

            let config = CONFIG.load(deps.storage)?;
            let liquidity = Liquidity::new(deps.querier, &config, &mut ob_state, true)?;

            // We need to track auto-executed trades.
            // We delay their processing until the next contract call.
            ob_state.delayed_trade = fetch_autoexecuted_trade(
                &ob_state.pre_reply_balances,
                &liquidity.total(),
                ob_state.orders_number,
            );

            ob_state.save(deps.storage)?;

            Ok(Response::default().add_attribute("action", "post_limit_order_callback"))
        }
    }
}
