// Original test content remains, adding new tests:

Clarinet.test({
  name: "Ensure empty strings are rejected in experience creation",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const provider = accounts.get('wallet_1')!;
    
    chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'verify-provider', [
        types.principal(provider.address)
      ], deployer.address)
    ]);
    
    let block = chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'create-experience', [
        types.utf8(""),
        types.utf8("Description"),
        types.utf8("Location"),
        types.uint(1000000),
        types.uint(10)
      ], provider.address)
    ]);
    
    block.receipts[0].result.expectErr().expectUint(107);
  }
});
