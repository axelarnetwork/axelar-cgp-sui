// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use axum::routing::post;
use axum::Router;
use clap::Parser;
use futures::future::try_join_all;
use rxrust::observable::ObservableItem;
use sui_keys::keystore::{AccountKeystore, InMemKeystore, Keystore};
use sui_sdk::types::base_types::{ObjectID, SuiAddress};
use sui_sdk::types::crypto::SignatureScheme;
use sui_sdk::{SuiClient, SuiClientBuilder};
use telemetry_subscribers::TelemetryConfig;
use tokio::sync::RwLock;
use tokio::task::JoinHandle;
use tracing::info;

use crate::handlers::process_commands;
use crate::listener::{
    ContractCall, OperatorshipTransferred, Subject, SuiAxelarEvent, SuiListener,
};
use crate::types::Error;

mod handlers;
mod listener;
mod types;

#[derive(Parser)]
#[clap(
    name = "sui-axelar-relayer",
    rename_all = "kebab-case",
    author,
    version
)]
pub struct SuiAxelarRelayer {
    #[clap(
        long,
        env,
        default_value = "you parade planet become era edit fuel birth arrow cry grunt snow"
    )]
    signer_mnemonic: String,
    #[clap(long, env, default_value = "https://rpc.testnet.sui.io:443")]
    sui_fn_url: String,
    #[clap(long, env, default_value = "wss://rpc.testnet.sui.io:443")]
    sui_ws_url: String,
    #[clap(long, env, default_value = "127.0.0.1:10000")]
    listen_address: SocketAddr,
    #[clap(
        long,
        env,
        default_value = "0x3ef8140369a7b5270fa2cea453a28de2c55b016d333523aea517f7abc55ce9f4"
    )]
    gateway_package_id: ObjectID,
    #[clap(
        long,
        env,
        default_value = "0x2e75b650c1e1bd2a6b737e629514fd3cdde7252e0b74a074fa6fb53a40921141"
    )]
    validators: ObjectID,
    #[clap(long, env, default_value = "897000")]
    validators_shared_version: u64,
}

#[derive(Clone)]
pub struct RelayerState {
    signer_address: SuiAddress,
    keystore: Arc<Keystore>,
    sui_client: Arc<RwLock<SuiClient>>,
    gateway_package_id: ObjectID,
    validators: ObjectID,
    validators_shared_version: u64,
}

impl SuiAxelarRelayer {
    pub async fn start(self) -> Result<(), Error> {
        info!("Starting Sui Axelar relayer");

        info!("Sui Fullnode: {}", self.sui_fn_url);
        let sui_client = SuiClientBuilder::default()
            .ws_ping_interval(Duration::from_secs(20))
            .ws_url(&self.sui_ws_url)
            .build(&self.sui_fn_url)
            .await?;

        let mut keystore = Keystore::InMem(InMemKeystore::default());
        let signer_address =
            keystore.import_from_mnemonic(&self.signer_mnemonic, SignatureScheme::ED25519, None)?;

        info!("Relayer signer Sui address: {signer_address}");

        let state = RelayerState {
            signer_address,
            keystore: Arc::new(keystore),
            sui_client: Arc::new(RwLock::new(sui_client.clone())),
            gateway_package_id: self.gateway_package_id,
            validators: self.validators,
            validators_shared_version: self.validators_shared_version,
        };

        let api = self.start_api_service(state).await;

        let (contract_call_handle, contract_call) = self
            .start_event_listener::<ContractCall>(sui_client.clone(), self.gateway_package_id)
            .await;

        contract_call.subscribe(|call| {
            // todo: pass to axelar
            println!("{call:?}")
        });

        let (operatorship_transferred_handle, operatorship_transferred) = self
            .start_event_listener::<OperatorshipTransferred>(sui_client, self.gateway_package_id)
            .await;

        operatorship_transferred.subscribe(|call| {
            // todo: pass to axelar
            println!("{call:?}")
        });

        try_join_all(vec![
            api,
            contract_call_handle,
            operatorship_transferred_handle,
        ])
        .await?;
        Ok(())
    }

    async fn start_event_listener<T: SuiAxelarEvent + Clone + 'static>(
        &self,
        client: SuiClient,
        gateway_package_id: ObjectID,
    ) -> (JoinHandle<()>, Subject<T>) {
        let sui_listener = SuiListener::new(client, gateway_package_id);
        let event = Subject::<T>::default();
        (tokio::spawn(sui_listener.listen(event.clone())), event)
    }

    async fn start_api_service(&self, state: RelayerState) -> JoinHandle<()> {
        let app = Router::new()
            .route("/process_commands", post(process_commands))
            .with_state(state);
        let server = axum::Server::bind(&self.listen_address).serve(app.into_make_service());
        let addr = server.local_addr();
        let handle = tokio::spawn(async move { server.await.unwrap() });

        info!("Sui Axelar relayer listening on {addr}");
        handle
    }
}

#[tokio::main]
pub async fn main() -> Result<(), Error> {
    let (_guard, _) = TelemetryConfig::new().with_env().init();
    SuiAxelarRelayer::parse().start().await
}
